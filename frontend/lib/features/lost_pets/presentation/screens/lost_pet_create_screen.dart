import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/location/location_service.dart';
import '../../../../core/media/image_picker_options.dart';
import '../../../../core/media/selected_image_pipeline.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/storage/token_store.dart';
import '../../../../core/storage/token_store_provider.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../notifications/application/notification_push.dart';
import '../../../../core/widgets/form_icon_buttons.dart';
import '../../../../core/widgets/osm_attribution.dart';
import '../../../add_observation/application/pet_post_draft_controller.dart';
import '../../../add_observation/presentation/widgets/contact_share_notice.dart';
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
  final _formKey = GlobalKey<FormState>();
  bool _isPickingPhotos = false;
  String? _error;
  StreamSubscription<void>? _sessionChanges;

  PetPostDraftController get _draft => ref.read(lostPetDraftProvider.notifier);

  @override
  void initState() {
    super.initState();
    final store = ref.read(tokenStoreProvider);
    if (store is GuardedAuthTokenStore) {
      // The draft provider clears the draft itself on a session change.
      _sessionChanges = store.sessionChanges.listen((_) {
        if (!mounted) return;
        setState(() {
          _isPickingPhotos = false;
          _error = null;
        });
      });
    }
    // Natural moment for the deferred, one-time notification prompt.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(askForNotificationsOnce(context, ref));
    });
  }

  @override
  void dispose() {
    _sessionChanges?.cancel();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final draft = ref.read(lostPetDraftProvider);
    final attemptId = draft.publicationId;
    if (_isPickingPhotos || draft.locked) {
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
        limit: 5 - draft.photos.length,
      );
      if (files.isEmpty) {
        return;
      }
      final preparedPhotos = await preparePickedXFilesForUpload(
        files,
        limit: 5 - draft.photos.length,
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
      if (mounted &&
          ref.read(lostPetDraftProvider).publicationId == attemptId) {
        _draft.addPhotos(uploads);
      }
    } catch (error) {
      logPhotoPipelineFailure('lost_pet_gallery_picker', error);
      if (mounted) {
        setState(() => _error = selectedImageErrorMessage(strings, error));
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingPhotos = false);
      }
    }
  }

  Future<void> _submit() async {
    final strings = ref.read(appStringsProvider);
    final draft = ref.read(lostPetDraftProvider);
    if (draft.submitting || _isPickingPhotos || draft.completedUnavailable) {
      return;
    }
    if (draft.photos.isEmpty) {
      setState(() {
        _error = strings.addAtLeastOnePhoto;
      });
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (draft.location == null) {
      setState(() {
        _error = strings.pointLastSeenLocation;
      });
      return;
    }
    setState(() => _error = null);
    final published = await _draft.submit(strings: strings);
    if (!published) return;
    ref.invalidate(feedPostsProvider);
    _draft.reset();
    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      context.go('/feed');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(strings.postPublished)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final draft = ref.watch(lostPetDraftProvider);
    final photos = draft.photos;
    final draftLocked = draft.locked;
    final error = _error ?? draft.errorMessage;

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
                  for (var index = 0; index < photos.length; index++)
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            photos[index].bytes,
                            width: 92,
                            height: 92,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: PhotoRemoveButton(
                            position: index + 1,
                            total: photos.length,
                            strings: strings,
                            onPressed: draftLocked
                                ? null
                                : () => _draft.removePhotoAt(index),
                          ),
                        ),
                      ],
                    ),
                  OutlinedButton.icon(
                    onPressed:
                        draftLocked || _isPickingPhotos || photos.length >= 5
                            ? null
                            : _pickPhotos,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text('${strings.addPhotos} (${photos.length}/5)'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                key: ValueKey('${draft.publicationId}:petName'),
                enabled: !draftLocked,
                initialValue: draft.petName,
                onChanged: _draft.setPetName,
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
                ignoring: draftLocked,
                child: LostPetLocationPicker(
                  key: ValueKey(draft.publicationId),
                  strings: strings,
                  selectedLocation: draft.location,
                  onSelected: (location) {
                    if (ref.read(lostPetDraftProvider).locked) return;
                    setState(() => _error = null);
                    _draft.setLocation(location);
                  },
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                key: ValueKey('${draft.publicationId}:info'),
                enabled: !draftLocked,
                initialValue: draft.additionalInfo,
                onChanged: _draft.setAdditionalInfo,
                maxLines: 5,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: strings.additionalInformation,
                  alignLabelWithHint: true,
                ),
              ),
              // The profile phone is the consent: name what will be shared.
              const ContactShareNotice(),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: draft.submitting ||
                        _isPickingPhotos ||
                        draft.completedUnavailable
                    ? null
                    : () => unawaited(_submit()),
                icon: draft.submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.publish_outlined),
                label: Text(draft.completedUnavailable
                    ? strings.publicationAlreadyPublished
                    : draft.outcomeUnknown
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
                const OsmAttribution(),
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
