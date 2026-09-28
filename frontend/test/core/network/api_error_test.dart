import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';

void main() {
  test('parses backend validation envelopes', () {
    final error = MushukistanApiException.fromEnvelope(
      {
        'success': false,
        'error': {
          'code': 'VALIDATION_ERROR',
          'message': 'Validation failed.',
          'details': {
            'email': ['invalid']
          },
        },
      },
      statusCode: 422,
    );

    expect(error.kind, ApiFailureKind.validation);
    expect(error.code, 'VALIDATION_ERROR');
    expect(error.message, 'Validation failed.');
    expect(error.details, isA<Map>());
  });

  test('maps unauthorized responses to session-invalid failures', () {
    final error = MushukistanApiException.fromEnvelope(
      {
        'success': false,
        'error': {
          'code': 'UNAUTHORIZED',
          'message': 'Missing or invalid Authorization header.',
        },
      },
      statusCode: 401,
    );

    expect(error.kind, ApiFailureKind.unauthorized);
    expect(error.isSessionInvalid, isTrue);
  });

  test('marks network failures as retryable', () {
    const error = MushukistanApiException(
      kind: ApiFailureKind.network,
      code: 'NETWORK_ERROR',
      message: 'Network request failed.',
    );

    expect(error.isRetryable, isTrue);
  });

  test('maps auth conflicts to user-facing messages without provider codes',
      () {
    final googleConflict = MushukistanApiException.fromEnvelope(
      {
        'error': {
          'code': 'GOOGLE_IDENTITY_CONFLICT',
          'message': 'Google identity could not be connected.',
        },
      },
      statusCode: 409,
    );
    final duplicate = MushukistanApiException.fromEnvelope(
      {
        'error': {
          'code': 'EMAIL_ALREADY_EXISTS',
          'message': 'Email already registered.',
        },
      },
      statusCode: 409,
    );

    expect(googleConflict.userMessage, contains('Google account'));
    expect(googleConflict.userMessage,
        isNot(contains('GOOGLE_IDENTITY_CONFLICT')));
    expect(duplicate.userMessage, contains('If you already have an account'));
    expect(duplicate.userMessage, isNot(contains('already registered')));
  });
}
