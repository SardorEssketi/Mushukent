import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/media/selected_image_pipeline.dart';
import '../../../core/network/mushukistan_api.dart';
import '../../../core/network/publication_retry.dart';
import '../../../core/network/publication_session.dart';
import '../../../core/storage/token_store.dart';
import '../../../core/storage/token_store_provider.dart';

final addObservationControllerProvider =
    StateNotifierProvider<AddObservationController, AddObservationState>((ref) {
  final controller =
      AddObservationController(ref.watch(mushukistanApiProvider));
  final store = ref.watch(tokenStoreProvider);
  if (store is GuardedAuthTokenStore) {
    final changes = store.sessionChanges.listen((_) => controller.reset());
    ref.onDispose(changes.cancel);
  }
  return controller;
});

class AddObservationState {
  AddObservationState({
    String? publicationId,
    this.photos = const [],
    this.location,
    this.kind = 'observation',
    this.catName = '',
    this.description = '',
    this.isPublic = true,
    this.submitting = false,
    this.outcomeUnknown = false,
    this.completedUnavailable = false,
    this.errorMessage,
  }) : publicationId = publicationId ?? newPublicationKey();

  final String publicationId;

  final List<ObservationPhotoUpload> photos;
  final GeoPoint? location;
  final String kind;
  final String catName;
  final String description;
  final bool isPublic;
  final bool submitting;
  final bool outcomeUnknown;
  final bool completedUnavailable;
  bool get locked => submitting || outcomeUnknown || completedUnavailable;
  final String? errorMessage;

  bool get hasPhoto => photos.isNotEmpty;
  bool get hasLocation => location != null;
  bool get hasDraft =>
      photos.isNotEmpty ||
      location != null ||
      kind != 'observation' ||
      catName.trim().isNotEmpty ||
      description.trim().isNotEmpty ||
      !isPublic;

  AddObservationState copyWith({
    String? publicationId,
    List<ObservationPhotoUpload>? photos,
    GeoPoint? location,
    String? kind,
    bool clearLocation = false,
    String? catName,
    String? description,
    bool? isPublic,
    bool? submitting,
    bool? outcomeUnknown,
    bool? completedUnavailable,
    String? errorMessage,
  }) {
    return AddObservationState(
      publicationId: publicationId ?? this.publicationId,
      photos: photos ?? this.photos,
      location: clearLocation ? null : location ?? this.location,
      kind: kind ?? this.kind,
      catName: catName ?? this.catName,
      description: description ?? this.description,
      isPublic: isPublic ?? this.isPublic,
      submitting: submitting ?? this.submitting,
      outcomeUnknown: outcomeUnknown ?? this.outcomeUnknown,
      completedUnavailable: completedUnavailable ?? this.completedUnavailable,
      errorMessage: errorMessage,
    );
  }
}

class AddObservationController extends StateNotifier<AddObservationState> {
  AddObservationController(this._api) : super(AddObservationState());

  final MushukistanApi _api;

  void setPhoto({
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) {
    setPhotos([
      ObservationPhotoUpload(
        bytes: bytes,
        filename: filename,
        contentType: contentType,
      ),
    ]);
  }

  void setPhotos(List<ObservationPhotoUpload> photos) {
    state = state.copyWith(photos: photos.take(5).toList(), errorMessage: null);
  }

  void setLocation(GeoPoint location) {
    state = state.copyWith(location: location, errorMessage: null);
  }

  void clearLocation() {
    state = state.copyWith(clearLocation: true, errorMessage: null);
  }

  void setKind(String kind) {
    state = state.copyWith(kind: kind, errorMessage: null);
  }

  void setDescription(String description) {
    state = state.copyWith(description: description);
  }

  void setCatName(String catName) {
    state = state.copyWith(catName: catName);
  }

  void setIsPublic(bool value) {
    state = state.copyWith(isPublic: value);
  }

  Future<PostDetail> submit({required AppStrings strings}) async {
    if (state.completedUnavailable) {
      throw const PublicationCompletedUnavailable();
    }
    final attemptId = state.publicationId;
    if (state.submitting) {
      throw StateError('Post submission is already in progress.');
    }
    final location = state.location;
    if (state.photos.isEmpty) {
      throw StateError('A post photo is required.');
    }
    if (state.kind == 'needs_help' && location == null) {
      throw StateError('Cat needs help posts require a location.');
    }
    if (state.kind == 'needs_help' && state.description.trim().isEmpty) {
      throw StateError('Cat needs help posts require help details.');
    }

    state = state.copyWith(submitting: true, errorMessage: null);
    try {
      final post = await _api.createObservation(
        publicationId: state.publicationId,
        photos: state.photos,
        location: location,
        kind: state.kind,
        catName: state.catName.trim().isEmpty ? null : state.catName.trim(),
        description:
            state.description.trim().isEmpty ? null : state.description.trim(),
        isPublic: state.isPublic,
      );
      if (state.publicationId != attemptId) throw publicationSessionChanged;
      state = state.copyWith(submitting: false, outcomeUnknown: false);
      return post;
    } catch (error) {
      if (state.publicationId != attemptId) rethrow;
      state = state.copyWith(
        submitting: false,
        publicationId: publicationAllowsReplacement(error)
            ? newPublicationKey()
            : state.publicationId,
        completedUnavailable: publicationCompletedUnavailable(error),
        outcomeUnknown: publicationOutcomeUncertain(error),
        errorMessage: publicationErrorMessage(strings, error),
      );
      rethrow;
    }
  }

  void reset({String kind = 'observation'}) {
    state = AddObservationState(kind: kind);
  }
}
