import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_planner/data/calendar_layout.dart';

void main() {
  test('Sunday is the first column and Saturday the last', () {
    expect(columnForWeekday(DateTime.sunday), 0);
    expect(columnForWeekday(DateTime.monday), 1);
    expect(columnForWeekday(DateTime.tuesday), 2);
    expect(columnForWeekday(DateTime.wednesday), 3);
    expect(columnForWeekday(DateTime.thursday), 4);
    expect(columnForWeekday(DateTime.friday), 5);
    expect(columnForWeekday(DateTime.saturday), 6);
  });

  test('a month starting on Sunday has no leading blanks', () {
    // 1 February 2026 is a Sunday.
    expect(DateTime(2026, 2, 1).weekday, DateTime.sunday);
    expect(leadingBlankDays(DateTime(2026, 2, 1)), 0);
  });

  test('a month starting on Saturday has six leading blanks', () {
    // 1 August 2026 is a Saturday.
    expect(DateTime(2026, 8, 1).weekday, DateTime.saturday);
    expect(leadingBlankDays(DateTime(2026, 8, 1)), 6);
  });

  test('every day of every month lands in its own weekday column', () {
    // The real guarantee: whatever the grid draws in column N is a date whose
    // weekday belongs in column N, for Sunday-first.
    for (int year = 2024; year <= 2030; year++) {
      for (int month = 1; month <= 12; month++) {
        final DateTime first = DateTime(year, month, 1);
        final int blanks = leadingBlankDays(first);

        for (int day = 1; day <= daysInMonth(first); day++) {
          final DateTime date = DateTime(year, month, day);
          final int cellIndex = blanks + day - 1;
          expect(
            cellIndex % 7,
            columnForWeekday(date.weekday),
            reason: '$date placed in the wrong column',
          );
        }
      }
    }
  });

  test('daysInMonth handles February in leap and common years', () {
    expect(daysInMonth(DateTime(2024, 2, 1)), 29);
    expect(daysInMonth(DateTime(2026, 2, 1)), 28);
    expect(daysInMonth(DateTime(2000, 2, 1)), 29);
    expect(daysInMonth(DateTime(1900, 2, 1)), 28);
    expect(daysInMonth(DateTime(2026, 12, 1)), 31);
  });

  test('row count always covers the whole month', () {
    for (int year = 2024; year <= 2030; year++) {
      for (int month = 1; month <= 12; month++) {
        final DateTime date = DateTime(year, month, 1);
        final int rows = weekRowsInMonth(date);
        expect(
          rows * 7,
          greaterThanOrEqualTo(leadingBlankDays(date) + daysInMonth(date)),
          reason: '$year-$month needs more rows',
        );
        expect(rows, inInclusiveRange(4, 6));
      }
    }
  });
}
