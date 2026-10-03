import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_planner/data/task_time.dart';

void main() {
  group('wire format', () {
    test('dates round-trip', () {
      final DateTime date = DateTime(2026, 3, 9);
      expect(formatWireDate(date), '2026-03-09');
      expect(parseWireDate('2026-03-09'), date);
    });

    test('impossible or malformed dates are rejected', () {
      // DateTime would quietly roll this over into March.
      expect(parseWireDate('2026-02-30'), isNull);
      expect(parseWireDate('2026-2-3'), isNull);
      expect(parseWireDate(20260203), isNull);
      expect(parseWireDate(null), isNull);
    });

    test('times round-trip as minutes after midnight', () {
      expect(formatWireTime(17 * 60 + 5), '17:05');
      expect(parseWireTime('17:05'), 17 * 60 + 5);
      expect(parseWireTime('00:00'), 0);
    });

    test('out-of-range times are rejected', () {
      expect(parseWireTime('24:00'), isNull);
      expect(parseWireTime('9:00'), isNull);
      expect(parseWireTime('12:60'), isNull);
    });
  });

  test('atMinute builds the wall-clock time on that day', () {
    expect(atMinute(DateTime(2026, 11, 1), 90), DateTime(2026, 11, 1, 1, 30));
    expect(atMinute(DateTime(2026, 11, 1), null), DateTime(2026, 11, 1));
  });

  group('display', () {
    test('clock times are twelve-hour', () {
      expect(formatClock(0), '12:00 AM');
      expect(formatClock(9 * 60 + 5), '9:05 AM');
      expect(formatClock(12 * 60), '12:00 PM');
      expect(formatClock(17 * 60 + 30), '5:30 PM');
    });

    test('a range shares its AM or PM when it can', () {
      expect(formatClockRange(17 * 60, 90), '5:00–6:30 PM');
      expect(formatClockRange(11 * 60 + 30, 60), '11:30 AM–12:30 PM');
    });

    test('durations read naturally', () {
      expect(formatDuration(30), '30 min');
      expect(formatDuration(60), '1 hr');
      expect(formatDuration(150), '2 hr 30 min');
    });

    test('short dates name the weekday', () {
      expect(formatShortDate(DateTime(2026, 10, 3)), 'Sat, Oct 3');
    });
  });
}
