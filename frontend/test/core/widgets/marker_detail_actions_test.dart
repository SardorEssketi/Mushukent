import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/localization/app_strings.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/network/mushukistan_api.dart';
import 'package:mushukistan_frontend/core/validation/phone_numbers.dart';
import 'package:mushukistan_frontend/core/widgets/marker_detail_actions.dart';

void main() {
  const destination = GeoPoint(latitude: 41.3111, longitude: 69.2797);
  final strings = AppStrings.forLanguage(AppLanguage.english);

  test('Google Maps web URL uses latitude,longitude destination order', () {
    final uri = googleMapsWebRouteUri(destination);

    expect(uri.scheme, 'https');
    expect(uri.host, 'www.google.com');
    expect(uri.path, '/maps/dir/');
    expect(uri.queryParameters, <String, String>{
      'api': '1',
      'destination': '41.3111,69.2797',
      'travelmode': 'driving',
    });
  });

  test('Google Maps native URLs preserve destination coordinates', () {
    expect(
      googleMapsAndroidRouteUri(destination).toString(),
      'google.navigation:q=41.3111,69.2797&mode=d',
    );
    expect(
      googleMapsIosRouteUri(destination).toString(),
      'comgooglemaps://?daddr=41.3111,69.2797&directionsmode=driving',
    );
  });

  test('Yandex Maps web and native URLs use latitude,longitude rtext order',
      () {
    final webUri = yandexMapsWebRouteUri(destination);
    final nativeUri = yandexMapsNativeRouteUri(destination);

    expect(webUri.scheme, 'https');
    expect(webUri.host, 'yandex.com');
    expect(webUri.path, '/maps/');
    expect(webUri.queryParameters, <String, String>{
      'rtext': '~41.3111,69.2797',
      'rtt': 'auto',
    });
    expect(nativeUri.scheme, 'yandexmaps');
    expect(nativeUri.host, 'maps.yandex.com');
    expect(nativeUri.queryParameters, <String, String>{
      'rtext': '~41.3111,69.2797',
      'rtt': 'auto',
    });
  });

  test('invalid coordinates are rejected', () {
    expect(
      hasValidMapCoordinates(const GeoPoint(latitude: 91, longitude: 69)),
      isFalse,
    );
    expect(
      () => googleMapsWebRouteUri(
        const GeoPoint(latitude: 91, longitude: 69),
      ),
      throwsArgumentError,
    );
  });

  test('public phone numbers become normalized tel URIs', () {
    expect(
      publicPhoneUri('+998 (90) 123-45-67')?.toString(),
      'tel:+998901234567',
    );
    expect(publicPhoneUri('clinic@example.com'), isNull);
    expect(publicPhoneUri(null), isNull);
  });

  testWidgets('actions hide or show Route and Call by available public data',
      (tester) async {
    Future<void> pumpActions({GeoPoint? location, String? phone}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkerDetailActions(
              strings: strings,
              destination: location,
              publicPhone: phone,
            ),
          ),
        ),
      );
    }

    await pumpActions(location: destination, phone: '+998 90 123 45 67');
    expect(find.text('Route'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);

    await pumpActions(location: null, phone: '+998 90 123 45 67');
    expect(find.text('Route'), findsNothing);
    expect(find.text('Call'), findsOneWidget);

    await pumpActions(location: destination);
    expect(find.text('Route'), findsOneWidget);
    expect(find.text('Call'), findsNothing);

    await pumpActions();
    expect(find.text('Route'), findsNothing);
    expect(find.text('Call'), findsNothing);
  });

  testWidgets('place actions can hide Route while keeping public Call',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkerDetailActions(
            strings: strings,
            destination: destination,
            publicPhone: '+998 90 123 45 67',
            showRoute: false,
          ),
        ),
      ),
    );

    expect(find.text('Route'), findsNothing);
    expect(find.text('Call'), findsOneWidget);
  });

  testWidgets('Route opens the Google/Yandex provider chooser', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkerDetailActions(
            strings: strings,
            destination: destination,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Route'));
    await tester.pumpAndSettle();

    expect(find.text('Google Maps'), findsOneWidget);
    expect(find.text('Yandex Maps'), findsOneWidget);
  });
}
