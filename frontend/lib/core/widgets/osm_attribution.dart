import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

/// The OpenStreetMap licence page the credit links to.
final Uri osmCopyrightUri =
    Uri.parse('https://www.openstreetmap.org/copyright');

/// How long the credit stays open when a map appears. OSM's attribution
/// guidelines require it to be visible without interaction; it may collapse
/// after five seconds (or on map interaction) into the (i) button, from which
/// it can always be reopened.
const Duration osmAttributionInitialDisplay = Duration(seconds: 5);

/// Test-only override of [osmAttributionInitialDisplay]. flutter_map closes
/// the popup with an uncancellable `Future.delayed`, which widget tests of
/// whole map screens would report as a pending timer; `flutter_test_config`
/// sets this to [Duration.zero] (start collapsed) for every test except the
/// attribution's own.
@visibleForTesting
Duration? debugOsmAttributionInitialDisplay;

/// "© OpenStreetMap contributors", linked to the licence page. Every map
/// that shows OpenStreetMap-based tiles must include it as a map child.
class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key, this.openUri = _openExternally});

  /// Opens the licence page; replaceable in tests.
  final Future<void> Function(Uri uri) openUri;

  @override
  Widget build(BuildContext context) {
    return RichAttributionWidget(
      popupInitialDisplayDuration:
          debugOsmAttributionInitialDisplay ?? osmAttributionInitialDisplay,
      attributions: [
        TextSourceAttribution(
          'OpenStreetMap contributors',
          onTap: () => openUri(osmCopyrightUri),
        ),
      ],
    );
  }
}

Future<void> _openExternally(Uri uri) async {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
