/// Date and time formats for tasks.
///
/// Quackers' server works only in the user's local wall-clock time, as
/// "YYYY-MM-DD" dates and 24-hour "HH:MM" times, so the app is the only place a
/// [DateTime] is ever built from them. The wire helpers here are the two ends
/// of that contract; the display helpers keep the same task reading the same
/// way in the list, the calendar and Quackers' proposals.
library;

const List<String> _shortWeekdays = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

const List<String> _shortMonths = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _two(int value) => value.toString().padLeft(2, '0');

/// "2026-10-03".
String formatWireDate(DateTime date) =>
    '${date.year}-${_two(date.month)}-${_two(date.day)}';

/// "17:05", from minutes after midnight.
String formatWireTime(int minuteOfDay) =>
    '${_two(minuteOfDay ~/ 60)}:${_two(minuteOfDay % 60)}';

/// Midnight on a "YYYY-MM-DD" date, or null if it is not a real date.
DateTime? parseWireDate(Object? value) {
  if (value is! String) return null;
  final RegExpMatch? match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})$',
  ).firstMatch(value);
  if (match == null) return null;

  final int year = int.parse(match.group(1)!);
  final int month = int.parse(match.group(2)!);
  final int day = int.parse(match.group(3)!);
  final DateTime date = DateTime(year, month, day);
  // DateTime rolls 30 February over into March; a real date survives intact.
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

/// Minutes after midnight for a 24-hour "HH:MM" time, or null if invalid.
int? parseWireTime(Object? value) {
  if (value is! String) return null;
  final RegExpMatch? match = RegExp(
    r'^([01]\d|2[0-3]):([0-5]\d)$',
  ).firstMatch(value);
  if (match == null) return null;
  return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
}

/// Minutes after midnight of [date]'s wall-clock time.
int minuteOfDay(DateTime date) => date.hour * 60 + date.minute;

/// [date]'s day at [minuteOfDay], or midnight when there is no time.
///
/// Built from fields rather than by adding a Duration, so a daylight-saving
/// change that day cannot shift the result by an hour.
DateTime atMinute(DateTime date, int? minuteOfDay) => DateTime(
  date.year,
  date.month,
  date.day,
  (minuteOfDay ?? 0) ~/ 60,
  (minuteOfDay ?? 0) % 60,
);

/// "5:00 PM".
String formatClock(int minuteOfDay) {
  final int hour = (minuteOfDay ~/ 60) % 24;
  final int minute = minuteOfDay % 60;
  final int twelveHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$twelveHour:${_two(minute)} ${hour < 12 ? 'AM' : 'PM'}';
}

/// "5:00–6:30 PM", or "11:30 AM–12:30 PM" when the range crosses noon.
String formatClockRange(int startMinute, int durationMinutes) {
  final String start = formatClock(startMinute);
  final String end = formatClock(startMinute + durationMinutes);
  final String startPeriod = start.substring(start.length - 2);
  final String endPeriod = end.substring(end.length - 2);
  if (startPeriod == endPeriod) {
    return '${start.substring(0, start.length - 3)}–$end';
  }
  return '$start–$end';
}

/// "30 min", "1 hr", "1 hr 30 min".
String formatDuration(int minutes) {
  final int hours = minutes ~/ 60;
  final int rest = minutes % 60;
  if (hours == 0) return '$rest min';
  if (rest == 0) return '$hours hr';
  return '$hours hr $rest min';
}

/// "Sat, Oct 3".
String formatShortDate(DateTime date) =>
    '${_shortWeekdays[date.weekday - 1]}, '
    '${_shortMonths[date.month - 1]} ${date.day}';
