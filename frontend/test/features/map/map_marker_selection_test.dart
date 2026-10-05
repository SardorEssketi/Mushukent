import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/features/map/application/map_marker_selection.dart';

void main() {
  test('selecting a marker notifies only its old and new markers', () {
    final selection = MapMarkerSelection();
    final counts = <String, int>{'first': 0, 'second': 0, 'other': 0};
    for (final key in counts.keys) {
      selection
          .listenableFor(key)
          .addListener(() => counts[key] = counts[key]! + 1);
    }
    selection.select('first');
    expect(counts, {'first': 1, 'second': 0, 'other': 0});
    selection.select('second');
    expect(counts, {'first': 2, 'second': 1, 'other': 0});
    selection.clearIfSelected('first');
    expect(counts['second'], 1);
    selection.clearIfSelected('second');
    expect(counts, {'first': 2, 'second': 2, 'other': 0});
    selection.dispose();
  });

  test('discarded viewport markers release their selection listeners', () {
    final selection = MapMarkerSelection();
    final old = selection.listenableFor('old');
    selection.retainKeys({'old'});
    selection.retainKeys({'new'});
    expect(selection.listenableFor('old'), isNot(same(old)));
    selection.dispose();
  });
}
