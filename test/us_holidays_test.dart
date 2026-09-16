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
      // Found rather than hardcoded: the holiday set grows, and a date that is
      // quiet today may not be after the next addition.
      final DateTime ordinary = _firstQuietDay(2026);
      expect(UsHolidays.on(ordinary), isEmpty);
      expect(UsHolidays.primaryOn(ordinary), isNull);
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
      // The 27th is Black Friday in 2026, not Thanksgiving.
      expect(UsHolidays.primaryOn(DateTime(2026, 11, 27))?.name, 'Black Friday');
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

  group('religious and informal additions', () {
    List<Holiday> year(int y) => UsHolidays.forYear(y);
    Holiday? find(int y, String name) {
      final Iterable<Holiday> hits = year(y).where((Holiday h) => h.name == name);
      return hits.isEmpty ? null : hits.first;
    }

    test('April Fools and the other fixed fun days are present', () {
      expect(find(2026, "April Fools' Day")?.date, DateTime(2026, 4, 1));
      expect(find(2026, 'Pi Day')?.date, DateTime(2026, 3, 14));
      expect(find(2026, 'Star Wars Day')?.date, DateTime(2026, 5, 4));
      expect(find(2026, 'Groundhog Day')?.date, DateTime(2026, 2, 2));
    });

    test('Leap Day appears only in leap years', () {
      expect(find(2024, 'Leap Day')?.date, DateTime(2024, 2, 29));
      expect(find(2026, 'Leap Day'), isNull);
    });

    test('every Friday the 13th in a year is found', () {
      for (int y = 2024; y <= 2030; y++) {
        final List<Holiday> found = year(
          y,
        ).where((Holiday h) => h.name == 'Friday the 13th').toList();
        final int actual = List<int>.generate(12, (int i) => i + 1)
            .where((int m) => DateTime(y, m, 13).weekday == DateTime.friday)
            .length;
        expect(found, hasLength(actual), reason: 'year $y');
        for (final Holiday h in found) {
          expect(h.date.weekday, DateTime.friday);
          expect(h.date.day, 13);
        }
      }
    });

    test('Hanukkah lands in November or December every year', () {
      for (int y = 2024; y <= 2035; y++) {
        final Holiday? hanukkah = find(y, 'Hanukkah begins');
        expect(hanukkah, isNotNull, reason: 'year $y');
        expect(hanukkah!.date.month, anyOf(11, 12), reason: 'year $y');
        expect(hanukkah.emoji, '🕎');
      }
    });

    test('the major Jewish holidays appear each year', () {
      for (int y = 2025; y <= 2032; y++) {
        for (final String name in <String>[
          'Rosh Hashanah',
          'Yom Kippur',
          'Passover begins',
          'Purim',
        ]) {
          expect(find(y, name), isNotNull, reason: '$name $y');
        }
      }
    });

    test('Good Friday is two days before Easter', () {
      for (int y = 2024; y <= 2032; y++) {
        expect(
          find(y, 'Good Friday')!.date,
          easterSunday(y).subtract(const Duration(days: 2)),
        );
        expect(find(y, 'Good Friday')!.date.weekday, DateTime.friday);
      }
    });

    test('Ash Wednesday is always a Wednesday', () {
      for (int y = 2024; y <= 2032; y++) {
        expect(find(y, 'Ash Wednesday')!.date.weekday, DateTime.wednesday);
      }
    });

    test('Ramadan and Eid appear and are flagged approximate', () {
      final Holiday? ramadan = find(2027, 'Ramadan begins');
      expect(ramadan, isNotNull);
      expect(ramadan!.isApproximate, isTrue);
      expect(find(2027, 'Eid al-Fitr')?.isApproximate, isTrue);
    });

    test('solemn observances carry the neutral marker, not a festive emoji', () {
      const List<String> solemn = <String>[
        'Yom Kippur',
        'Good Friday',
        'Ash Wednesday',
        'Patriot Day',
        'Memorial Day',
        'Martin Luther King Jr. Day',
        'Ashura',
        'International Holocaust Remembrance Day',
      ];
      for (final Holiday h in year(2026)) {
        if (solemn.contains(h.name)) {
          expect(h.emoji, kNeutralMarker, reason: h.name);
        }
      }
    });

    test('every holiday has an emoji so the calendar always marks the day', () {
      for (int y = 2024; y <= 2032; y++) {
        for (final Holiday h in year(y)) {
          expect(h.emoji, isNotEmpty, reason: '${h.name} $y');
        }
      }
    });

    test('Black Friday follows Thanksgiving', () {
      for (int y = 2024; y <= 2032; y++) {
        expect(
          find(y, 'Black Friday')!.date,
          find(y, 'Thanksgiving')!.date.add(const Duration(days: 1)),
        );
      }
    });

    test('Election Day is the Tuesday after the first Monday in November', () {
      for (int y = 2024; y <= 2032; y++) {
        final DateTime election = find(y, 'Election Day')!.date;
        expect(election.weekday, DateTime.tuesday);
        expect(election.day, inInclusiveRange(2, 8));
      }
    });
  });
}

/// First day of [year] with no observance on it.
DateTime _firstQuietDay(int year) {
  for (int day = 1; day <= 365; day++) {
    final DateTime date = DateTime(year, 1, day);
    if (date.year == year && UsHolidays.on(date).isEmpty) {
      return date;
    }
  }
  throw StateError('no quiet day in $year');
}
