import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_planner/data/us_holidays.dart';

void main() {
  group('Easter', () {
    test('matches known dates across years', () {
      // Verified against published dates; the computus is easy to get subtly
      // wrong, so this pins several years including a century boundary.
      expect(easterSunday(2024), DateTime(2024, 3, 31));
      expect(easterSunday(2025), DateTime(2025, 4, 20));
      expect(easterSunday(2026), DateTime(2026, 4, 5));
      expect(easterSunday(2027), DateTime(2027, 3, 28));
      expect(easterSunday(2030), DateTime(2030, 4, 21));
      expect(easterSunday(2000), DateTime(2000, 4, 23));
    });

    test('always lands on a Sunday', () {
      for (int year = 2020; year <= 2040; year++) {
        expect(
          easterSunday(year).weekday,
          DateTime.sunday,
          reason: 'Easter $year',
        );
      }
    });

    test('always falls between 22 March and 25 April', () {
      for (int year = 1900; year <= 2100; year++) {
        final DateTime easter = easterSunday(year);
        expect(
          easter.isAfter(DateTime(year, 3, 21)) &&
              easter.isBefore(DateTime(year, 4, 26)),
          isTrue,
          reason: 'Easter $year was $easter',
        );
      }
    });
  });

  group('ordinal weekday holidays', () {
    DateTime dateOf(int year, String name) {
      return UsHolidays.forYear(
        year,
      ).firstWhere((Holiday h) => h.name == name).date;
    }

    test('Thanksgiving is the 4th Thursday of November', () {
      expect(dateOf(2026, 'Thanksgiving'), DateTime(2026, 11, 26));
      expect(dateOf(2025, 'Thanksgiving'), DateTime(2025, 11, 27));
      expect(dateOf(2024, 'Thanksgiving'), DateTime(2024, 11, 28));
    });

    test('Memorial Day is the last Monday of May', () {
      expect(dateOf(2026, 'Memorial Day'), DateTime(2026, 5, 25));
      expect(dateOf(2025, 'Memorial Day'), DateTime(2025, 5, 26));
      // 2027's May has five Mondays -- the "last", not the fourth.
      expect(dateOf(2027, 'Memorial Day'), DateTime(2027, 5, 31));
    });

    test('MLK Day is the 3rd Monday of January', () {
      expect(dateOf(2026, 'Martin Luther King Jr. Day'), DateTime(2026, 1, 19));
      expect(dateOf(2025, 'Martin Luther King Jr. Day'), DateTime(2025, 1, 20));
    });

    test('Labor Day is the 1st Monday of September', () {
      expect(dateOf(2026, 'Labor Day'), DateTime(2026, 9, 7));
      expect(dateOf(2025, 'Labor Day'), DateTime(2025, 9, 1));
    });

    test("Mother's Day and Father's Day are the right Sundays", () {
      expect(dateOf(2026, "Mother's Day"), DateTime(2026, 5, 10));
      expect(dateOf(2026, "Father's Day"), DateTime(2026, 6, 21));
    });

    test('every ordinal holiday lands on its intended weekday', () {
      const Map<String, int> expected = <String, int>{
        'Martin Luther King Jr. Day': DateTime.monday,
        "Presidents' Day": DateTime.monday,
        'Memorial Day': DateTime.monday,
        'Labor Day': DateTime.monday,
        "Columbus Day / Indigenous Peoples' Day": DateTime.monday,
        'Thanksgiving': DateTime.thursday,
        "Mother's Day": DateTime.sunday,
        "Father's Day": DateTime.sunday,
      };

      for (int year = 2024; year <= 2035; year++) {
        for (final Holiday holiday in UsHolidays.forYear(year)) {
          final int? want = expected[holiday.name];
          if (want != null) {
            expect(
              holiday.date.weekday,
              want,
              reason: '${holiday.name} $year',
            );
          }
        }
      }
    });
  });

  group('fixed holidays', () {
    test('land on their calendar dates', () {
      final List<Holiday> y = UsHolidays.forYear(2026);
      DateTime dateOf(String name) =>
          y.firstWhere((Holiday h) => h.name == name).date;

      expect(dateOf('Christmas Day'), DateTime(2026, 12, 25));
      expect(dateOf('Halloween'), DateTime(2026, 10, 31));
      expect(dateOf('Independence Day'), DateTime(2026, 7, 4));
      expect(dateOf('Juneteenth'), DateTime(2026, 6, 19));
      expect(dateOf('Veterans Day'), DateTime(2026, 11, 11));
      expect(dateOf("New Year's Day"), DateTime(2026, 1, 1));
    });
  });

  group('lookup', () {
    test('finds a holiday on its date', () {
      final Holiday? christmas = UsHolidays.primaryOn(DateTime(2026, 12, 25));
      expect(christmas?.name, 'Christmas Day');
      expect(christmas?.emoji, '🎄');
      expect(christmas?.label, '🎄 Christmas Day');
    });

    test('returns nothing on an ordinary day', () {
      expect(UsHolidays.on(DateTime(2026, 3, 4)), isEmpty);
      expect(UsHolidays.primaryOn(DateTime(2026, 3, 4)), isNull);
    });

    test('ignores the time component', () {
      // Calendar cells build dates at midnight, but "today" carries a clock
      // time; both must match the same holiday.
      expect(
        UsHolidays.primaryOn(DateTime(2026, 10, 31, 16, 45))?.name,
        'Halloween',
      );
    });

    test('handles two holidays sharing one day, federal first', () {
      // Father's Day fell on Juneteenth in 2022.
      final List<Holiday> both = UsHolidays.on(DateTime(2022, 6, 19));
      expect(both, hasLength(2));
      expect(both.first.name, 'Juneteenth');
      expect(both.first.isFederal, isTrue);
      expect(both.last.name, "Father's Day");
    });

    test('works across years without cache bleed', () {
      expect(UsHolidays.primaryOn(DateTime(2025, 11, 27))?.name, 'Thanksgiving');
      expect(UsHolidays.primaryOn(DateTime(2026, 11, 26))?.name, 'Thanksgiving');
      expect(UsHolidays.on(DateTime(2026, 11, 27)), isEmpty);
    });
  });

  test('all eleven federal holidays are present', () {
    final List<Holiday> federal = UsHolidays.forYear(
      2026,
    ).where((Holiday h) => h.isFederal).toList();
    expect(federal, hasLength(11));
  });

  test('holidays come back in date order', () {
    final List<Holiday> all = UsHolidays.forYear(2026);
    for (int i = 1; i < all.length; i++) {
      expect(
        all[i].date.isBefore(all[i - 1].date),
        isFalse,
        reason: '${all[i].name} out of order',
      );
    }
  });
}
