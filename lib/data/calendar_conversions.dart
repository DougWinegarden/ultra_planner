/// Conversions between the Gregorian calendar and the Hebrew and Islamic
/// calendars, for holidays that do not sit on a fixed Gregorian date.
///
/// Everything routes through "fixed days" (Rata Die): day 1 is 1 January 1 CE
/// in the proleptic Gregorian calendar. Converting each calendar to and from
/// that one scale keeps the arithmetic simple and testable.
library;

// --- Rata Die <-> Gregorian -------------------------------------------------

bool isGregorianLeapYear(int year) =>
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

/// Fixed-day number for a Gregorian date.
int rdFromGregorian(int year, int month, int day) {
  final int prior = year - 1;
  final int correction = month <= 2
      ? 0
      : isGregorianLeapYear(year)
      ? -1
      : -2;

  return 365 * prior +
      (prior ~/ 4) -
      (prior ~/ 100) +
      (prior ~/ 400) +
      ((367 * month - 362) ~/ 12) +
      correction +
      day;
}

/// Gregorian date for a fixed-day number, as a midnight local `DateTime`.
///
/// Stepping from the epoch in UTC avoids a daylight-saving shift pushing the
/// result onto the wrong day.
DateTime gregorianFromRd(int rd) {
  final DateTime utc = DateTime.utc(1, 1, 1).add(Duration(days: rd - 1));
  return DateTime(utc.year, utc.month, utc.day);
}

// --- Hebrew calendar --------------------------------------------------------

/// Fixed day of 1 Tishrei, year 1 of the Hebrew calendar.
const int _hebrewEpoch = -1373427;

/// Whether a Hebrew year has a second month of Adar.
bool isHebrewLeapYear(int hYear) => ((7 * hYear + 1) % 19) < 7;

/// Days from the Hebrew epoch to the molad-derived new year, before the
/// postponements that [_hebrewYearDelay] applies.
int _hebrewElapsedDays(int hYear) {
  final int monthsElapsed = (235 * hYear - 234) ~/ 19;
  final int partsElapsed = 12084 + 13753 * monthsElapsed;
  int day = monthsElapsed * 29 + partsElapsed ~/ 25920;

  // "Lo ADU rosh": Rosh Hashanah cannot fall on Sunday, Wednesday or Friday.
  if ((3 * (day + 1)) % 7 < 3) {
    day += 1;
  }
  return day;
}

/// Extra postponement so no year ends up an illegal length.
int _hebrewYearDelay(int hYear) {
  final int last = _hebrewElapsedDays(hYear - 1);
  final int present = _hebrewElapsedDays(hYear);
  final int next = _hebrewElapsedDays(hYear + 1);

  if (next - present == 356) return 2;
  if (present - last == 382) return 1;
  return 0;
}

/// Fixed day of 1 Tishrei (Rosh Hashanah) for a Hebrew year.
int hebrewNewYearRd(int hYear) =>
    _hebrewEpoch + _hebrewElapsedDays(hYear) + _hebrewYearDelay(hYear);

/// Length of a Hebrew year in days: 353-355, or 383-385 in a leap year.
int hebrewYearLength(int hYear) =>
    hebrewNewYearRd(hYear + 1) - hebrewNewYearRd(hYear);

/// Months in order from Tishrei, which is where the Hebrew year begins.
///
/// Heshvan and Kislev flex by a day to absorb the postponements, and leap years
/// insert Adar I before Adar.
List<({String name, int days})> hebrewMonths(int hYear) {
  final int length = hebrewYearLength(hYear);
  final int heshvan = (length == 355 || length == 385) ? 30 : 29;
  final int kislev = (length == 353 || length == 383) ? 29 : 30;

  return <({String name, int days})>[
    (name: 'Tishrei', days: 30),
    (name: 'Heshvan', days: heshvan),
    (name: 'Kislev', days: kislev),
    (name: 'Tevet', days: 29),
    (name: 'Shevat', days: 30),
    if (isHebrewLeapYear(hYear)) (name: 'Adar I', days: 30),
    (name: 'Adar', days: 29),
    (name: 'Nisan', days: 30),
    (name: 'Iyar', days: 29),
    (name: 'Sivan', days: 30),
    (name: 'Tammuz', days: 29),
    (name: 'Av', days: 30),
    (name: 'Elul', days: 29),
  ];
}

/// Fixed day for a Hebrew date, naming the month rather than numbering it —
/// the numbering shifts in leap years, the names do not.
int rdFromHebrew(int hYear, String monthName, int day) {
  int offset = 0;
  for (final ({String name, int days}) month in hebrewMonths(hYear)) {
    if (month.name == monthName) {
      return hebrewNewYearRd(hYear) + offset + day - 1;
    }
    offset += month.days;
  }
  throw ArgumentError('Unknown Hebrew month: $monthName');
}

/// Hebrew years that can contain dates falling in a Gregorian year.
///
/// The Hebrew year turns over in September or October, so any Gregorian year
/// overlaps two of them.
List<int> hebrewYearsOverlapping(int gregorianYear) =>
    <int>[gregorianYear + 3760, gregorianYear + 3761];

// --- Islamic calendar -------------------------------------------------------

/// Fixed day of 1 Muharram, year 1 AH.
const int _islamicEpoch = 227015;

/// Fixed day for a date in the *tabular* Islamic calendar.
///
/// The observed Islamic calendar begins each month on a local sighting of the
/// crescent moon, so a real observance can differ from this by a day either
/// way, and can differ between countries on the same day. Anything shown from
/// this should be treated as approximate.
int rdFromIslamic(int iYear, int month, int day) {
  return _islamicEpoch -
      1 +
      354 * (iYear - 1) +
      ((3 + 11 * iYear) ~/ 30) +
      29 * (month - 1) +
      (month ~/ 2) +
      day;
}

/// Islamic years that can contain dates falling in a Gregorian year.
///
/// The Islamic year is about 354 days, so it drifts backwards through the
/// Gregorian year and a single Gregorian year can touch three of them.
List<int> islamicYearsOverlapping(int gregorianYear) {
  final int approx = ((gregorianYear - 622) * 33 ~/ 32) + 1;
  return <int>[approx - 1, approx, approx + 1];
}

// --- Julian calendar, for Orthodox observances ------------------------------

bool isJulianLeapYear(int year) => year % 4 == 0;

/// Fixed day for a Julian-calendar date.
int rdFromJulian(int year, int month, int day) {
  final int prior = year - 1;
  final int correction = month <= 2
      ? 0
      : isJulianLeapYear(year)
      ? -1
      : -2;

  // The Julian epoch sits two days before the Gregorian one on the RD scale.
  return -2 +
      365 * prior +
      (prior ~/ 4) +
      ((367 * month - 362) ~/ 12) +
      correction +
      day;
}
