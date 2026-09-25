import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/features/leaderboards/presentation/screens/leaderboard_screen.dart';

void main() {
  test('leaderboard defaults to the month period', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(leaderboardPeriodProvider), 'month');
  });
}
