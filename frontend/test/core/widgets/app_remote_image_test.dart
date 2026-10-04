import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/widgets/app_remote_image.dart';

void main() {
  test('retry URL preserves query values and fragment for app media', () {
    const original =
        'https://media.mushukistan.uz/posts/a.jpg?tag=one&tag=two&token=a%2Bb#preview';
    final retry = retryUrlForAppMedia(original)!;
    final uri = Uri.parse(retry);

    expect(
        retry,
        startsWith('https://media.mushukistan.uz/posts/a.jpg?'
            'tag=one&tag=two&token=a%2Bb&_retry='));
    expect(uri.queryParametersAll['tag'], ['one', 'two']);
    expect(uri.fragment, 'preview');
  });

  test('third-party and lookalike hosts never get a retry URL', () {
    expect(retryUrlForAppMedia('https://example.com/cat.jpg'), isNull);
    expect(retryUrlForAppMedia('https://media.mushukistan.uz.evil.com/a.jpg'),
        isNull);
    expect(retryUrlForAppMedia('https://mushukistan.uz/media/a.jpg'), isNull);
  });

  testWidgets('retry image has only a terminal fallback', (tester) async {
    const original = 'https://media.mushukistan.uz/posts/a.jpg';
    await tester.pumpWidget(const MaterialApp(
      home: AppRemoteImage(
        original,
        errorBuilder: _fallback,
      ),
    ));

    final firstImage = tester.widget<Image>(find.byType(Image).first);
    expect((firstImage.image as NetworkImage).url, original);
    final retryImage = firstImage.errorBuilder!(
      tester.element(find.byType(Image).first),
      Exception('cached failure'),
      StackTrace.empty,
    ) as Image;
    expect((retryImage.image as NetworkImage).url,
        contains('media.mushukistan.uz/posts/a.jpg?_retry='));
    expect(
      retryImage.errorBuilder!(
        tester.element(find.byType(Image).first),
        Exception('retry failure'),
        StackTrace.empty,
      ),
      isA<Icon>(),
    );
  });

  testWidgets('third-party failure has no cache-busting retry', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: AppRemoteImage(
        'https://example.com/cat.jpg',
        errorBuilder: _fallback,
      ),
    ));

    final firstImage = tester.widget<Image>(find.byType(Image).first);
    expect(
      firstImage.errorBuilder!(
        tester.element(find.byType(Image).first),
        Exception('external failure'),
        StackTrace.empty,
      ),
      isA<Icon>(),
    );
  });
}

Widget _fallback(BuildContext context, Object error, StackTrace? stackTrace) =>
    const Icon(Icons.broken_image_outlined);
