import 'dart:async';

import 'package:mushukistan_frontend/core/widgets/osm_attribution.dart';

/// Runs before every test file. Map screens open the OpenStreetMap credit for
/// five seconds through an uncancellable timer in flutter_map; tests of whole
/// screens start with it collapsed instead. `osm_attribution_test.dart` tests
/// the real behaviour by clearing this override.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  debugOsmAttributionInitialDisplay = Duration.zero;
  await testMain();
}
