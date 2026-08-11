import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/location/location_service.dart';
import '../../../../core/media/image_upload_preprocessor.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
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
  bool _phonePublicationConsent = false;
  String? _error;

  @override
  void dispose() {
    _petNameController.dispose();
    _infoController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: true,
    );
    if (result == null) {
      return;
    }
    final uploads = <LostPetPhotoUpload>[];
    final availableSlots = 5 - _photos.length;
    for (final file in result.files
        .where((file) => file.bytes != null)
        .take(availableSlots)) {
      final prepared = await prepareImageForUpload(
        bytes: file.bytes as Uint8List,
        filename: file.name,
      );
      uploads.add(
        LostPetPhotoUpload(
          bytes: prepared.bytes,
          filename: prepared.filename,
          contentType: prepared.contentType,
        ),
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _photos.addAll(uploads);
    });
  }

  Future<void> _submit() async {
    final strings = ref.read(appStringsProvider);
    if (_isSubmitting) {
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
        _error = strings.confirmPhonePublic;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await ref.read(mushukistanApiProvider).createLostPet(
            photos: _photos,
            petName: _petNameController.text,
            lastSeenLocation: location,
            ownerPhonePublicationConsent: _phonePublicationConsent,
            additionalInfo: _infoController.text,
          );
      ref.invalidate(feedPostsProvider);
      if (mounted) {
        context.go('/feed');
      }
    } on MushukistanApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.userMessage;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) {
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
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
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
                          onPressed: () {
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
                  onPressed:
                      _isSubmitting || _photos.length >= 5 ? null : _pickPhotos,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text('${strings.addPhotos} (${_photos.length}/5)'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextFormField(
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
            _LostPetLocationPicker(
              strings: strings,
              selectedLocation: _selectedLocation,
              onSelected: (location) {
                setState(() {
                  _selectedLocation = location;
                  _error = null;
                });
              },
            ),
            const SizedBox(height: 24),
            TextFormField(
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
              onChanged: _isSubmitting
                  ? null
                  : (value) {
                      setState(() {
                        _phonePublicationConsent = value ?? false;
                        _error = null;
                      });
                    },
              title: Text(strings.phonePublicConsent),
              subtitle: Text(strings.phonePublicConsentSubtitle),
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
              onPressed: _isSubmitting ? null : () => unawaited(_submit()),
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.publish_outlined),
              label: Text(strings.publishLostPet),
            ),
          ],
        ),
      ),
    );
  }
}

class _LostPetLocationPicker extends StatefulWidget {
  const _LostPetLocationPicker({
    required this.strings,
    required this.selectedLocation,
    required this.onSelected,
  });

  final AppStrings strings;
  final GeoPoint? selectedLocation;
  final ValueChanged<GeoPoint> onSelected;

  @override
  State<_LostPetLocationPicker> createState() => _LostPetLocationPickerState();
}

class _LostPetLocationPickerState extends State<_LostPetLocationPicker> {
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
          borderRadius: BorderRadius.circular(8),
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
