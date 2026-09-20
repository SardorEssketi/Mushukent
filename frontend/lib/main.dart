import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';
import 'core/config/app_environment.dart';
import 'core/startup/startup_log.dart';

void main() {
  logStartupStage('Dart entry reached');
  try {
    usePathUrlStrategy();
    final environment = AppEnvironment.fromBuildEnvironment();
    logStartupStage('Configuration initialized');
    runApp(
      ProviderScope(
        overrides: [
          appEnvironmentProvider.overrideWithValue(environment),
        ],
        child: const MushukistanApp(),
      ),
    );
    _logFirstFrame();
  } on AppEnvironmentConfiguration catch (error, stackTrace) {
    logStartupFailure('Fatal configuration failure', error, stackTrace);
    runApp(const StartupFailureApp.configuration());
    _logFirstFrame();
  } on Object catch (error, stackTrace) {
    logStartupFailure('Fatal synchronous startup failure', error, stackTrace);
    runApp(const StartupFailureApp.unexpected());
    _logFirstFrame();
  }
}

void _logFirstFrame() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    logStartupStage('First Flutter frame');
  });
}

class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp.configuration({super.key})
      : message = 'This Mushukistan release is not configured correctly.';

  const StartupFailureApp.unexpected({super.key})
      : message = 'Mushukistan could not start. Please try again.';

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mushukistan startup error',
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              message,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
