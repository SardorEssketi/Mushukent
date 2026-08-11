import 'package:flutter/foundation.dart';

class AuthCredentials {
  const AuthCredentials({
    required this.email,
    required this.password,
  });

  final String email;
  final String password;

  Map<String, Object?> toJson() => <String, Object?>{
        'email': email,
        'password': password,
      };
}

class RegisterCredentials extends AuthCredentials {
  const RegisterCredentials({
    required super.email,
    required super.password,
    required this.preferredLanguage,
    required this.acceptTerms,
    required this.acceptPrivacy,
    this.name,
  });

  final String? name;
  final String preferredLanguage;
  final bool acceptTerms;
  final bool acceptPrivacy;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        ...super.toJson(),
        if (name != null) 'name': name,
        'preferred_language': preferredLanguage,
        'accept_terms': acceptTerms,
        'accept_privacy': acceptPrivacy,
      };
}

@immutable
class VerificationRequirement {
  const VerificationRequirement({
    required this.email,
    this.devVerificationToken,
  });

  final String email;
  final String? devVerificationToken;

  factory VerificationRequirement.fromJson(Object? json) {
    final map = _readMap(json);
    return VerificationRequirement(
      email: _readString(map['email']),
      devVerificationToken: _readOptionalString(map['dev_verification_token']),
    );
  }
}

@immutable
class MushukistanUser {
  const MushukistanUser({
    required this.id,
    required this.registeredAt,
    this.email,
    this.name,
    this.avatarUrl,
    this.preferredLanguage = 'en',
    this.allowPublicActivityView = true,
    this.bio,
    this.observationCount = 0,
    this.totalLikesReceived = 0,
    this.commentCount = 0,
  });

  final String id;
  final String? email;
  final String? name;
  final String? avatarUrl;
  final String preferredLanguage;
  final bool allowPublicActivityView;
  final String? bio;
  final DateTime registeredAt;
  final int observationCount;
  final int totalLikesReceived;
  final int commentCount;

  bool get hasAvatar => avatarUrl != null && avatarUrl!.isNotEmpty;

  factory MushukistanUser.fromJson(Object? json) {
    final map = _readMap(json);
    return MushukistanUser(
      id: _readString(map['id']),
      email: _readOptionalString(map['email']),
      name: _readOptionalString(map['name']),
      avatarUrl: _readOptionalString(map['avatar_url']),
      preferredLanguage: _readOptionalString(map['preferred_language']) ?? 'en',
      allowPublicActivityView:
          _readOptionalBool(map['allow_public_activity_view']) ?? true,
      bio: _readOptionalString(map['bio']),
      registeredAt: DateTime.parse(_readString(map['registered_at'])),
      observationCount: _readInt(map['observation_count']),
      totalLikesReceived: _readInt(map['total_likes_received']),
      commentCount: _readInt(map['comment_count']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        if (email != null) 'email': email,
        if (name != null) 'name': name,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'preferred_language': preferredLanguage,
        'allow_public_activity_view': allowPublicActivityView,
        if (bio != null) 'bio': bio,
        'registered_at': registeredAt.toUtc().toIso8601String(),
        'observation_count': observationCount,
        'total_likes_received': totalLikesReceived,
        'comment_count': commentCount,
      };
}

@immutable
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.user,
    this.tokenType = 'Bearer',
    this.expiresIn,
  });

  final String accessToken;
  final String tokenType;
  final int? expiresIn;
  final MushukistanUser user;

  factory AuthSession.fromJson(Object? json) {
    final map = _readMap(json);
    return AuthSession(
      accessToken: _readString(map['access_token']),
      tokenType: _readOptionalString(map['token_type']) ?? 'Bearer',
      expiresIn: _readOptionalInt(map['expires_in']),
      user: MushukistanUser.fromJson(map['user']),
    );
  }

  factory AuthSession.restored({
    required String accessToken,
    required MushukistanUser user,
  }) {
    return AuthSession(accessToken: accessToken, user: user);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'access_token': accessToken,
        'token_type': tokenType,
        if (expiresIn != null) 'expires_in': expiresIn,
        'user': user.toJson(),
      };
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

String _readString(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw const FormatException('Expected non-empty string.');
}

String? _readOptionalString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

int _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return 0;
}

int? _readOptionalInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

bool? _readOptionalBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    return value.toLowerCase() == 'true';
  }
  return null;
}
