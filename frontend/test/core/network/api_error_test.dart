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
}
