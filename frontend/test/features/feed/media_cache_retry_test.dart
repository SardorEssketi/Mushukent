import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/localization/app_strings.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/features/feed/presentation/widgets/feed_card_parts.dart';

void main() {
  const mediaUrl = 'https://media.mushukistan.uz/posts/thumb.jpg';

  testWidgets('a failed Feed image retries once with a fresh cache key',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: FeedMedia(
            photoUrl: mediaUrl,
            photoUrls: const [mediaUrl],
            strings: AppStrings.forLanguage(AppLanguage.english),
          ),
        ),
      ),
    ));

    final original = tester.widget<Image>(find.byType(Image).first);
    expect((original.image as NetworkImage).url, mediaUrl);

    final retry = original.errorBuilder!(
      tester.element(find.byType(Image).first),
      Exception('stale cached response'),
      StackTrace.empty,
    ) as Image;
    final retryUri = Uri.parse((retry.image as NetworkImage).url);
    expect(retryUri.origin + retryUri.path, mediaUrl);
    expect(retryUri.queryParameters['_retry'], isNotEmpty);
    expect(
      retry.errorBuilder!(
        tester.element(find.byType(Image).first),
        Exception('origin unavailable'),
        StackTrace.empty,
      ),
      isA<Center>(),
    );
  });

  testWidgets('a failed Feed avatar also retries with a fresh cache key',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: FeedAuthorAvatar(name: 'Cat', avatarUrl: mediaUrl),
      ),
    ));

    final original = tester.widget<Image>(find.byType(Image).first);
    final retry = original.errorBuilder!(
      tester.element(find.byType(Image).first),
      Exception('stale cached response'),
      StackTrace.empty,
    ) as Image;
    expect(
        Uri.parse((retry.image as NetworkImage).url).queryParameters['_retry'],
        isNotEmpty);
    expect(
      retry.errorBuilder!(
        tester.element(find.byType(Image).first),
        Exception('origin unavailable'),
        StackTrace.empty,
      ),
      isA<CircleAvatar>(),
    );
  });

  testWidgets('retry preserves existing query values and URL fragment',
      (tester) async {
    const url = '$mediaUrl?tag=first&tag=second&token=a%2Bb#preview';
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: FeedAuthorAvatar(name: 'Cat', avatarUrl: url)),
    ));

    final original = tester.widget<Image>(find.byType(Image).first);
    final retry = original.errorBuilder!(
      tester.element(find.byType(Image).first),
      Exception('cached failure'),
      StackTrace.empty,
    ) as Image;
    final retryUrl = (retry.image as NetworkImage).url;
    final retryUri = Uri.parse(retryUrl);

    expect(retryUrl,
        startsWith('$mediaUrl?tag=first&tag=second&token=a%2Bb&_retry='));
    expect(retryUri.queryParametersAll['tag'], ['first', 'second']);
    expect(retryUri.fragment, 'preview');
  });
}
