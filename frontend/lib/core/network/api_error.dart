import 'package:dio/dio.dart';

enum ApiFailureKind {
  validation,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  server,
  network,
  parse,
  unknown,
}

class MushukistanApiException implements Exception {
  const MushukistanApiException({
    required this.kind,
    required this.code,
    required this.message,
    this.statusCode,
    this.details,
  });

  final ApiFailureKind kind;
  final int? statusCode;
  final String code;
  final String message;
  final Object? details;

  bool get isRetryable =>
      kind == ApiFailureKind.network || kind == ApiFailureKind.server;

  bool get isSessionInvalid =>
      kind == ApiFailureKind.unauthorized ||
      kind == ApiFailureKind.notFound ||
      (kind == ApiFailureKind.forbidden && code == 'ACCOUNT_DISABLED');

  String get userMessage =>
      message.trim().isEmpty ? 'Request failed.' : message;

  factory MushukistanApiException.fromEnvelope(
    Object? raw, {
    int? statusCode,
  }) {
    if (statusCode == 413) {
      return const MushukistanApiException(
        kind: ApiFailureKind.validation,
        statusCode: 413,
        code: 'PAYLOAD_TOO_LARGE',
        message: 'The selected image is too large. Choose a smaller photo.',
      );
    }

    if (raw is Map) {
      final error = raw['error'];
      if (error is Map) {
        final code = _readString(error['code']) ?? _fallbackCode(statusCode);
        final message = _readString(error['message']) ?? 'Request failed.';
        final details = error['details'];
        return MushukistanApiException(
          kind: _kindForStatus(statusCode, code),
          statusCode: statusCode,
          code: code,
          message: message,
          details: details,
        );
      }
      final code = _fallbackCode(statusCode);
      return MushukistanApiException(
        kind: _kindForStatus(statusCode, code),
        statusCode: statusCode,
        code: code,
        message: 'Request failed.',
        details: raw,
      );
    }

    return MushukistanApiException(
      kind: _kindForStatus(statusCode, _fallbackCode(statusCode)),
      statusCode: statusCode,
      code: _fallbackCode(statusCode),
      message: 'Request failed.',
      details: raw,
    );
  }

  factory MushukistanApiException.fromDioException(DioException error) {
    final statusCode = error.response?.statusCode;
    if (_isNetworkFailure(error.type)) {
      return MushukistanApiException(
        kind: ApiFailureKind.network,
        statusCode: statusCode,
        code: 'NETWORK_ERROR',
        message: 'Network request failed.',
        details: null,
      );
    }
    final responseData = error.response?.data;
    if (responseData != null) {
      return MushukistanApiException.fromEnvelope(responseData,
          statusCode: statusCode);
    }
    return MushukistanApiException(
      kind: _kindForStatus(statusCode, _fallbackCode(statusCode)),
      statusCode: statusCode,
      code: _fallbackCode(statusCode),
      message: 'Request failed.',
      details: null,
    );
  }

  static ApiFailureKind _kindForStatus(int? statusCode, String code) {
    switch (statusCode) {
      case 400:
      case 413:
      case 422:
        return ApiFailureKind.validation;
      case 401:
        return ApiFailureKind.unauthorized;
      case 403:
        return ApiFailureKind.forbidden;
      case 404:
        return ApiFailureKind.notFound;
      case 409:
        return ApiFailureKind.conflict;
      default:
        if (statusCode != null && statusCode >= 500) {
          return ApiFailureKind.server;
        }
        if (code == 'VALIDATION_ERROR') {
          return ApiFailureKind.validation;
        }
        return ApiFailureKind.unknown;
    }
  }

  static String _fallbackCode(int? statusCode) {
    switch (statusCode) {
      case 400:
        return 'VALIDATION_ERROR';
      case 413:
        return 'PAYLOAD_TOO_LARGE';
      case 422:
        return 'VALIDATION_ERROR';
      case 401:
        return 'UNAUTHORIZED';
      case 403:
        return 'FORBIDDEN';
      case 404:
        return 'NOT_FOUND';
      case 409:
        return 'CONFLICT';
      default:
        return 'REQUEST_FAILED';
    }
  }

  static String? _readString(Object? value) {
    if (value is String) {
      return value;
    }
    return null;
  }

  static bool _isNetworkFailure(DioExceptionType type) {
    return switch (type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.transformTimeout ||
      DioExceptionType.cancel ||
      DioExceptionType.connectionError ||
      DioExceptionType.unknown =>
        true,
      DioExceptionType.badCertificate || DioExceptionType.badResponse => false,
    };
  }

  @override
  String toString() => 'MushukistanApiException($code, $message)';
}
