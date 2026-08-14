import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

import 'api_client.dart';

final mushukistanApiProvider = Provider<MushukistanApi>((ref) {
  return MushukistanApi(
    client: ref.watch(apiClientProvider),
  );
});

class MushukistanApi {
  MushukistanApi({required MushukistanApiClient client}) : _client = client;

  final MushukistanApiClient _client;

  Future<ApiPage<CatSummary>> listCats({
    String filter = 'nearby',
    double? lat,
    double? lon,
    int? radiusMeters,
    String? bbox,
    int limit = 20,
    String? cursor,
  }) {
    return _client.get<ApiPage<CatSummary>>(
      'cats',
      authenticated: false,
      queryParameters: <String, dynamic>{
        'filter': filter,
        if (lat != null) 'lat': lat,
        if (lon != null) 'lon': lon,
        if (radiusMeters != null) 'radius_meters': radiusMeters,
        if (bbox != null) 'bbox': bbox,
        'limit': limit,
        if (cursor != null) 'cursor': cursor,
      },
      decoder: (json) => ApiPage.fromJson(
        json,
        (item) => CatSummary.fromJson(item),
      ),
    );
  }

  Future<ApiPage<PlaceSummary>> listPlaces({
    List<String>? categories,
    double? lat,
    double? lon,
    int? radiusMeters,
    String? bbox,
    int limit = 100,
  }) {
    return _client.get<ApiPage<PlaceSummary>>(
      'places',
      authenticated: false,
      queryParameters: <String, dynamic>{
        if (categories != null && categories.isNotEmpty) 'category': categories,
        if (lat != null) 'lat': lat,
        if (lon != null) 'lon': lon,
        if (radiusMeters != null) 'radius_meters': radiusMeters,
        if (bbox != null) 'bbox': bbox,
        'limit': limit,
      },
      decoder: (json) => ApiPage.fromJson(
        json,
        (item) => PlaceSummary.fromJson(item),
      ),
    );
  }

  Future<ApiPage<FeedItem>> listFeed({
    String filter = 'recent',
    String? popularPeriod,
    double? lat,
    double? lon,
    int? radiusMeters,
    int limit = 20,
    String? cursor,
  }) {
    return _client.get<ApiPage<FeedItem>>(
      'feed',
      queryParameters: <String, dynamic>{
        'filter': filter,
        if (popularPeriod != null) 'popular_period': popularPeriod,
        if (lat != null) 'lat': lat,
        if (lon != null) 'lon': lon,
        if (radiusMeters != null) 'radius_meters': radiusMeters,
        'limit': limit,
        if (cursor != null) 'cursor': cursor,
      },
      decoder: (json) => ApiPage.fromJson(
        json,
        (item) => FeedItem.fromJson(item),
      ),
    );
  }

  Future<PostDetail> getPost(String postId) {
    return _client.get<PostDetail>(
      'posts/$postId',
      decoder: (json) => PostDetail.fromJson(json),
    );
  }

  Future<LostPetData> getLostPet(String lostPetId) {
    return _client.get<LostPetData>(
      'lost-pets/$lostPetId',
      authenticated: false,
      decoder: (json) => LostPetData.fromJson(json),
    );
  }

  Future<AdoptionPostData> getAdoptionPost(String adoptionPostId) {
    return _client.get<AdoptionPostData>(
      'adoption-posts/$adoptionPostId',
      authenticated: false,
      decoder: (json) => AdoptionPostData.fromJson(json),
    );
  }

  Future<ApiPage<FeedItem>> listLostPets({
    double? lat,
    double? lon,
    int? radiusMeters,
    int limit = 20,
    String? cursor,
    bool validForMap = false,
  }) {
    return _client.get<ApiPage<FeedItem>>(
      'lost-pets',
      authenticated: false,
      queryParameters: <String, dynamic>{
        if (lat != null) 'lat': lat,
        if (lon != null) 'lon': lon,
        if (radiusMeters != null) 'radius_meters': radiusMeters,
        'limit': limit,
        if (validForMap) 'valid_for_map': true,
        if (cursor != null) 'cursor': cursor,
      },
      decoder: (json) => ApiPage.fromJson(
        json,
        (item) => LostPetData.fromJson(item),
      ),
    );
  }

  Future<ApiPage<FeedItem>> listAdoptionPosts({
    int limit = 20,
    String? cursor,
  }) {
    return _client.get<ApiPage<FeedItem>>(
      'adoption-posts',
      authenticated: false,
      queryParameters: <String, dynamic>{
        'limit': limit,
        if (cursor != null) 'cursor': cursor,
      },
      decoder: (json) => ApiPage.fromJson(
        json,
        (item) => AdoptionPostData.fromJson(item),
      ),
    );
  }

  Future<ApiPage<PostSummary>> listUserPosts(
    String userId, {
    int limit = 20,
    String? cursor,
    String sort = 'latest',
  }) {
    return _client.get<ApiPage<PostSummary>>(
      'users/$userId/posts',
      queryParameters: <String, dynamic>{
        'limit': limit,
        'sort': sort,
        if (cursor != null) 'cursor': cursor,
      },
      decoder: (json) => ApiPage.fromJson(
        json,
        (item) => PostSummary.fromJson(item),
      ),
    );
  }

  Future<ApiPage<PostSummary>> listCatPosts(
    String catId, {
    int limit = 20,
    String? cursor,
    String sort = 'latest',
  }) {
    return _client.get<ApiPage<PostSummary>>(
      'cats/$catId/posts',
      queryParameters: <String, dynamic>{
        'limit': limit,
        'sort': sort,
        if (cursor != null) 'cursor': cursor,
      },
      decoder: (json) => ApiPage.fromJson(
        json,
        (item) => PostSummary.fromJson(item),
      ),
    );
  }

  Future<List<LeaderboardEntryData>> listLeaderboard(
    String type, {
    String period = 'week',
    int limit = 20,
  }) {
    return _client.get<List<LeaderboardEntryData>>(
      'leaderboards/$type',
      authenticated: false,
      queryParameters: <String, dynamic>{
        'period': period,
        'limit': limit,
      },
      decoder: (json) {
        final list = _readList(json);
        return list.map(LeaderboardEntryData.fromJson).toList(growable: false);
      },
    );
  }

  Future<UserProfileData> getMe() {
    return _client.get<UserProfileData>(
      'users/me',
      decoder: (json) => UserProfileData.fromJson(json),
    );
  }

  Future<UserPublicData> getPublicProfile(String userId) {
    return _client.get<UserPublicData>(
      'users/$userId',
      authenticated: false,
      decoder: (json) => UserPublicData.fromJson(json),
    );
  }

  Future<ApiPage<PostSummary>> listPublicProfilePosts(
    String userId, {
    int limit = 20,
    String? cursor,
    String sort = 'latest',
  }) {
    return listUserPosts(userId, limit: limit, cursor: cursor, sort: sort);
  }

  Future<ApiPage<CommentData>> listComments(
    String postId, {
    int limit = 20,
    String? cursor,
    String order = 'asc',
  }) {
    return _client.get<ApiPage<CommentData>>(
      'posts/$postId/comments',
      authenticated: false,
      queryParameters: <String, dynamic>{
        'limit': limit,
        'order': order,
        if (cursor != null) 'cursor': cursor,
      },
      decoder: (json) => ApiPage.fromJson(
        json,
        (item) => CommentData.fromJson(item),
      ),
    );
  }

  Future<ApiPage<CommentData>> listUserComments(
    String userId, {
    int limit = 20,
    String? cursor,
    String order = 'desc',
  }) {
    return _client.get<ApiPage<CommentData>>(
      'users/$userId/comments',
      queryParameters: <String, dynamic>{
        'limit': limit,
        'order': order,
        if (cursor != null) 'cursor': cursor,
      },
      decoder: (json) => ApiPage.fromJson(
        json,
        (item) => CommentData.fromJson(item),
      ),
    );
  }

  Future<CommentData> createComment(String postId, String content) {
    return _client.postJson<CommentData>(
      'posts/$postId/comments',
      body: <String, Object?>{'content': content},
      decoder: (json) => CommentData.fromJson(json),
    );
  }

  Future<ApiPage<CommentData>> listLostPetComments(
    String lostPetId, {
    int limit = 20,
    String? cursor,
    String order = 'asc',
  }) {
    return _client.get<ApiPage<CommentData>>(
      'lost-pets/$lostPetId/comments',
      authenticated: false,
      queryParameters: <String, dynamic>{
        'limit': limit,
        'order': order,
        if (cursor != null) 'cursor': cursor,
      },
      decoder: (json) => ApiPage.fromJson(
        json,
        (item) => CommentData.fromJson(item),
      ),
    );
  }

  Future<CommentData> createLostPetComment(String lostPetId, String content) {
    return _client.postJson<CommentData>(
      'lost-pets/$lostPetId/comments',
      body: <String, Object?>{'content': content},
      decoder: (json) => CommentData.fromJson(json),
    );
  }

  Future<ApiPage<CommentData>> listAdoptionPostComments(
    String adoptionPostId, {
    int limit = 20,
    String? cursor,
    String order = 'asc',
  }) {
    return _client.get<ApiPage<CommentData>>(
      'adoption-posts/$adoptionPostId/comments',
      authenticated: false,
      queryParameters: <String, dynamic>{
        'limit': limit,
        'order': order,
        if (cursor != null) 'cursor': cursor,
      },
      decoder: (json) => ApiPage.fromJson(
        json,
        (item) => CommentData.fromJson(item),
      ),
    );
  }

  Future<CommentData> createAdoptionPostComment(
    String adoptionPostId,
    String content,
  ) {
    return _client.postJson<CommentData>(
      'adoption-posts/$adoptionPostId/comments',
      body: <String, Object?>{'content': content},
      decoder: (json) => CommentData.fromJson(json),
    );
  }

  Future<LikeData> likePost(String postId) {
    return _client.postJson<LikeData>(
      'posts/$postId/likes',
      body: const <String, Object?>{},
      decoder: (json) => LikeData.fromJson(json),
    );
  }

  Future<void> unlikePost(String postId) {
    return _client.delete('posts/$postId/likes');
  }

  Future<ReportData> createReport({
    required String targetType,
    required String targetId,
    required String reason,
    Map<String, Object?>? metadata,
  }) {
    return _client.postJson<ReportData>(
      'reports',
      body: <String, Object?>{
        'target_type': targetType,
        'target_id': targetId,
        'reason': reason,
        if (metadata != null) 'metadata': metadata,
      },
      decoder: (json) => ReportData.fromJson(json),
    );
  }

  Future<ApiPage<ReportData>> listReports({
    String status = 'open',
    int limit = 20,
    String? cursor,
  }) {
    return _client.get<ApiPage<ReportData>>(
      'moderation/reports',
      queryParameters: <String, dynamic>{
        'status': status,
        'limit': limit,
        if (cursor != null) 'cursor': cursor,
      },
      decoder: (json) => ApiPage.fromJson(
        json,
        (item) => ReportData.fromJson(item),
      ),
    );
  }

  Future<ReportData> handleReport({
    required String reportId,
    required String status,
    String? action,
    String? note,
  }) {
    return _client.patchJson<ReportData>(
      'moderation/reports/$reportId',
      body: <String, Object?>{
        'status': status,
        if (action != null) 'action': action,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
      decoder: (json) => ReportData.fromJson(json),
    );
  }

  Future<void> deleteModerationPost(String postId) {
    return _client.delete('moderation/posts/$postId');
  }

  Future<UserProfileData> updateMe({
    String? name,
    String? bio,
    String? phoneNumber,
    String? telegramUsername,
    String? preferredLanguage,
    bool? allowPublicActivityView,
    String? avatarUrl,
  }) {
    return _client.patchJson<UserProfileData>(
      'users/me',
      body: <String, Object?>{
        if (name != null) 'name': name,
        if (bio != null) 'bio': bio,
        if (phoneNumber != null) 'phone_number': phoneNumber,
        if (telegramUsername != null) 'telegram_username': telegramUsername,
        if (preferredLanguage != null) 'preferred_language': preferredLanguage,
        if (allowPublicActivityView != null)
          'allow_public_activity_view': allowPublicActivityView,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      },
      decoder: (json) => UserProfileData.fromJson(json),
    );
  }

  Future<void> deleteMe() {
    return _client.delete('users/me');
  }

  Future<void> blockUser(String userId) {
    return _client.postJson<Object?>(
      'users/$userId/block',
      body: const <String, Object?>{},
      decoder: (_) => null,
    );
  }

  Future<void> unblockUser(String userId) {
    return _client.delete('users/$userId/block');
  }

  Future<UserProfileData> updateAvatar({
    required Uint8List avatarBytes,
    required String avatarFilename,
    required String avatarContentType,
  }) {
    final formData = FormData.fromMap(
      <String, dynamic>{
        'avatar': MultipartFile.fromBytes(
          avatarBytes,
          filename: avatarFilename,
          contentType: MediaType.parse(avatarContentType),
        ),
      },
    );
    return _client.postMultipart<UserProfileData>(
      'users/me/avatar',
      formData: formData,
      decoder: (json) => UserProfileData.fromJson(json),
    );
  }

  Future<PostDetail> createObservation({
    required List<ObservationPhotoUpload> photos,
    GeoPoint? location,
    String? description,
    String? existingCatId,
    String? newCatName,
    String? newCatStatus,
    GeoPoint? newCatLocation,
    bool isPublic = true,
    String? postStatus,
  }) {
    final formData = FormData.fromMap(
      <String, dynamic>{
        'photos': photos
            .map(
              (photo) => MultipartFile.fromBytes(
                photo.bytes,
                filename: photo.filename,
                contentType: MediaType.parse(photo.contentType),
              ),
            )
            .toList(growable: false),
        if (location != null) 'location': jsonEncode(location.toJson()),
        'is_public': isPublic,
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        if (existingCatId != null) 'cat_id': existingCatId,
        if (postStatus != null) 'status': postStatus,
        if (newCatName != null ||
            newCatStatus != null ||
            newCatLocation != null)
          'new_cat': jsonEncode(<String, Object?>{
            if (newCatName != null && newCatName.trim().isNotEmpty)
              'name': newCatName.trim(),
            if (newCatStatus != null) 'status': newCatStatus,
            if (newCatLocation != null)
              'canonical_location': newCatLocation.toJson(),
          }),
      },
    );

    return _client.postMultipart<PostDetail>(
      'posts',
      formData: formData,
      decoder: (json) => PostDetail.fromJson(json),
    );
  }

  Future<LostPetData> createLostPet({
    required List<LostPetPhotoUpload> photos,
    required GeoPoint lastSeenLocation,
    required String petName,
    required bool ownerPhonePublicationConsent,
    String? additionalInfo,
  }) {
    final formData = FormData.fromMap(
      <String, dynamic>{
        'last_seen_location': jsonEncode(lastSeenLocation.toJson()),
        'pet_name': petName.trim(),
        'owner_phone_publication_consent': ownerPhonePublicationConsent,
        if (additionalInfo != null && additionalInfo.trim().isNotEmpty)
          'additional_info': additionalInfo.trim(),
        'photos': photos
            .map(
              (photo) => MultipartFile.fromBytes(
                photo.bytes,
                filename: photo.filename,
                contentType: MediaType.parse(photo.contentType),
              ),
            )
            .toList(growable: false),
      },
    );

    return _client.postMultipart<LostPetData>(
      'lost-pets',
      formData: formData,
      decoder: (json) => LostPetData.fromJson(json),
    );
  }

  Future<AdoptionPostData> createAdoptionPost({
    required List<LostPetPhotoUpload> photos,
    required String petName,
    required bool ownerPhonePublicationConsent,
    String? additionalInfo,
  }) {
    final formData = FormData.fromMap(
      <String, dynamic>{
        'pet_name': petName.trim(),
        'owner_phone_publication_consent': ownerPhonePublicationConsent,
        if (additionalInfo != null && additionalInfo.trim().isNotEmpty)
          'additional_info': additionalInfo.trim(),
        'photos': photos
            .map(
              (photo) => MultipartFile.fromBytes(
                photo.bytes,
                filename: photo.filename,
                contentType: MediaType.parse(photo.contentType),
              ),
            )
            .toList(growable: false),
      },
    );

    return _client.postMultipart<AdoptionPostData>(
      'adoption-posts',
      formData: formData,
      decoder: (json) => AdoptionPostData.fromJson(json),
    );
  }
}

class LostPetPhotoUpload {
  const LostPetPhotoUpload({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });

  final Uint8List bytes;
  final String filename;
  final String contentType;
}

class ObservationPhotoUpload {
  const ObservationPhotoUpload({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });

  final Uint8List bytes;
  final String filename;
  final String contentType;
}

class ApiPage<T> {
  const ApiPage({
    required this.items,
    required this.limit,
    this.nextCursor,
  });

  final List<T> items;
  final String? nextCursor;
  final int limit;

  factory ApiPage.fromJson(
    Object? json,
    T Function(Object? json) itemFromJson,
  ) {
    final map = _readMap(json);
    final items =
        _readList(map['items']).map(itemFromJson).toList(growable: false);
    return ApiPage<T>(
      items: items,
      nextCursor: _readStringOrNull(map['next_cursor']),
      limit: _readInt(map['limit'], fallback: items.length),
    );
  }
}

class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  factory GeoPoint.fromJson(Object? json) {
    final map = _readMap(json);
    return GeoPoint(
      latitude: _readDouble(map['latitude']),
      longitude: _readDouble(map['longitude']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'latitude': latitude,
        'longitude': longitude,
      };
}

class CatSummary {
  const CatSummary({
    required this.id,
    required this.status,
    required this.totalObservations,
    this.name,
    this.coverPhotoUrl,
    this.canonicalLocation,
    this.lastSeenAt,
    this.distanceMeters,
  });

  final String id;
  final String? name;
  final String status;
  final String? coverPhotoUrl;
  final GeoPoint? canonicalLocation;
  final DateTime? lastSeenAt;
  final int totalObservations;
  final double? distanceMeters;

  factory CatSummary.fromJson(Object? json) {
    final map = _readMap(json);
    return CatSummary(
      id: _readString(map['id']),
      name: _readStringOrNull(map['name']),
      status: _readString(map['status']),
      coverPhotoUrl: _readStringOrNull(map['cover_photo_url']),
      canonicalLocation: _readNullableGeoPoint(map['canonical_location']),
      lastSeenAt: _readDateTimeOrNull(map['last_seen_at']),
      totalObservations: _readInt(map['total_observations']),
      distanceMeters: _readDoubleOrNull(map['distance_meters']),
    );
  }
}

class PlaceSummary {
  const PlaceSummary({
    required this.id,
    required this.name,
    required this.category,
    required this.location,
    required this.source,
    this.address,
    this.phone,
    this.website,
    this.openingHours,
    this.sourceId,
    this.verifiedAt,
    this.distanceMeters,
  });

  final String id;
  final String name;
  final String category;
  final GeoPoint location;
  final String? address;
  final String? phone;
  final String? website;
  final String? openingHours;
  final String source;
  final String? sourceId;
  final DateTime? verifiedAt;
  final double? distanceMeters;

  factory PlaceSummary.fromJson(Object? json) {
    final map = _readMap(json);
    return PlaceSummary(
      id: _readString(map['id']),
      name: _readString(map['name']),
      category: _readString(map['category']),
      location: GeoPoint.fromJson(map['location']),
      address: _readStringOrNull(map['address']),
      phone: _readStringOrNull(map['phone']),
      website: _readStringOrNull(map['website']),
      openingHours: _readStringOrNull(map['opening_hours']),
      source: _readString(map['source']),
      sourceId: _readStringOrNull(map['source_id']),
      verifiedAt: _readDateTimeOrNull(map['verified_at']),
      distanceMeters: _readDoubleOrNull(map['distance_meters']),
    );
  }
}

class PostAuthorData {
  const PostAuthorData({
    this.id,
    this.name,
    this.avatarUrl,
  });

  final String? id;
  final String? name;
  final String? avatarUrl;

  factory PostAuthorData.fromJson(Object? json) {
    final map = _readMap(json);
    return PostAuthorData(
      id: _readStringOrNull(map['id']),
      name: _readStringOrNull(map['name']),
      avatarUrl: _readStringOrNull(map['avatar_url']),
    );
  }
}

class PostCatData {
  const PostCatData({
    required this.id,
    required this.status,
    this.name,
    this.coverPhotoUrl,
  });

  final String id;
  final String? name;
  final String status;
  final String? coverPhotoUrl;

  factory PostCatData.fromJson(Object? json) {
    final map = _readMap(json);
    return PostCatData(
      id: _readString(map['id']),
      status: _readStringOrNull(map['status']) ?? 'unknown',
      name: _readStringOrNull(map['name']),
      coverPhotoUrl: _readStringOrNull(map['cover_photo_url']),
    );
  }
}

sealed class FeedItem {
  const FeedItem();

  String get id;
  DateTime get createdAt;
  String get itemType;

  factory FeedItem.fromJson(Object? json) {
    final map = _readMap(json);
    final itemType = _readStringOrNull(map['item_type']) ?? 'observation';
    if (itemType == 'lost_pet') {
      return LostPetData.fromJson(map);
    }
    if (itemType == 'adoption') {
      return AdoptionPostData.fromJson(map);
    }
    return PostSummary.fromJson(map);
  }
}

class PostSummary extends FeedItem {
  const PostSummary({
    required this.id,
    required this.cat,
    required this.photoUrl,
    required this.photoUrls,
    required this.location,
    required this.createdAt,
    required this.likeCount,
    required this.commentCount,
    required this.isLikedByMe,
    this.author,
    this.thumbUrl,
    this.description,
    this.status,
  }) : super();

  @override
  final String id;
  @override
  String get itemType => 'observation';
  final PostCatData cat;
  final PostAuthorData? author;
  final String photoUrl;
  final List<String> photoUrls;
  final String? thumbUrl;
  final String? description;
  final String? status;
  final GeoPoint? location;
  @override
  final DateTime createdAt;
  final int likeCount;
  final int commentCount;
  final bool isLikedByMe;

  factory PostSummary.fromJson(Object? json) {
    final map = _readMap(json);
    final photoUrl = _readString(map['photo_url']);
    final photoUrls = _readListOrEmpty(map['photo_urls'])
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    return PostSummary(
      id: _readString(map['id']),
      cat: PostCatData.fromJson(map['cat']),
      author:
          map['author'] == null ? null : PostAuthorData.fromJson(map['author']),
      photoUrl: photoUrl,
      photoUrls: photoUrls.isEmpty ? [photoUrl] : photoUrls,
      thumbUrl: _readStringOrNull(map['thumb_url']),
      description: _readStringOrNull(map['description']),
      status: _readStringOrNull(map['status']),
      location: _readNullableGeoPoint(map['location']),
      createdAt: _readDateTime(map['created_at']),
      likeCount: _readInt(map['like_count']),
      commentCount: _readInt(map['comment_count']),
      isLikedByMe: _readBool(map['is_liked_by_me']),
    );
  }
}

class PostDetail extends PostSummary {
  const PostDetail({
    required super.id,
    required super.cat,
    required super.photoUrl,
    required super.photoUrls,
    required super.location,
    required super.createdAt,
    required super.likeCount,
    required super.commentCount,
    required super.isLikedByMe,
    super.author,
    super.thumbUrl,
    super.description,
    super.status,
  });

  factory PostDetail.fromJson(Object? json) {
    final map = _readMap(json);
    final summary = PostSummary.fromJson(map);
    return PostDetail(
      id: summary.id,
      cat: summary.cat,
      author: summary.author,
      photoUrl: summary.photoUrl,
      photoUrls: summary.photoUrls,
      thumbUrl: summary.thumbUrl,
      description: summary.description,
      status: summary.status,
      location: summary.location,
      createdAt: summary.createdAt,
      likeCount: summary.likeCount,
      commentCount: summary.commentCount,
      isLikedByMe: summary.isLikedByMe,
    );
  }
}

class LostPetData extends FeedItem {
  const LostPetData({
    required this.id,
    required this.petName,
    required this.ownerPhoneNumber,
    this.ownerTelegramUsername,
    required this.photoUrl,
    required this.photoUrls,
    required this.lastSeenLocation,
    required this.createdAt,
    required this.isResolved,
    required this.commentCount,
    this.author,
    this.thumbUrl,
    this.additionalInfo,
  }) : super();

  @override
  final String id;
  @override
  String get itemType => 'lost_pet';
  final PostAuthorData? author;
  final String petName;
  final String ownerPhoneNumber;
  final String? ownerTelegramUsername;
  final String photoUrl;
  final String? thumbUrl;
  final List<String> photoUrls;
  final GeoPoint lastSeenLocation;
  final String? additionalInfo;
  final bool isResolved;
  final int commentCount;
  @override
  final DateTime createdAt;

  factory LostPetData.fromJson(Object? json) {
    final map = _readMap(json);
    final photoUrls = _readList(map['photo_urls'])
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    final photoUrl = _readString(map['photo_url']);
    return LostPetData(
      id: _readString(map['id']),
      petName: _readString(map['pet_name']),
      author:
          map['author'] == null ? null : PostAuthorData.fromJson(map['author']),
      ownerPhoneNumber: _readString(map['owner_phone_number']),
      ownerTelegramUsername: _readStringOrNull(map['owner_telegram_username']),
      photoUrl: photoUrl,
      thumbUrl: _readStringOrNull(map['thumb_url']),
      photoUrls: photoUrls.isEmpty ? [photoUrl] : photoUrls,
      lastSeenLocation: GeoPoint.fromJson(map['last_seen_location']),
      additionalInfo: _readStringOrNull(map['additional_info']),
      isResolved: _readBool(map['is_resolved']),
      commentCount: _readInt(map['comment_count']),
      createdAt: _readDateTime(map['created_at']),
    );
  }
}

class AdoptionPostData extends FeedItem {
  const AdoptionPostData({
    required this.id,
    required this.petName,
    required this.ownerPhoneNumber,
    this.ownerTelegramUsername,
    required this.photoUrl,
    required this.photoUrls,
    required this.createdAt,
    required this.commentCount,
    this.author,
    this.thumbUrl,
    this.additionalInfo,
  }) : super();

  @override
  final String id;
  @override
  String get itemType => 'adoption';
  final PostAuthorData? author;
  final String petName;
  final String ownerPhoneNumber;
  final String? ownerTelegramUsername;
  final String photoUrl;
  final String? thumbUrl;
  final List<String> photoUrls;
  final String? additionalInfo;
  final int commentCount;
  @override
  final DateTime createdAt;

  factory AdoptionPostData.fromJson(Object? json) {
    final map = _readMap(json);
    final photoUrls = _readList(map['photo_urls'])
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    final photoUrl = _readString(map['photo_url']);
    return AdoptionPostData(
      id: _readString(map['id']),
      petName: _readString(map['pet_name']),
      author:
          map['author'] == null ? null : PostAuthorData.fromJson(map['author']),
      ownerPhoneNumber: _readString(map['owner_phone_number']),
      ownerTelegramUsername: _readStringOrNull(map['owner_telegram_username']),
      photoUrl: photoUrl,
      thumbUrl: _readStringOrNull(map['thumb_url']),
      photoUrls: photoUrls.isEmpty ? [photoUrl] : photoUrls,
      additionalInfo: _readStringOrNull(map['additional_info']),
      commentCount: _readInt(map['comment_count']),
      createdAt: _readDateTime(map['created_at']),
    );
  }
}

class UserProfileData {
  const UserProfileData({
    required this.id,
    required this.email,
    required this.registeredAt,
    required this.observationCount,
    required this.totalLikesReceived,
    required this.commentCount,
    this.name,
    this.avatarUrl,
    this.phoneNumber,
    this.telegramUsername,
    this.preferredLanguage = 'en',
    this.allowPublicActivityView = true,
    this.bio,
  });

  final String id;
  final String email;
  final String? name;
  final String? avatarUrl;
  final String? phoneNumber;
  final String? telegramUsername;
  final String preferredLanguage;
  final bool allowPublicActivityView;
  final String? bio;
  final DateTime registeredAt;
  final int observationCount;
  final int totalLikesReceived;
  final int commentCount;

  factory UserProfileData.fromJson(Object? json) {
    final map = _readMap(json);
    return UserProfileData(
      id: _readString(map['id']),
      email: _readString(map['email']),
      name: _readStringOrNull(map['name']),
      avatarUrl: _readStringOrNull(map['avatar_url']),
      phoneNumber: _readStringOrNull(map['phone_number']),
      telegramUsername: _readStringOrNull(map['telegram_username']),
      preferredLanguage: _readStringOrNull(map['preferred_language']) ?? 'en',
      allowPublicActivityView:
          _readBoolOrNull(map['allow_public_activity_view']) ?? true,
      bio: _readStringOrNull(map['bio']),
      registeredAt: _readDateTime(map['registered_at']),
      observationCount: _readInt(map['observation_count']),
      totalLikesReceived: _readInt(map['total_likes_received']),
      commentCount: _readInt(map['comment_count']),
    );
  }
}

class UserPublicData {
  const UserPublicData({
    required this.id,
    required this.registeredAt,
    required this.observationCount,
    required this.commentCount,
    required this.allowPublicActivityView,
    this.name,
    this.avatarUrl,
  });

  final String id;
  final String? name;
  final String? avatarUrl;
  final DateTime registeredAt;
  final int observationCount;
  final int commentCount;
  final bool allowPublicActivityView;

  factory UserPublicData.fromJson(Object? json) {
    final map = _readMap(json);
    return UserPublicData(
      id: _readString(map['id']),
      name: _readStringOrNull(map['name']),
      avatarUrl: _readStringOrNull(map['avatar_url']),
      registeredAt: _readDateTime(map['registered_at']),
      observationCount: _readInt(map['observation_count']),
      commentCount: _readInt(map['comment_count']),
      allowPublicActivityView:
          _readBoolOrNull(map['allow_public_activity_view']) ?? true,
    );
  }
}

class LeaderboardEntryData {
  const LeaderboardEntryData({
    required this.rank,
    required this.user,
    required this.score,
  });

  final int rank;
  final UserPublicData user;
  final int score;

  factory LeaderboardEntryData.fromJson(Object? json) {
    final map = _readMap(json);
    return LeaderboardEntryData(
      rank: _readInt(map['rank']),
      user: UserPublicData.fromJson(map['user']),
      score: _readInt(map['score']),
    );
  }
}

class CommentUserData {
  const CommentUserData({
    this.id,
    this.name,
    this.avatarUrl,
  });

  final String? id;
  final String? name;
  final String? avatarUrl;

  factory CommentUserData.fromJson(Object? json) {
    final map = _readMap(json);
    return CommentUserData(
      id: _readStringOrNull(map['id']),
      name: _readStringOrNull(map['name']),
      avatarUrl: _readStringOrNull(map['avatar_url']),
    );
  }
}

class CommentData {
  const CommentData({
    required this.id,
    required this.postId,
    required this.content,
    required this.createdAt,
    this.user,
    this.lostPetId,
    this.adoptionPostId,
  });

  final String id;
  final String? postId;
  final String? lostPetId;
  final String? adoptionPostId;
  final CommentUserData? user;
  final String content;
  final DateTime createdAt;

  factory CommentData.fromJson(Object? json) {
    final map = _readMap(json);
    return CommentData(
      id: _readString(map['id']),
      postId: _readStringOrNull(map['post_id']),
      lostPetId: _readStringOrNull(map['lost_pet_id']),
      adoptionPostId: _readStringOrNull(map['adoption_post_id']),
      user: map['user'] == null ? null : CommentUserData.fromJson(map['user']),
      content: _readString(map['content']),
      createdAt: _readDateTime(map['created_at']),
    );
  }
}

class LikeData {
  const LikeData({
    required this.liked,
    required this.likeCount,
  });

  final bool liked;
  final int likeCount;

  factory LikeData.fromJson(Object? json) {
    final map = _readMap(json);
    return LikeData(
      liked: _readBool(map['liked']),
      likeCount: _readInt(map['like_count']),
    );
  }
}

class ReportTargetData {
  const ReportTargetData({
    required this.id,
    required this.targetType,
    this.title,
    this.subtitle,
    this.status,
    this.isPublic,
    this.isActive,
    this.deletedAt,
  });

  final String id;
  final String targetType;
  final String? title;
  final String? subtitle;
  final String? status;
  final bool? isPublic;
  final bool? isActive;
  final DateTime? deletedAt;

  factory ReportTargetData.fromJson(Object? json) {
    final map = _readMap(json);
    return ReportTargetData(
      id: _readString(map['id']),
      targetType: _readString(map['target_type']),
      title: _readStringOrNull(map['title']),
      subtitle: _readStringOrNull(map['subtitle']),
      status: _readStringOrNull(map['status']),
      isPublic: _readBoolOrNull(map['is_public']),
      isActive: _readBoolOrNull(map['is_active']),
      deletedAt: _readDateTimeOrNull(map['deleted_at']),
    );
  }
}

class ReportData {
  const ReportData({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.status,
    required this.createdAt,
    this.reporter,
    this.target,
    this.reason,
    this.metadata,
    this.handledBy,
    this.handledAt,
  });

  final String id;
  final CommentUserData? reporter;
  final String targetType;
  final String targetId;
  final ReportTargetData? target;
  final String? reason;
  final Map<String, Object?>? metadata;
  final String status;
  final CommentUserData? handledBy;
  final DateTime? handledAt;
  final DateTime createdAt;

  factory ReportData.fromJson(Object? json) {
    final map = _readMap(json);
    final metadata = map['metadata'];
    return ReportData(
      id: _readString(map['id']),
      reporter: map['reporter'] == null
          ? null
          : CommentUserData.fromJson(map['reporter']),
      targetType: _readString(map['target_type']),
      targetId: _readString(map['target_id']),
      target: map['target'] == null
          ? null
          : ReportTargetData.fromJson(map['target']),
      reason: _readStringOrNull(map['reason']),
      metadata: metadata is Map ? metadata.cast<String, Object?>() : null,
      status: _readString(map['status']),
      handledBy: map['handled_by'] == null
          ? null
          : CommentUserData.fromJson(map['handled_by']),
      handledAt: _readDateTimeOrNull(map['handled_at']),
      createdAt: _readDateTime(map['created_at']),
    );
  }
}

Map<String, Object?> _readMap(Object? json) {
  if (json is Map<String, Object?>) {
    return json;
  }
  if (json is Map) {
    return json.cast<String, Object?>();
  }
  throw const FormatException('Expected JSON object.');
}

List<Object?> _readList(Object? json) {
  if (json is List<Object?>) {
    return json;
  }
  if (json is List) {
    return json.cast<Object?>();
  }
  throw const FormatException('Expected JSON array.');
}

List<Object?> _readListOrEmpty(Object? json) {
  if (json == null) {
    return const [];
  }
  return _readList(json);
}

String _readString(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw const FormatException('Expected non-empty string.');
}

String? _readStringOrNull(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

bool _readBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    return value.toLowerCase() == 'true';
  }
  return false;
}

bool? _readBoolOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  return _readBool(value);
}

int _readInt(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return fallback;
}

double? _readDoubleOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  return _readDouble(value);
}

double _readDouble(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is int) {
    return value.toDouble();
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0;
  }
  throw const FormatException('Expected number.');
}

DateTime _readDateTime(Object? value) {
  final parsed = _readDateTimeOrNull(value);
  if (parsed == null) {
    throw const FormatException('Expected datetime.');
  }
  return parsed;
}

DateTime? _readDateTimeOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.parse(value);
  }
  return null;
}

GeoPoint? _readNullableGeoPoint(Object? value) {
  if (value == null) {
    return null;
  }
  return GeoPoint.fromJson(value);
}
