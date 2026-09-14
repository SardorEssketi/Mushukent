import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/mushukistan_api.dart';

final addObservationControllerProvider =
    StateNotifierProvider<AddObservationController, AddObservationState>((ref) {
  return AddObservationController(ref.watch(mushukistanApiProvider));
});

class AddObservationState {
  const AddObservationState({
    this.photos = const [],
    this.location,
    this.description = '',
    this.isPublic = true,
    this.submitting = false,
    this.errorMessage,
    this.createdPostId,
  });

  final List<ObservationPhotoUpload> photos;
  final GeoPoint? location;
  final String description;
  final bool isPublic;
  final bool submitting;
  final String? errorMessage;
  final String? createdPostId;

  bool get hasPhoto => photos.isNotEmpty;
  bool get hasLocation => location != null;
  bool get hasDraft =>
      photos.isNotEmpty ||
      location != null ||
      description.trim().isNotEmpty ||
      !isPublic;

  AddObservationState copyWith({
    List<ObservationPhotoUpload>? photos,
    GeoPoint? location,
    bool clearLocation = false,
    String? description,
    bool? isPublic,
    bool? submitting,
    String? errorMessage,
    String? createdPostId,
  }) {
    return AddObservationState(
      photos: photos ?? this.photos,
      location: clearLocation ? null : location ?? this.location,
      description: description ?? this.description,
      isPublic: isPublic ?? this.isPublic,
      submitting: submitting ?? this.submitting,
      errorMessage: errorMessage,
      createdPostId: createdPostId ?? this.createdPostId,
    );
  }
}

class AddObservationController extends StateNotifier<AddObservationState> {
  AddObservationController(this._api) : super(const AddObservationState());

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

  void setDescription(String description) {
    state = state.copyWith(description: description);
  }

  void setIsPublic(bool value) {
    state = state.copyWith(isPublic: value);
  }

  Future<PostDetail> submit() async {
    final location = state.location;
    if (state.photos.isEmpty) {
      throw StateError('Missing observation data.');
    }

    state = state.copyWith(submitting: true, errorMessage: null);
    try {
      final post = await _api.createObservation(
        photos: state.photos,
        location: location,
        description:
            state.description.trim().isEmpty ? null : state.description.trim(),
        isPublic: state.isPublic,
      );
      state = state.copyWith(
        submitting: false,
        createdPostId: post.id,
      );
      return post;
    } catch (error) {
      state = state.copyWith(
        submitting: false,
        errorMessage: error.toString(),
      );
      rethrow;
    }
  }

  void reset() {
    state = const AddObservationState();
  }
}
