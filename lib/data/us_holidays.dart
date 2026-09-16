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

import 'calendar_conversions.dart';

/// Marker used where a festive emoji would strike the wrong note -- days of
/// remembrance, mourning, atonement or fasting. Keeps the day visible on the
/// calendar without celebrating it.
const String kNeutralMarker = '🟢';

/// A single observance on one date.
class Holiday {
  const Holiday({
    required this.name,
    required this.date,
    this.emoji = kNeutralMarker,
    this.isFederal = false,
    this.isApproximate = false,
  });

  final String name;
  final DateTime date;

  /// Shown on the calendar. Defaults to [kNeutralMarker] for observances where
  /// a festive emoji would be inappropriate.
  final String emoji;

  /// Federal holidays sort first when two land on the same day.
  final bool isFederal;

  /// True when the date is computed from lunar observation and may differ from
  /// local practice by a day. Surfaced in the day view.
  final bool isApproximate;

  String get label => '$emoji $name';
}

/// Adds whole days without a daylight-saving transition shifting the result
/// onto the wrong date.
///
/// `DateTime.add` works in absolute time, so stepping back across a
/// spring-forward boundary lands at 23:00 the previous day. Going through the
/// constructor keeps the arithmetic on the calendar, where it belongs.
DateTime _addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

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
    return <Holiday>[
      ..._federal(year),
      ..._christian(year),
      ..._jewish(year),
      ..._islamic(year),
      ..._cultural(year),
      ..._remembrance(year),
      ..._justForFun(year),
    ]..sort((Holiday a, Holiday b) => a.date.compareTo(b.date));
  }

  // --- Federal --------------------------------------------------------------

  static List<Holiday> _federal(int year) => <Holiday>[
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
  ];

  // --- Christian ------------------------------------------------------------

  /// Most of these are fixed offsets from Easter, so the computus drives them.
  static List<Holiday> _christian(int year) {
    final DateTime easter = easterSunday(year);
    DateTime fromEaster(int days) => _addDays(easter, days);

    final DateTime orthodoxEaster = gregorianFromRd(
      rdFromJulian(year, 1, 1) + _julianEasterOffset(year),
    );

    return <Holiday>[
      Holiday(name: 'Epiphany', date: DateTime(year, 1, 6), emoji: '⭐'),
      // Mardi Gras is the day before Ash Wednesday.
      Holiday(name: 'Mardi Gras', date: fromEaster(-47), emoji: '🎭'),
      Holiday(name: 'Ash Wednesday', date: fromEaster(-46)),
      Holiday(name: 'Palm Sunday', date: fromEaster(-7), emoji: '🌿'),
      Holiday(name: 'Good Friday', date: fromEaster(-2)),
      Holiday(name: 'Easter Sunday', date: easter, emoji: '🐣'),
      if (orthodoxEaster != easter)
        Holiday(name: 'Orthodox Easter', date: orthodoxEaster, emoji: '🐣'),
      Holiday(name: 'Pentecost', date: fromEaster(49), emoji: '🕊️'),
      Holiday(name: 'All Saints\' Day', date: DateTime(year, 11, 1)),
      // Advent begins on the fourth Sunday before Christmas.
      Holiday(
        name: 'First Sunday of Advent',
        date: _addDays(_sundayBefore(DateTime(year, 12, 25)), -21),
        emoji: '🕯️',
      ),
      Holiday(name: 'Christmas Eve', date: DateTime(year, 12, 24), emoji: '🎁'),
      Holiday(
        name: 'Orthodox Christmas',
        date: gregorianFromRd(rdFromJulian(year - 1, 12, 25)),
        emoji: '🎄',
      ),
    ];
  }

  // --- Jewish ---------------------------------------------------------------

  /// Hebrew dates are computed, not tabulated, so they stay correct for any
  /// year. Observance begins the preceding sunset; the date shown is the day
  /// the holiday falls on.
  static List<Holiday> _jewish(int year) {
    final List<Holiday> found = <Holiday>[];

    for (final int h in hebrewYearsOverlapping(year)) {
      void add(String name, String month, int day, String emoji) {
        final DateTime date = gregorianFromRd(rdFromHebrew(h, month, day));
        if (date.year == year) {
          found.add(Holiday(name: name, date: date, emoji: emoji));
        }
      }

      add('Rosh Hashanah', 'Tishrei', 1, '🍎');
      add('Yom Kippur', 'Tishrei', 10, kNeutralMarker);
      add('Sukkot', 'Tishrei', 15, '🌿');
      add('Simchat Torah', 'Tishrei', 22, '📜');
      add('Hanukkah begins', 'Kislev', 25, '🕎');
      add('Tu BiShvat', 'Shevat', 15, '🌳');
      add('Purim', 'Adar', 14, '🎭');
      add('Passover begins', 'Nisan', 15, '🍷');
      add('Yom HaShoah', 'Nisan', 27, kNeutralMarker);
      add('Shavuot', 'Sivan', 6, '🌾');
      add("Tisha B'Av", 'Av', 9, kNeutralMarker);
    }

    return found;
  }

  // --- Islamic --------------------------------------------------------------

  /// Dates come from the tabular Islamic calendar. Actual observance follows a
  /// local sighting of the crescent moon and can differ by a day, so these are
  /// flagged approximate.
  static List<Holiday> _islamic(int year) {
    final List<Holiday> found = <Holiday>[];

    for (final int i in islamicYearsOverlapping(year)) {
      void add(String name, int month, int day, String emoji) {
        final DateTime date = gregorianFromRd(rdFromIslamic(i, month, day));
        if (date.year == year) {
          found.add(
            Holiday(
              name: name,
              date: date,
              emoji: emoji,
              isApproximate: true,
            ),
          );
        }
      }

      add('Islamic New Year', 1, 1, kNeutralMarker);
      add('Ashura', 1, 10, kNeutralMarker);
      add('Mawlid al-Nabi', 3, 12, kNeutralMarker);
      add('Ramadan begins', 9, 1, '🌙');
      add('Eid al-Fitr', 10, 1, '🎉');
      add('Eid al-Adha', 12, 10, '🌙');
    }

    return found;
  }

  // --- Widely observed, not federal ----------------------------------------

  static List<Holiday> _cultural(int year) => <Holiday>[
    Holiday(name: 'Groundhog Day', date: DateTime(year, 2, 2), emoji: '🐿️'),
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
    Holiday(name: 'Earth Day', date: DateTime(year, 4, 22), emoji: '🌍'),
    Holiday(name: 'Cinco de Mayo', date: DateTime(year, 5, 5), emoji: '🌮'),
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
    Holiday(name: 'Flag Day', date: DateTime(year, 6, 14), emoji: '🇺🇸'),
    Holiday(
      name: 'Grandparents Day',
      date: _addDays(_nthWeekday(year, 9, DateTime.monday, 1), 6),
      emoji: '👵',
    ),
    Holiday(name: 'Halloween', date: DateTime(year, 10, 31), emoji: '🎃'),
    Holiday(
      name: 'Election Day',
      // Tuesday after the first Monday in November.
      date: _addDays(_nthWeekday(year, 11, DateTime.monday, 1), 1),
      emoji: '🗳️',
    ),
    Holiday(
      name: 'Black Friday',
      date: _addDays(_nthWeekday(year, 11, DateTime.thursday, 4), 1),
      emoji: '🛍️',
    ),
    Holiday(
      name: 'Cyber Monday',
      date: _addDays(_nthWeekday(year, 11, DateTime.thursday, 4), 4),
      emoji: '💻',
    ),
    Holiday(name: 'Kwanzaa begins', date: DateTime(year, 12, 26), emoji: '🕯️'),
    Holiday(name: 'Boxing Day', date: DateTime(year, 12, 26), emoji: '📦'),
    Holiday(
      name: "New Year's Eve",
      date: DateTime(year, 12, 31),
      emoji: '🎊',
    ),
  ];

  // --- Remembrance ----------------------------------------------------------

  /// Days of mourning or remembrance. All carry the neutral marker.
  static List<Holiday> _remembrance(int year) => <Holiday>[
    Holiday(
      name: 'International Holocaust Remembrance Day',
      date: DateTime(year, 1, 27),
    ),
    Holiday(name: 'Patriot Day', date: DateTime(year, 9, 11)),
    Holiday(
      name: 'Pearl Harbor Remembrance Day',
      date: DateTime(year, 12, 7),
    ),
  ];

  // --- Just for fun ---------------------------------------------------------

  static List<Holiday> _justForFun(int year) => <Holiday>[
    Holiday(name: 'Pi Day', date: DateTime(year, 3, 14), emoji: '🥧'),
    Holiday(name: "April Fools' Day", date: DateTime(year, 4, 1), emoji: '🃏'),
    Holiday(name: 'Star Wars Day', date: DateTime(year, 5, 4), emoji: '🚀'),
    Holiday(
      name: 'National Donut Day',
      date: _nthWeekday(year, 6, DateTime.friday, 1),
      emoji: '🍩',
    ),
    Holiday(
      name: 'Talk Like a Pirate Day',
      date: DateTime(year, 9, 19),
      emoji: '🏴‍☠️',
    ),
    if (isGregorianLeapYear(year))
      Holiday(name: 'Leap Day', date: DateTime(year, 2, 29), emoji: '🐸'),
    // Every Friday the 13th in the year -- there can be one, two or three.
    for (int month = 1; month <= 12; month++)
      if (DateTime(year, month, 13).weekday == DateTime.friday)
        Holiday(
          name: 'Friday the 13th',
          date: DateTime(year, month, 13),
          emoji: '🖤',
        ),
  ];

  /// Offset in days from 1 January Julian to Orthodox Easter, via the Julian
  /// computus (Meton's cycle, without the Gregorian corrections).
  static int _julianEasterOffset(int year) {
    final int a = year % 4;
    final int b = year % 7;
    final int c = year % 19;
    final int d = (19 * c + 15) % 30;
    final int e = (2 * a + 4 * b - d + 34) % 7;
    final int month = (d + e + 114) ~/ 31;
    final int day = ((d + e + 114) % 31) + 1;
    return rdFromJulian(year, month, day) - rdFromJulian(year, 1, 1);
  }

  /// The Sunday on or before [date].
  static DateTime _sundayBefore(DateTime date) =>
      _addDays(date, -(date.weekday % 7));

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
