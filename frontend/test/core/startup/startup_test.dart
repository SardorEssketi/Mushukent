import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/main.dart';

void main() {
  testWidgets('fatal startup failure renders a controlled surface',
      (tester) async {
    await tester.pumpWidget(const StartupFailureApp.unexpected());

    expect(find.byType(Scaffold), findsOneWidget);
    expect(
      find.text('Mushukistan could not start. Please try again.'),
      findsOneWidget,
    );
  });

  test('web shell covers bootstrap and first-frame failures', () {
    final index = File('web/index.html').readAsStringSync();
    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();

    expect(index, contains('id="flutter-startup"'));
    expect(index, contains('This is taking longer than expected.'));
    expect(index, contains('flutter_bootstrap.js" defer'));
    expect(bootstrap, contains('{{flutter_js}}'));
    expect(bootstrap, contains('{{flutter_build_config}}'));
    expect(bootstrap, contains('flutter-first-frame'));
    expect(bootstrap, contains('retireLegacyFlutterServiceWorker'));
    expect(bootstrap, contains('startFlutter().catch(showFailure)'));
    expect(bootstrap, isNot(contains('serviceWorkerSettings:')));
  });

  test('production cache rules keep executable generations compatible', () {
    final nginx =
        File('../infrastructure/nginx/default.conf').readAsStringSync();

    expect(nginx, contains('location = /main.dart.js'));
    expect(nginx, contains('location = /flutter_bootstrap.js'));
    expect(nginx, contains('location ^~ /canvaskit/'));
    expect(
      nginx,
      contains('/index.html "no-store, no-cache, must-revalidate, max-age=0"'),
    );
    expect(
      nginx,
      contains(
        'add_header Cache-Control \$frontend_cache_control always;',
      ),
    );
    expect(nginx, contains('add_header Content-Security-Policy'));
    expect(nginx, contains("connect-src 'self' blob:"));
  });
}
