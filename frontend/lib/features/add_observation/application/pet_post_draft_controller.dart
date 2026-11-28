import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/media/selected_image_pipeline.dart';
import '../../../core/network/api_error.dart';
import '../../../core/network/mushukistan_api.dart';
import '../../../core/network/publication_retry.dart';
import '../../../core/storage/token_store.dart';
import '../../../core/storage/token_store_provider.dart';

/// The contact-based post types whose create forms keep an in-memory draft.
enum PetPostType { lostPet, adoption }

/// One draft per type, so a Lost Pet draft never overwrites a Rehoming one
/// (or the Cat post draft in [addObservationControllerProvider]).
final lostPetDraftProvider =
    StateNotifierProvider<PetPostDraftController, PetPostDraftState>(
        (ref) => _create(ref, PetPostType.lostPet));

final adoptionPostDraftProvider =
    StateNotifierProvider<PetPostDraftController, PetPostDraftState>(
        (ref) => _create(ref, PetPostType.adoption));

StateNotifierProvider<PetPostDraftController, PetPostDraftState>
    petPostDraftProvider(PetPostType type) => switch (type) {
          PetPostType.lostPet => lostPetDraftProvider,
          PetPostType.adoption => adoptionPostDraftProvider,
        };

PetPostDraftController _create(Ref ref, PetPostType type) {
  final controller =
      PetPostDraftController(ref.watch(mushukistanApiProvider), type);
  final store = ref.watch(tokenStoreProvider);
  if (store is GuardedAuthTokenStore) {
    final changes = store.sessionChanges.listen((_) => controller.reset());
    ref.onDispose(changes.cancel);
  }
  return controller;
}

class PetPostDraftState {
  PetPostDraftState({
    String? publicationId,
    this.photos = const [],
    this.location,
    this.petName = '',
    this.additionalInfo = '',
    this.submitting = false,
    this.outcomeUnknown = false,
    this.completedUnavailable = false,
    this.errorMessage,
  }) : publicationId = publicationId ?? newPublicationKey();

  final String publicationId;
  final List<LostPetPhotoUpload> photos;

  /// Last-seen location; only Lost Pet uses it.
  final GeoPoint? location;
  final String petName;
  final String additionalInfo;
  final bool submitting;
  final bool outcomeUnknown;
  final bool completedUnavailable;
  final String? errorMessage;

  bool get locked => submitting || outcomeUnknown || completedUnavailable;

  /// Same rule as Cat posts: only content the user added makes a draft.
  bool get hasDraft =>
      photos.isNotEmpty ||
      location != null ||
      petName.trim().isNotEmpty ||
      additionalInfo.trim().isNotEmpty;

  PetPostDraftState copyWith({
    String? publicationId,
    List<LostPetPhotoUpload>? photos,
    GeoPoint? location,
    String? petName,
    String? additionalInfo,
    bool? submitting,
    bool? outcomeUnknown,
    bool? completedUnavailable,
    String? errorMessage,
  }) {
    return PetPostDraftState(
      publicationId: publicationId ?? this.publicationId,
      photos: photos ?? this.photos,
      location: location ?? this.location,
      petName: petName ?? this.petName,
      additionalInfo: additionalInfo ?? this.additionalInfo,
      submitting: submitting ?? this.submitting,
      outcomeUnknown: outcomeUnknown ?? this.outcomeUnknown,
      completedUnavailable: completedUnavailable ?? this.completedUnavailable,
      errorMessage: errorMessage,
    );
  }
}

class PetPostDraftController extends StateNotifier<PetPostDraftState> {
  PetPostDraftController(this._api, this.type) : super(PetPostDraftState());

  final MushukistanApi _api;
  final PetPostType type;

  void addPhotos(List<LostPetPhotoUpload> photos) {
    state = state.copyWith(
        photos: [...state.photos, ...photos].take(5).toList(),
        errorMessage: null);
  }

  void removePhotoAt(int index) {
    state = state.copyWith(photos: [...state.photos]..removeAt(index));
  }

  void setLocation(GeoPoint location) {
    state = state.copyWith(location: location, errorMessage: null);
  }

  void setPetName(String value) {
    state = state.copyWith(petName: value);
  }

  void setAdditionalInfo(String value) {
    state = state.copyWith(additionalInfo: value);
  }

  /// Publishes the draft with its publicationId (the idempotency key). Errors
  /// land in [PetPostDraftState.errorMessage]; the caller only learns success.
  Future<bool> submit({
    required AppStrings strings,
  }) async {
    if (state.submitting || state.completedUnavailable) return false;
    final attemptId = state.publicationId;
    state = state.copyWith(submitting: true, errorMessage: null);
    try {
      switch (type) {
        case PetPostType.lostPet:
          await _api.createLostPet(
            publicationId: attemptId,
            photos: state.photos,
            petName: state.petName,
            lastSeenLocation: state.location!,
            additionalInfo: state.additionalInfo,
          );
        case PetPostType.adoption:
          await _api.createAdoptionPost(
            publicationId: attemptId,
            photos: state.photos,
            petName: state.petName,
            additionalInfo: state.additionalInfo,
          );
      }
      if (state.publicationId != attemptId) return false;
      state = state.copyWith(submitting: false, outcomeUnknown: false);
      return true;
    } on MushukistanApiException catch (error) {
      if (state.publicationId != attemptId) return false;
      state = state.copyWith(
        submitting: false,
        publicationId: publicationAllowsReplacement(error)
            ? newPublicationKey()
            : attemptId,
        outcomeUnknown: publicationOutcomeUncertain(error),
        completedUnavailable: publicationCompletedUnavailable(error),
        errorMessage: publicationErrorMessage(strings, error),
      );
      return false;
    } catch (_) {
      if (state.publicationId != attemptId) return false;
      state = state.copyWith(
          submitting: false, errorMessage: strings.couldNotSaveChanges);
      return false;
    }
  }

  /// Clears the draft; the next one gets a fresh publicationId.
  void reset() {
    state = PetPostDraftState();
  }
}
