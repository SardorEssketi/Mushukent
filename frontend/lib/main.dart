import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';
import 'core/config/app_environment.dart';

void main() {
  usePathUrlStrategy();
  try {
    final environment = AppEnvironment.fromBuildEnvironment();
    runApp(
      ProviderScope(
        overrides: [
          appEnvironmentProvider.overrideWithValue(environment),
        ],
        child: const MushukistanApp(),
      ),
    );
  } on AppEnvironmentConfiguration catch (error) {
    runApp(_ConfigurationErrorApp(message: error.message));
  }
}

class _ConfigurationErrorApp extends StatelessWidget {
  const _ConfigurationErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mushukistan configuration error',
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'This Mushukistan release is not configured correctly.\n\n'
              '$message',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
