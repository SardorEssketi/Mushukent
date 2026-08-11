import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/location/location_service.dart';
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
    this.selectedCatId,
    this.useNewCat = true,
    this.newCatName = '',
    this.newCatStatus = 'unknown',
    this.isPublic = true,
    this.nearbyCats = const AsyncValue<ApiPage<CatSummary>?>.data(null),
    this.submitting = false,
    this.errorMessage,
    this.createdPostId,
  });

  final List<ObservationPhotoUpload> photos;
  final GeoPoint? location;
  final String description;
  final String? selectedCatId;
  final bool useNewCat;
  final String newCatName;
  final String newCatStatus;
  final bool isPublic;
  final AsyncValue<ApiPage<CatSummary>?> nearbyCats;
  final bool submitting;
  final String? errorMessage;
  final String? createdPostId;

  bool get hasPhoto => photos.isNotEmpty;
  bool get hasLocation => location != null;

  AddObservationState copyWith({
    List<ObservationPhotoUpload>? photos,
    GeoPoint? location,
    String? description,
    String? selectedCatId,
    bool clearSelectedCatId = false,
    bool? useNewCat,
    String? newCatName,
    String? newCatStatus,
    bool? isPublic,
    AsyncValue<ApiPage<CatSummary>?>? nearbyCats,
    bool? submitting,
    String? errorMessage,
    String? createdPostId,
  }) {
    return AddObservationState(
      photos: photos ?? this.photos,
      location: location ?? this.location,
      description: description ?? this.description,
      selectedCatId:
          clearSelectedCatId ? null : selectedCatId ?? this.selectedCatId,
      useNewCat: useNewCat ?? this.useNewCat,
      newCatName: newCatName ?? this.newCatName,
      newCatStatus: newCatStatus ?? this.newCatStatus,
      isPublic: isPublic ?? this.isPublic,
      nearbyCats: nearbyCats ?? this.nearbyCats,
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

  void setDescription(String description) {
    state = state.copyWith(description: description);
  }

  void setSelectedCat(String? catId) {
    state = state.copyWith(
      selectedCatId: catId,
      useNewCat: catId == null,
      errorMessage: null,
    );
  }

  void setUseNewCat(bool value) {
    state = state.copyWith(
      useNewCat: value,
      clearSelectedCatId: value,
    );
  }

  void setNewCatName(String value) {
    state = state.copyWith(newCatName: value);
  }

  void setNewCatStatus(String value) {
    state = state.copyWith(newCatStatus: value);
  }

  void setIsPublic(bool value) {
    state = state.copyWith(isPublic: value);
  }

  Future<void> loadNearbyCats() async {
    final location =
        state.location ?? await LocationService().resolveCurrentLocation();
    state = state.copyWith(
      location: location,
      nearbyCats: const AsyncValue.loading(),
      errorMessage: null,
    );
    try {
      final page = await _api.listCats(
        filter: 'nearby',
        lat: location.latitude,
        lon: location.longitude,
        radiusMeters: 1500,
        limit: 12,
      );
      state = state.copyWith(nearbyCats: AsyncValue.data(page));
    } catch (error, stackTrace) {
      state = state.copyWith(
        nearbyCats: AsyncValue.error(error, stackTrace),
        errorMessage: error.toString(),
      );
    }
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
        existingCatId: state.useNewCat ? null : state.selectedCatId,
        newCatName:
            state.useNewCat ? state.newCatName.trim().ifEmptyNull : null,
        newCatStatus: state.useNewCat ? state.newCatStatus : null,
        newCatLocation: state.useNewCat ? location : null,
        isPublic: state.isPublic,
        postStatus: state.useNewCat ? state.newCatStatus : null,
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

extension on String {
  String? get ifEmptyNull => trim().isEmpty ? null : trim();
}
