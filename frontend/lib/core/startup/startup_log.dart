import 'dart:developer' as developer;

void logStartupStage(String stage) {
  developer.log(stage, name: 'mushukistan.startup');
}

void logStartupFailure(String stage, Object error, StackTrace stackTrace) {
  developer.log(
    stage,
    name: 'mushukistan.startup',
    error: error.runtimeType,
    stackTrace: stackTrace,
    level: 1000,
  );
}
