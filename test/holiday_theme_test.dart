import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_planner/data/us_holidays.dart';
import 'package:ultra_planner/widgets/holiday_theme.dart';

void main() {
  test('an ordinary day keeps the ocean theme', () {
    // 15 September 2026 is the date the request used as an example of a
    // non-holiday.
    expect(HolidayTheme.forDate(DateTime(2026, 9, 15)), HolidayTheme.ocean);
    expect(HolidayTheme.forDate(DateTime(2026, 9, 15)).isOcean, isTrue);
  });

  test('the named holidays get the drifters that were asked for', () {
    final Map<DateTime, DrifterStyle> cases = <DateTime, DrifterStyle>{
      DateTime(2026, 12, 25): DrifterStyle.sleigh,
      DateTime(2026, 12, 24): DrifterStyle.sleigh,
      DateTime(2026, 10, 31): DrifterStyle.reaper,
      DateTime(2026, 11, 26): DrifterStyle.turkey,
      DateTime(2026, 7, 4): DrifterStyle.fireworks,
      DateTime(2026, 1, 1): DrifterStyle.fireworks,
      DateTime(2026, 12, 31): DrifterStyle.fireworks,
      DateTime(2026, 2, 14): DrifterStyle.heart,
      DateTime(2026, 3, 17): DrifterStyle.rainbowPot,
      DateTime(2026, 4, 5): DrifterStyle.bunny,
      DateTime(2026, 5, 10): DrifterStyle.flower,
      DateTime(2026, 6, 21): DrifterStyle.tie,
      DateTime(2026, 9, 7): DrifterStyle.tool,
    };
    cases.forEach((DateTime date, DrifterStyle style) {
      expect(HolidayTheme.forDate(date).drifter, style, reason: '$date');
    });
  });

  test('themes exist for exactly the agreed major holidays', () {
    const List<String> themed = <String>[
      "New Year's Day",
      'Martin Luther King Jr. Day',
      "Presidents' Day",
      'Memorial Day',
      'Juneteenth',
      'Independence Day',
      'Labor Day',
      "Columbus Day / Indigenous Peoples' Day",
      'Veterans Day',
      'Thanksgiving',
      'Christmas Day',
      "Valentine's Day",
      "St. Patrick's Day",
      'Easter Sunday',
      "Mother's Day",
      "Father's Day",
      'Halloween',
      'Christmas Eve',
      "New Year's Eve",
    ];

    for (final String name in themed) {
      final Holiday holiday = UsHolidays.forYear(
        2026,
      ).firstWhere((Holiday h) => h.name == name);
      expect(
        HolidayTheme.forDate(holiday.date).isOcean,
        isFalse,
        reason: '$name should have its own theme',
      );
    }
  });

  test('minor observances stay on the ocean theme', () {
    // April Fools and the like are on the calendar but do not restyle the app.
    for (final String name in <String>[
      "April Fools' Day",
      'Pi Day',
      'Groundhog Day',
      'Earth Day',
      'Boxing Day',
    ]) {
      final Holiday holiday = UsHolidays.forYear(
        2026,
      ).firstWhere((Holiday h) => h.name == name);
      expect(
        HolidayTheme.forDate(holiday.date).isOcean,
        isTrue,
        reason: '$name should not restyle the app',
      );
    }
  });

  test('every theme carries a full palette', () {
    final Set<HolidayTheme> themes = <HolidayTheme>{
      HolidayTheme.ocean,
      for (int month = 1; month <= 12; month++)
        for (int day = 1; day <= 28; day++)
          HolidayTheme.forDate(DateTime(2026, month, day)),
    };

    for (final HolidayTheme theme in themes) {
      expect(theme.gradient, hasLength(3), reason: theme.name);
      expect(theme.drifterColors, isNotEmpty, reason: theme.name);
      expect(theme.name, isNotEmpty);
    }
  });

  test('the theme follows the chosen date, not today', () {
    // The whole point: previewing Halloween in September must work.
    final HolidayTheme halloween = HolidayTheme.forDate(DateTime(2026, 10, 31));
    expect(halloween.drifter, DrifterStyle.reaper);
    expect(halloween, isNot(HolidayTheme.ocean));
  });

  test('dark themes use light heading text', () {
    // A dark sky with the app's usual navy type would be unreadable.
    for (final HolidayTheme theme in <HolidayTheme>[
      HolidayTheme.christmas,
      HolidayTheme.halloween,
      HolidayTheme.fireworksNight,
      HolidayTheme.independenceDay,
    ]) {
      final double skyLuminance = theme.gradient[1].computeLuminance();
      final double textLuminance = theme.heading.computeLuminance();
      expect(
        textLuminance,
        greaterThan(skyLuminance),
        reason: '${theme.name} heading must be lighter than its sky',
      );
    }
  });

  test('light themes use dark heading text', () {
    for (final HolidayTheme theme in <HolidayTheme>[
      HolidayTheme.ocean,
      HolidayTheme.valentines,
      HolidayTheme.easter,
      HolidayTheme.thanksgiving,
      HolidayTheme.stPatricks,
    ]) {
      final double skyLuminance = theme.gradient[1].computeLuminance();
      final double textLuminance = theme.heading.computeLuminance();
      expect(
        textLuminance,
        lessThan(skyLuminance),
        reason: '${theme.name} heading must be darker than its sky',
      );
    }
  });
}
