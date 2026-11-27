import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/planner_board_gaps.dart';
import 'package:task_app/core/module_host/planner_board_types.dart';

void main() {
  test('selection and preview reuse gaps until their own inputs change', () {
    DateTime hour(int value) => DateTime.utc(2026, 11, 24, value);
    BoardItem block(String id, int start, int end) => {
      'id': id,
      'start': hour(start),
      'end': hour(end),
    };
    var reads = 0;
    final cache = PlannerBoardGaps((value) {
      reads++;
      return value as DateTime?;
    });
    final blocks = [block('before', 7, 8), block('after', 12, 13)];
    List<PlannerGap> gaps({List<BoardItem>? preview}) => cache.around(
      blocks,
      'selected',
      hour(9),
      hour(10),
      replacements: preview,
    );
    final selected = gaps();
    expect(selected, [(hour(8), hour(9)), (hour(10), hour(12))]);
    final preview = [block('after', 11, 13)];
    final drag = gaps(preview: preview);
    expect(drag.last, (hour(10), hour(11)));
    final initialReads = reads;
    for (var frame = 0; frame < 10; frame++) {
      expect(gaps(), same(selected));
      expect(gaps(preview: preview), same(drag));
    }
    expect(reads, initialReads);
    expect(gaps(preview: [block('after', 9, 12)]), isEmpty);
    expect(gaps(), same(selected));
    expect(cache.around(blocks, 'selected', hour(8), hour(9)), [
      (hour(9), hour(12)),
    ]);
    final revised = [blocks.first, block('after', 10, 13)];
    expect(cache.around(revised, 'selected', hour(9), hour(10)), [
      (hour(8), hour(9)),
    ]);
  });
}
