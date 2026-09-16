/// Grid maths for the month view.
///
/// The week runs Sunday..Saturday. `DateTime` numbers weekdays Monday..Sunday
/// as 1..7, so every placement goes through [columnForWeekday] rather than
/// subtracting one, which would put Monday first.
library;

/// Column a weekday occupies, with Sunday at 0 and Saturday at 6.
///
/// [weekday] uses `DateTime`'s numbering: 1 = Monday ... 7 = Sunday.
int columnForWeekday(int weekday) => weekday % 7;

/// Blank cells before the 1st of the month in a Sunday-first grid.
int leadingBlankDays(DateTime firstOfMonth) =>
    columnForWeekday(firstOfMonth.weekday);

/// Number of days in the month containing [date].
int daysInMonth(DateTime date) => DateTime(date.year, date.month + 1, 0).day;

/// Rows needed to show the whole month.
int weekRowsInMonth(DateTime date) {
  final DateTime first = DateTime(date.year, date.month, 1);
  return ((leadingBlankDays(first) + daysInMonth(date)) / 7).ceil();
}
