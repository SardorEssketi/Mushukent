// The Posts and Comments counts on the profile card open lists, so they carry
// an "open" arrow; the Likes received count is static and does not.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/localization/app_strings.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/features/profile/presentation/widgets/profile_components.dart';

void main() {
  testWidgets('tappable stats show an open icon and stay the same height',
      (tester) async {
    var postsTaps = 0;
    var commentsTaps = 0;
    final strings = AppStrings.forLanguage(AppLanguage.english);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          child: ProfileSummaryCard(
            name: 'Sardor',
            strings: strings,
            observationCount: 4,
            likesReceived: 7,
            commentCount: 2,
            onObservationsTap: () => postsTaps++,
            onCommentsTap: () => commentsTaps++,
          ),
        ),
      ),
    ));
    final icons = find.byKey(const ValueKey('profile-stat-open-icon'));
    expect(icons, findsNWidgets(2));

    // Icons sit on the Posts and Comments tiles, not on Likes received.
    final likes = tester.getRect(find.text('7'));
    for (final rect in icons
        .evaluate()
        .map((e) => tester.getRect(find.byWidget(e.widget)))) {
      expect((rect.center.dx - likes.center.dx).abs(), greaterThan(60));
    }

    final heights = [
      for (final value in ['4', '7', '2'])
        tester
            .getSize(find
                .ancestor(of: find.text(value), matching: find.byType(Material))
                .first)
            .height,
    ];
    expect(heights.toSet(), hasLength(1));

    await tester.tap(find.text('4'));
    await tester.tap(find.text('2'));
    expect(postsTaps, 1);
    expect(commentsTaps, 1);
  });
}
