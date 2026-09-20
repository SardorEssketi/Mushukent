import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/routing/auth_navigation.dart';

void main() {
  test('post-auth redirects accept only safe internal product routes', () {
    expect(validatedPostAuthRedirect('/posts/post-1?reply=comment-1'),
        '/posts/post-1?reply=comment-1');
    expect(validatedPostAuthRedirect('https://evil.example/'), isNull);
    expect(validatedPostAuthRedirect('//evil.example/'), isNull);
    expect(validatedPostAuthRedirect('/login'), isNull);
    expect(validatedPostAuthRedirect('/moderation/reports'),
        '/moderation/reports');
  });

  test('authentication requirement preserves path and query', () {
    final location = authenticationRequiredLocation(
      Uri.parse('/report?type=post&id=post-1'),
    );
    final uri = Uri.parse(location);

    expect(uri.path, '/auth-required');
    expect(uri.queryParameters['redirect'], '/report?type=post&id=post-1');
  });
}
