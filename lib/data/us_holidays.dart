/// US holidays shown on the calendar.
///
/// Everything is computed, not hardcoded per year, so the calendar stays
/// correct however far the user scrolls. Dates come in three shapes:
///
///   * fixed      -- same month and day every year (Christmas)
///   * nth / last -- an ordinal weekday (Thanksgiving, Memorial Day)
///   * Easter     -- the Gregorian computus, which Mother's Day and the rest
///                   of the movable feasts key off
library;

/// A single observance on one date.
class Holiday {
  const Holiday({
    required this.name,
    required this.date,
    this.emoji,
    this.isFederal = false,
  });

  final String name;
  final DateTime date;

  /// Shown on the calendar. Null for observances where a festive emoji would
  /// strike the wrong note.
  final String? emoji;

  /// Federal holidays sort first when two land on the same day.
  final bool isFederal;

  String get label => emoji == null ? name : '$emoji $name';
}

/// Returns the [n]th [weekday] of a month, e.g. the 4th Thursday of November.
///
/// [weekday] uses `DateTime`'s numbering: 1 = Monday ... 7 = Sunday.
DateTime _nthWeekday(int year, int month, int weekday, int n) {
  final DateTime first = DateTime(year, month, 1);
  final int offset = (weekday - first.weekday + 7) % 7;
  return DateTime(year, month, 1 + offset + (n - 1) * 7);
}

/// Returns the last [weekday] of a month, e.g. the last Monday of May.
DateTime _lastWeekday(int year, int month, int weekday) {
  // Day zero of the following month is the last day of this one.
  final DateTime last = DateTime(year, month + 1, 0);
  final int offset = (last.weekday - weekday + 7) % 7;
  return DateTime(year, month, last.day - offset);
}

/// Easter Sunday, by the anonymous Gregorian algorithm.
///
/// Easter is the first Sunday after the first ecclesiastical full moon on or
/// after 21 March, which is why it needs a dedicated calculation rather than a
/// rule about weekdays.
DateTime easterSunday(int year) {
  final int a = year % 19;
  final int b = year ~/ 100;
  final int c = year % 100;
  final int d = b ~/ 4;
  final int e = b % 4;
  final int f = (b + 8) ~/ 25;
  final int g = (b - f + 1) ~/ 3;
  final int h = (19 * a + b - d - g + 15) % 30;
  final int i = c ~/ 4;
  final int k = c % 4;
  final int l = (32 + 2 * e + 2 * i - h - k) % 7;
  final int m = (a + 11 * h + 22 * l) ~/ 451;
  final int month = (h + l - 7 * m + 114) ~/ 31;
  final int day = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime(year, month, day);
}

/// Computes and looks up the observances for a given year.
abstract final class UsHolidays {
  /// Built lazily per year and kept, since the month grid asks about up to 42
  /// dates every time it rebuilds.
  static final Map<int, Map<int, List<Holiday>>> _byYear =
      <int, Map<int, List<Holiday>>>{};

  /// Every observance in [year], in date order.
  static List<Holiday> forYear(int year) {
    final DateTime easter = easterSunday(year);

    final List<Holiday> holidays = <Holiday>[
      // --- Federal ---------------------------------------------------------
      Holiday(
        name: "New Year's Day",
        date: DateTime(year, 1, 1),
        emoji: '🎉',
        isFederal: true,
      ),
      Holiday(
        name: 'Martin Luther King Jr. Day',
        date: _nthWeekday(year, 1, DateTime.monday, 3),
        isFederal: true,
      ),
      Holiday(
        name: "Presidents' Day",
        date: _nthWeekday(year, 2, DateTime.monday, 3),
        emoji: '🇺🇸',
        isFederal: true,
      ),
      Holiday(
        name: 'Memorial Day',
        date: _lastWeekday(year, 5, DateTime.monday),
        emoji: '🇺🇸',
        isFederal: true,
      ),
      Holiday(
        name: 'Juneteenth',
        date: DateTime(year, 6, 19),
        emoji: '🎊',
        isFederal: true,
      ),
      Holiday(
        name: 'Independence Day',
        date: DateTime(year, 7, 4),
        emoji: '🎆',
        isFederal: true,
      ),
      Holiday(
        name: 'Labor Day',
        date: _nthWeekday(year, 9, DateTime.monday, 1),
        emoji: '🛠️',
        isFederal: true,
      ),
      Holiday(
        name: "Columbus Day / Indigenous Peoples' Day",
        date: _nthWeekday(year, 10, DateTime.monday, 2),
        isFederal: true,
      ),
      Holiday(
        name: 'Veterans Day',
        date: DateTime(year, 11, 11),
        emoji: '🎖️',
        isFederal: true,
      ),
      Holiday(
        name: 'Thanksgiving',
        date: _nthWeekday(year, 11, DateTime.thursday, 4),
        emoji: '🦃',
        isFederal: true,
      ),
      Holiday(
        name: 'Christmas Day',
        date: DateTime(year, 12, 25),
        emoji: '🎄',
        isFederal: true,
      ),

      // --- Widely observed, not federal ------------------------------------
      Holiday(
        name: "Valentine's Day",
        date: DateTime(year, 2, 14),
        emoji: '💝',
      ),
      Holiday(
        name: "St. Patrick's Day",
        date: DateTime(year, 3, 17),
        emoji: '☘️',
      ),
      Holiday(name: 'Easter Sunday', date: easter, emoji: '🐣'),
      Holiday(
        name: "Mother's Day",
        date: _nthWeekday(year, 5, DateTime.sunday, 2),
        emoji: '💐',
      ),
      Holiday(
        name: "Father's Day",
        date: _nthWeekday(year, 6, DateTime.sunday, 3),
        emoji: '👔',
      ),
      Holiday(name: 'Halloween', date: DateTime(year, 10, 31), emoji: '🎃'),
      Holiday(name: 'Christmas Eve', date: DateTime(year, 12, 24), emoji: '🎁'),
      Holiday(
        name: "New Year's Eve",
        date: DateTime(year, 12, 31),
        emoji: '🎊',
      ),
    ]..sort((Holiday a, Holiday b) => a.date.compareTo(b.date));

    return holidays;
  }

  /// Observances falling on [date]. Usually zero or one, but Juneteenth and
  /// Father's Day share 19 June in some years, so this returns a list.
  ///
  /// Federal holidays come first, so callers showing a single badge show the
  /// more significant one.
  static List<Holiday> on(DateTime date) {
    final Map<int, List<Holiday>> index = _byYear.putIfAbsent(date.year, () {
      final Map<int, List<Holiday>> built = <int, List<Holiday>>{};
      for (final Holiday holiday in forYear(date.year)) {
        built.putIfAbsent(_key(holiday.date), () => <Holiday>[]).add(holiday);
      }
      for (final List<Holiday> sameDay in built.values) {
        sameDay.sort((Holiday a, Holiday b) {
          if (a.isFederal == b.isFederal) return 0;
          return a.isFederal ? -1 : 1;
        });
      }
      return built;
    });

    return index[_key(date)] ?? const <Holiday>[];
  }

  /// The observance to show when there is only room for one, or null.
  static Holiday? primaryOn(DateTime date) {
    final List<Holiday> found = on(date);
    return found.isEmpty ? null : found.first;
  }

  static int _key(DateTime date) => date.month * 100 + date.day;
}
