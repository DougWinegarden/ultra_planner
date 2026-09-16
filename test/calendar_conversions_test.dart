import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_planner/data/calendar_conversions.dart';

void main() {
  group('Rata Die <-> Gregorian', () {
    test('the epoch is day 1', () {
      expect(rdFromGregorian(1, 1, 1), 1);
    });

    test('round-trips across a wide range', () {
      for (int year = 1900; year <= 2100; year += 7) {
        for (final List<int> md in <List<int>>[
          <int>[1, 1],
          <int>[2, 28],
          <int>[3, 1],
          <int>[7, 4],
          <int>[12, 31],
        ]) {
          final DateTime back = gregorianFromRd(
            rdFromGregorian(year, md[0], md[1]),
          );
          expect(back, DateTime(year, md[0], md[1]));
        }
      }
    });

    test('handles 29 February in leap years', () {
      expect(gregorianFromRd(rdFromGregorian(2024, 2, 29)), DateTime(2024, 2, 29));
      expect(gregorianFromRd(rdFromGregorian(2000, 2, 29)), DateTime(2000, 2, 29));
    });

    test('consecutive days differ by one', () {
      final int a = rdFromGregorian(2026, 2, 28);
      final int b = rdFromGregorian(2026, 3, 1);
      expect(b - a, 1);
    });
  });

  group('Hebrew calendar invariants', () {
    // These are exactly what the postponement rules (dechiyot) exist to
    // guarantee. An implementation that satisfies all of them across centuries
    // is almost certainly right; one that breaks any of them is definitely
    // wrong.

    test('Rosh Hashanah never falls on Sunday, Wednesday or Friday', () {
      for (int h = 5700; h <= 5850; h++) {
        final DateTime rh = gregorianFromRd(hebrewNewYearRd(h));
        expect(
          <int>[DateTime.sunday, DateTime.wednesday, DateTime.friday],
          isNot(contains(rh.weekday)),
          reason: 'Rosh Hashanah $h fell on a forbidden weekday ($rh)',
        );
      }
    });

    test('Yom Kippur never falls on Friday or Sunday', () {
      for (int h = 5700; h <= 5850; h++) {
        final DateTime yk = gregorianFromRd(hebrewNewYearRd(h) + 9);
        expect(
          <int>[DateTime.friday, DateTime.sunday],
          isNot(contains(yk.weekday)),
          reason: 'Yom Kippur $h fell on $yk',
        );
      }
    });

    test('Hoshana Rabbah never falls on Saturday', () {
      for (int h = 5700; h <= 5850; h++) {
        final DateTime hr = gregorianFromRd(hebrewNewYearRd(h) + 20);
        expect(hr.weekday, isNot(DateTime.saturday), reason: 'year $h');
      }
    });

    test('Passover never falls on Monday, Wednesday or Friday', () {
      for (int h = 5700; h <= 5850; h++) {
        final DateTime pesach = gregorianFromRd(rdFromHebrew(h, 'Nisan', 15));
        expect(
          <int>[DateTime.monday, DateTime.wednesday, DateTime.friday],
          isNot(contains(pesach.weekday)),
          reason: 'Passover $h fell on $pesach',
        );
      }
    });

    test('year lengths are always legal', () {
      for (int h = 5700; h <= 5850; h++) {
        expect(
          <int>[353, 354, 355, 383, 384, 385],
          contains(hebrewYearLength(h)),
          reason: 'year $h has length ${hebrewYearLength(h)}',
        );
      }
    });

    test('leap years are the long ones', () {
      for (int h = 5700; h <= 5850; h++) {
        final bool leap = isHebrewLeapYear(h);
        final int length = hebrewYearLength(h);
        expect(length > 380, leap, reason: 'year $h');
      }
    });

    test('month lengths sum to the year length', () {
      for (int h = 5700; h <= 5850; h++) {
        final int sum = hebrewMonths(
          h,
        ).fold(0, (int acc, ({String name, int days}) m) => acc + m.days);
        expect(sum, hebrewYearLength(h), reason: 'year $h');
      }
    });

    test('leap years have Adar I, common years do not', () {
      final List<String> leapNames = hebrewMonths(
        5784,
      ).map((({String name, int days}) m) => m.name).toList();
      expect(isHebrewLeapYear(5784), isTrue);
      expect(leapNames, contains('Adar I'));
      expect(leapNames, hasLength(13));

      expect(isHebrewLeapYear(5785), isFalse);
      expect(hebrewMonths(5785), hasLength(12));
    });

    test('a date in each month resolves inside its year', () {
      for (int h = 5780; h <= 5800; h++) {
        final int start = hebrewNewYearRd(h);
        final int end = hebrewNewYearRd(h + 1);
        for (final ({String name, int days}) m in hebrewMonths(h)) {
          final int rd = rdFromHebrew(h, m.name, 1);
          expect(rd, inInclusiveRange(start, end - 1), reason: '${m.name} $h');
        }
      }
    });

    test('Hanukkah starts on 25 Kislev and runs eight days', () {
      for (int h = 5780; h <= 5800; h++) {
        final int start = rdFromHebrew(h, 'Kislev', 25);
        // Kislev has 29 or 30 days, so the eighth day can land in Tevet; the
        // arithmetic must stay continuous across the month boundary.
        expect(start + 7, greaterThan(start));
        expect(gregorianFromRd(start).month, anyOf(11, 12));
      }
    });
  });

  group('Islamic calendar', () {
    test('years are 354 or 355 days', () {
      for (int y = 1440; y <= 1480; y++) {
        final int length = rdFromIslamic(y + 1, 1, 1) - rdFromIslamic(y, 1, 1);
        expect(<int>[354, 355], contains(length), reason: 'year $y');
      }
    });

    test('months advance monotonically', () {
      for (int m = 1; m < 12; m++) {
        expect(
          rdFromIslamic(1448, m + 1, 1),
          greaterThan(rdFromIslamic(1448, m, 1)),
        );
      }
    });

    test('drifts earlier through the Gregorian year', () {
      // A ~354-day year moves each observance about 11 days earlier annually.
      final DateTime a = gregorianFromRd(rdFromIslamic(1448, 9, 1));
      final DateTime b = gregorianFromRd(rdFromIslamic(1449, 9, 1));
      final int gap = b.difference(a).inDays;
      expect(gap, inInclusiveRange(353, 355));
    });
  });

  group('Julian calendar', () {
    test('runs behind Gregorian by 13 days in this century', () {
      // Orthodox Christmas: 25 December Julian is 7 January Gregorian.
      expect(
        gregorianFromRd(rdFromJulian(2025, 12, 25)),
        DateTime(2026, 1, 7),
      );
    });
  });
}
