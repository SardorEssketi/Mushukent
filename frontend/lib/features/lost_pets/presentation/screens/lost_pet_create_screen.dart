import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/location/location_service.dart';
import '../../../../core/media/image_picker_options.dart';
import '../../../../core/media/selected_image_pipeline.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/publication_retry.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/storage/token_store.dart';
import '../../../../core/storage/token_store_provider.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../feed/presentation/screens/feed_screen.dart';

final _tashkentBounds = LatLngBounds(
  const LatLng(41.1800, 69.0500),
  const LatLng(41.4300, 69.4200),
);

class LostPetCreateScreen extends ConsumerStatefulWidget {
  const LostPetCreateScreen({super.key});

  @override
  ConsumerState<LostPetCreateScreen> createState() =>
      _LostPetCreateScreenState();
}

class _LostPetCreateScreenState extends ConsumerState<LostPetCreateScreen> {
  final _petNameController = TextEditingController();
  final _infoController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final List<LostPetPhotoUpload> _photos = [];
  GeoPoint? _selectedLocation;
  bool _isSubmitting = false;
  bool _outcomeUnknown = false;
  bool _completedUnavailable = false;
  bool get _draftLocked =>
      _isSubmitting || _outcomeUnknown || _completedUnavailable;
  String _publicationId = newPublicationKey();
  bool _isPickingPhotos = false;
  bool _phonePublicationConsent = false;
  String? _error;
  StreamSubscription<void>? _sessionChanges;
  int _draftGeneration = 0;

  @override
  void initState() {
    super.initState();
    final store = ref.read(tokenStoreProvider);
    if (store is GuardedAuthTokenStore) {
      _sessionChanges = store.sessionChanges.listen((_) {
        if (!mounted) return;
        setState(() {
          _draftGeneration++;
          _photos.clear();
          _petNameController.clear();
          _infoController.clear();
          _selectedLocation = null;
          _publicationId = newPublicationKey();
          _isSubmitting = false;
          _isPickingPhotos = false;
          _outcomeUnknown = false;
          _completedUnavailable = false;
          _phonePublicationConsent = false;
          _error = null;
        });
      });
    }
  }

  @override
  void dispose() {
    _sessionChanges?.cancel();
    _petNameController.dispose();
    _infoController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final generation = _draftGeneration;
    if (_isPickingPhotos || _draftLocked) {
      return;
    }
    final strings = ref.read(appStringsProvider);
    setState(() {
      _isPickingPhotos = true;
      _error = null;
    });
    try {
      final files = await ImagePicker().pickMultiImage(
        imageQuality: pickerImageQuality,
        maxWidth: pickerMaxWidth,
        maxHeight: pickerMaxHeight,
        limit: 5 - _photos.length,
      );
      if (files.isEmpty) {
        return;
      }
      final preparedPhotos = await preparePickedXFilesForUpload(
        files,
        limit: 5 - _photos.length,
      );
      final uploads = preparedPhotos
          .map(
            (prepared) => LostPetPhotoUpload(
              bytes: prepared.bytes,
              filename: prepared.filename,
              contentType: prepared.contentType,
            ),
          )
          .toList(growable: false);
      if (mounted && _draftGeneration == generation) {
        setState(() {
          _photos.addAll(uploads);
        });
      }
    } catch (error) {
      logPhotoPipelineFailure('lost_pet_gallery_picker', error);
      if (mounted) {
        setState(() => _error = selectedImageErrorMessage(strings, error));
      }
    } finally {
      if (mounted && _draftGeneration == generation) {
        setState(() => _isPickingPhotos = false);
      }
    }
  }

  Future<void> _submit() async {
    final generation = _draftGeneration;
    final strings = ref.read(appStringsProvider);
    if (_isSubmitting || _isPickingPhotos || _completedUnavailable) {
      return;
    }
    if (_photos.isEmpty) {
      setState(() {
        _error = strings.addAtLeastOnePhoto;
      });
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final location = _selectedLocation;
    if (location == null) {
      setState(() {
        _error = strings.pointLastSeenLocation;
      });
      return;
    }
    if (!_phonePublicationConsent) {
      setState(() {
        _error = strings.confirmContactConsent;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await ref.read(mushukistanApiProvider).createLostPet(
            publicationId: _publicationId,
            photos: _photos,
            petName: _petNameController.text,
            lastSeenLocation: location,
            ownerPhonePublicationConsent: _phonePublicationConsent,
            additionalInfo: _infoController.text,
          );
      if (_draftGeneration != generation) return;
      ref.invalidate(feedPostsProvider);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        context.go('/feed');
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(strings.postPublished)));
      }
    } on MushukistanApiException catch (error) {
      if (_draftGeneration != generation) return;
      if (mounted) {
        setState(() {
          _outcomeUnknown = publicationOutcomeUncertain(error);
          _completedUnavailable = publicationCompletedUnavailable(error);
          if (publicationAllowsReplacement(error)) {
            _publicationId = newPublicationKey();
          }
          _error = publicationErrorMessage(strings, error);
        });
      }
    } catch (_) {
      if (_draftGeneration != generation) return;
      if (mounted) {
        setState(() {
          _error = strings.couldNotSaveChanges;
        });
      }
    } finally {
      if (mounted && _draftGeneration == generation) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.lostPet)),
      body: AppContentWidth(
        maxWidth: AppWidths.readable,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              AppBadge(
                label: strings.lostPet,
                icon: Icons.search_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                strings.createLostPetAlert,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                strings.createLostPetAlertHelp,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(strings.photos,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < _photos.length; index++)
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            _photos[index].bytes,
                            width: 92,
                            height: 92,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: IconButton.filledTonal(
                            onPressed: _draftLocked
                                ? null
                                : () {
                                    setState(() {
                                      _photos.removeAt(index);
                                    });
                                  },
                            icon: const Icon(Icons.close, size: 16),
                          ),
                        ),
                      ],
                    ),
                  OutlinedButton.icon(
                    onPressed: _isSubmitting ||
                            _outcomeUnknown ||
                            _completedUnavailable ||
                            _isPickingPhotos ||
                            _photos.length >= 5
                        ? null
                        : _pickPhotos,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text('${strings.addPhotos} (${_photos.length}/5)'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                enabled: !_draftLocked,
                controller: _petNameController,
                maxLength: 100,
                decoration: InputDecoration(
                  labelText: strings.petsName,
                  hintText: 'Mittens',
                ),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.isEmpty) {
                    return strings.enterPetsName;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Text(strings.lastSeen,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              IgnorePointer(
                ignoring: _draftLocked,
                child: LostPetLocationPicker(
                  key: ValueKey(_publicationId),
                  strings: strings,
                  selectedLocation: _selectedLocation,
                  onSelected: (location) {
                    if (_draftLocked) return;
                    setState(() {
                      _selectedLocation = location;
                      _error = null;
                    });
                  },
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                enabled: !_draftLocked,
                controller: _infoController,
                maxLines: 5,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: strings.additionalInformation,
                  alignLabelWithHint: true,
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _phonePublicationConsent,
                onChanged: _draftLocked
                    ? null
                    : (value) {
                        setState(() {
                          _phonePublicationConsent = value ?? false;
                          _error = null;
                        });
                      },
                title: Text(strings.contactConsentTitle),
                subtitle: Text(strings.contactConsentSubtitle),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed:
                    _isSubmitting || _isPickingPhotos || _completedUnavailable
                        ? null
                        : () => unawaited(_submit()),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.publish_outlined),
                label: Text(_completedUnavailable
                    ? strings.publicationAlreadyPublished
                    : _outcomeUnknown
                        ? strings.checkPublicationStatus
                        : strings.publishLostPet),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LostPetLocationPicker extends StatefulWidget {
  const LostPetLocationPicker({
    super.key,
    required this.strings,
    required this.selectedLocation,
    required this.onSelected,
  });

  final AppStrings strings;
  final GeoPoint? selectedLocation;
  final ValueChanged<GeoPoint> onSelected;

  @override
  State<LostPetLocationPicker> createState() => _LostPetLocationPickerState();
}

class _LostPetLocationPickerState extends State<LostPetLocationPicker> {
  static const _initialCenter = LatLng(41.3111, 69.2797);
  final MapController _mapController = MapController();
  bool _locating = false;

  Future<void> _useCurrentLocation() async {
    if (_locating) {
      return;
    }
    setState(() {
      _locating = true;
    });
    try {
      final location = await LocationService().resolveCurrentLocation();
      if (location == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(widget.strings.couldNotResolveLocation)),
          );
        }
        return;
      }
      widget.onSelected(location);
      _mapController.move(
        LatLng(location.latitude, location.longitude),
        16,
      );
    } finally {
      if (mounted) {
        setState(() {
          _locating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = widget.selectedLocation;
    final selectedPoint =
        selected == null ? null : LatLng(selected.latitude, selected.longitude);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: SizedBox(
            height: 320,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: selectedPoint ?? _initialCenter,
                initialZoom: 13.5,
                cameraConstraint: CameraConstraint.contain(
                  bounds: _tashkentBounds,
                ),
                minZoom: 11,
                maxZoom: 18,
                onTap: (_, point) {
                  widget.onSelected(
                    GeoPoint(
                      latitude: point.latitude,
                      longitude: point.longitude,
                    ),
                  );
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'mushukistan_frontend',
                ),
                if (selectedPoint != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: selectedPoint,
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.location_on,
                          color: colorScheme.error,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      'OpenStreetMap contributors',
                      onTap: () => _openOsmCopyright(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.touch_app_outlined,
                size: 18, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                selected == null
                    ? widget.strings.tapMapForLastSeen
                    : widget.strings.lastSeenLocationSelected,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _locating ? null : _useCurrentLocation,
                icon: _locating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_outlined),
                label: Text(widget.strings.centerOnUser),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> _openOsmCopyright() async {
  await launchUrl(
    Uri.parse('https://www.openstreetmap.org/copyright'),
    mode: LaunchMode.externalApplication,
  );
}
