import 'package:flutter/material.dart';

import '../data/us_holidays.dart';

/// What drifts back and forth across the background.
enum DrifterStyle {
  fish,
  sleigh,
  reaper,
  turkey,
  fireworks,
  heart,
  rainbowPot,
  bunny,
  flower,
  tie,
  star,
  tool,
}

/// Small particles floating in the background behind the drifters.
enum AmbientStyle { bubble, snow, sparkle, petal, leaf, mist }

/// Background, palette and animation for a day.
///
/// The ocean theme is the default; a handful of major holidays replace it while
/// that date is selected. Text colours travel with the theme because several
/// holiday skies are too dark for the app's usual navy type.
@immutable
class HolidayTheme {
  const HolidayTheme({
    required this.name,
    required this.gradient,
    required this.accent,
    required this.onAccent,
    required this.heading,
    required this.subheading,
    required this.drifter,
    required this.drifterColors,
    required this.ambient,
    this.ambientColor = Colors.white,
  });

  /// Shown in the banner when a holiday theme is active.
  final String name;

  /// Three stops, top to bottom.
  final List<Color> gradient;

  /// Drives the floating action button and other filled controls.
  final Color accent;
  final Color onAccent;

  /// Type drawn straight onto the background, where card colours do not apply.
  final Color heading;
  final Color subheading;

  final DrifterStyle drifter;
  final List<Color> drifterColors;
  final AmbientStyle ambient;
  final Color ambientColor;

  bool get isOcean => drifter == DrifterStyle.fish;

  /// The theme for [date], or [ocean] when nothing special falls on it.
  ///
  /// Driven by the selected date rather than the real one, so tapping Halloween
  /// in the calendar previews its theme in September.
  static HolidayTheme forDate(DateTime date) {
    for (final Holiday holiday in UsHolidays.on(date)) {
      final HolidayTheme? theme = _byHolidayName[holiday.name];
      if (theme != null) {
        return theme;
      }
    }
    return ocean;
  }

  // --- Default ---------------------------------------------------------------

  static const HolidayTheme ocean = HolidayTheme(
    name: 'Ocean Lists',
    gradient: <Color>[
      Color(0xFFE8F9FF),
      Color(0xFFBDEBFA),
      Color(0xFF78CFF0),
    ],
    accent: Color(0xFF0077B6),
    onAccent: Colors.white,
    heading: Color(0xFF003B5C),
    subheading: Color(0xFF005F8F),
    drifter: DrifterStyle.fish,
    drifterColors: <Color>[
      Color(0x5574C0FC),
      Color(0x555AABD8),
      Color(0x5564B5F6),
      Color(0x554C9FD2),
    ],
    ambient: AmbientStyle.bubble,
  );

  // --- Holiday themes --------------------------------------------------------

  static const HolidayTheme christmas = HolidayTheme(
    name: 'Merry Christmas',
    gradient: <Color>[
      Color(0xFF0B1E3A),
      Color(0xFF17375E),
      Color(0xFF2B5C86),
    ],
    accent: Color(0xFFC62828),
    onAccent: Colors.white,
    heading: Color(0xFFFFF4D6),
    subheading: Color(0xFFBFD8EE),
    drifter: DrifterStyle.sleigh,
    drifterColors: <Color>[
      Color(0xFFD94F4F),
      Color(0xFF8D5524),
      Color(0xFFFFE08A),
    ],
    ambient: AmbientStyle.snow,
  );

  static const HolidayTheme halloween = HolidayTheme(
    name: 'Happy Halloween',
    gradient: <Color>[
      Color(0xFF1A0E26),
      Color(0xFF3B1E4D),
      Color(0xFF7A3B1F),
    ],
    accent: Color(0xFFEF6C00),
    onAccent: Colors.black,
    heading: Color(0xFFFFB877),
    subheading: Color(0xFFD7A6E8),
    drifter: DrifterStyle.reaper,
    drifterColors: <Color>[
      Color(0xFF12060F),
      Color(0xFF2A1438),
      Color(0xFFBFAF9F),
    ],
    ambient: AmbientStyle.mist,
    ambientColor: Color(0xFFB98CD8),
  );

  static const HolidayTheme thanksgiving = HolidayTheme(
    name: 'Happy Thanksgiving',
    gradient: <Color>[
      Color(0xFFFFF0D6),
      Color(0xFFF6C98A),
      Color(0xFFD98A47),
    ],
    accent: Color(0xFF8C4A1E),
    onAccent: Colors.white,
    heading: Color(0xFF5A2E10),
    subheading: Color(0xFF8C4A1E),
    drifter: DrifterStyle.turkey,
    drifterColors: <Color>[
      Color(0xFF7B4420),
      Color(0xFFB5651D),
      Color(0xFFD64541),
    ],
    ambient: AmbientStyle.leaf,
    ambientColor: Color(0xFFB5651D),
  );

  static const HolidayTheme fireworksNight = HolidayTheme(
    name: 'Happy New Year',
    gradient: <Color>[
      Color(0xFF07091F),
      Color(0xFF1B1F44),
      Color(0xFF33265C),
    ],
    accent: Color(0xFFD4AF37),
    onAccent: Colors.black,
    heading: Color(0xFFFFE9A8),
    subheading: Color(0xFFC9C2F0),
    drifter: DrifterStyle.fireworks,
    drifterColors: <Color>[
      Color(0xFFFFD54F),
      Color(0xFFFF6E9C),
      Color(0xFF7FE7FF),
      Color(0xFFB388FF),
    ],
    ambient: AmbientStyle.sparkle,
    ambientColor: Color(0xFFFFE9A8),
  );

  static const HolidayTheme independenceDay = HolidayTheme(
    name: 'Happy Independence Day',
    gradient: <Color>[
      Color(0xFF0A1A3C),
      Color(0xFF16336B),
      Color(0xFF3E5FA3),
    ],
    accent: Color(0xFFC8102E),
    onAccent: Colors.white,
    heading: Color(0xFFFFFFFF),
    subheading: Color(0xFFBFD0F0),
    drifter: DrifterStyle.fireworks,
    drifterColors: <Color>[
      Color(0xFFFF5A5A),
      Color(0xFFFFFFFF),
      Color(0xFF6FA8FF),
    ],
    ambient: AmbientStyle.sparkle,
  );

  static const HolidayTheme valentines = HolidayTheme(
    name: "Happy Valentine's Day",
    gradient: <Color>[
      Color(0xFFFFF0F5),
      Color(0xFFFFD1E3),
      Color(0xFFF79AC0),
    ],
    accent: Color(0xFFD81B60),
    onAccent: Colors.white,
    heading: Color(0xFF7A1638),
    subheading: Color(0xFFB03060),
    drifter: DrifterStyle.heart,
    drifterColors: <Color>[
      Color(0xFFE8537F),
      Color(0xFFF178A4),
      Color(0xFFC2185B),
    ],
    ambient: AmbientStyle.petal,
    ambientColor: Color(0xFFFFB3CE),
  );

  static const HolidayTheme stPatricks = HolidayTheme(
    name: "Happy St. Patrick's Day",
    gradient: <Color>[
      Color(0xFFEFFBEA),
      Color(0xFFBFE9B5),
      Color(0xFF6BBF73),
    ],
    accent: Color(0xFF1B7A3D),
    onAccent: Colors.white,
    heading: Color(0xFF12482A),
    subheading: Color(0xFF1B7A3D),
    drifter: DrifterStyle.rainbowPot,
    drifterColors: <Color>[
      Color(0xFFFFD54F),
      Color(0xFF2E7D32),
      Color(0xFF6D4C41),
    ],
    ambient: AmbientStyle.sparkle,
    ambientColor: Color(0xFFFFE9A8),
  );

  static const HolidayTheme easter = HolidayTheme(
    name: 'Happy Easter',
    gradient: <Color>[
      Color(0xFFFFFBEA),
      Color(0xFFDDF3D8),
      Color(0xFFBFE3F2),
    ],
    accent: Color(0xFF7E57C2),
    onAccent: Colors.white,
    heading: Color(0xFF4A3B6B),
    subheading: Color(0xFF6D5BA3),
    drifter: DrifterStyle.bunny,
    // Warm mid-tones rather than pastels: a pale bunny on a pale spring sky
    // disappears into it.
    drifterColors: <Color>[
      Color(0xFFFFFFFF),
      Color(0xFFE9A0C0),
      Color(0xFFA98467),
      Color(0xFF8E7CC3),
    ],
    ambient: AmbientStyle.petal,
    ambientColor: Color(0xFFF7C8DD),
  );

  static const HolidayTheme mothersDay = HolidayTheme(
    name: "Happy Mother's Day",
    gradient: <Color>[
      Color(0xFFFFF6FB),
      Color(0xFFF3DCEF),
      Color(0xFFD9B8E0),
    ],
    accent: Color(0xFFAD4A96),
    onAccent: Colors.white,
    heading: Color(0xFF5E2B55),
    subheading: Color(0xFF8E4680),
    drifter: DrifterStyle.flower,
    drifterColors: <Color>[
      Color(0xFFEF7BAE),
      Color(0xFFF6B4D0),
      Color(0xFF7CB342),
    ],
    ambient: AmbientStyle.petal,
    ambientColor: Color(0xFFF6B4D0),
  );

  static const HolidayTheme fathersDay = HolidayTheme(
    name: "Happy Father's Day",
    gradient: <Color>[
      Color(0xFFEFF4F8),
      Color(0xFFC6D6E4),
      Color(0xFF8AA5BF),
    ],
    accent: Color(0xFF37546E),
    onAccent: Colors.white,
    heading: Color(0xFF22384B),
    subheading: Color(0xFF37546E),
    drifter: DrifterStyle.tie,
    drifterColors: <Color>[
      Color(0xFF2E4A63),
      Color(0xFF8C6239),
      Color(0xFFB03A48),
    ],
    ambient: AmbientStyle.sparkle,
    ambientColor: Color(0xFFDCE7F0),
  );

  /// Shared by the patriotic holidays. The solemn ones reuse it with a quieter
  /// palette rather than getting cartoon sprites.
  static const HolidayTheme patriotic = HolidayTheme(
    name: 'Stars and Stripes',
    gradient: <Color>[
      Color(0xFFF4F7FC),
      Color(0xFFC9D8EE),
      Color(0xFF8FA9CE),
    ],
    accent: Color(0xFF1F3C73),
    onAccent: Colors.white,
    heading: Color(0xFF16294F),
    subheading: Color(0xFF1F3C73),
    drifter: DrifterStyle.star,
    drifterColors: <Color>[
      Color(0xFF1F3C73),
      Color(0xFFB3132A),
      Color(0xFFFFFFFF),
    ],
    ambient: AmbientStyle.sparkle,
    ambientColor: Color(0xFFFFFFFF),
  );

  static const HolidayTheme remembrance = HolidayTheme(
    name: 'In Remembrance',
    gradient: <Color>[
      Color(0xFFEDF1F6),
      Color(0xFFBCC8D8),
      Color(0xFF7D8DA3),
    ],
    accent: Color(0xFF3A4A5E),
    onAccent: Colors.white,
    heading: Color(0xFF212C3B),
    subheading: Color(0xFF3A4A5E),
    drifter: DrifterStyle.star,
    drifterColors: <Color>[
      Color(0xFF4A5A70),
      Color(0xFF8A97A8),
      Color(0xFFD8DEE7),
    ],
    ambient: AmbientStyle.sparkle,
    ambientColor: Color(0xFFDDE4EC),
  );

  static const HolidayTheme laborDay = HolidayTheme(
    name: 'Happy Labor Day',
    gradient: <Color>[
      Color(0xFFF6F2E7),
      Color(0xFFD9CDB4),
      Color(0xFFA8926B),
    ],
    accent: Color(0xFF6B4F2A),
    onAccent: Colors.white,
    heading: Color(0xFF3F2E17),
    subheading: Color(0xFF6B4F2A),
    drifter: DrifterStyle.tool,
    drifterColors: <Color>[
      Color(0xFF5A4227),
      Color(0xFF8C6D46),
      Color(0xFFB0752A),
    ],
    ambient: AmbientStyle.sparkle,
    ambientColor: Color(0xFFE6DCC6),
  );

  static const HolidayTheme juneteenth = HolidayTheme(
    name: 'Happy Juneteenth',
    gradient: <Color>[
      Color(0xFFFFF3E6),
      Color(0xFFF2C89B),
      Color(0xFFC2543B),
    ],
    accent: Color(0xFF18795C),
    onAccent: Colors.white,
    heading: Color(0xFF5A2318),
    subheading: Color(0xFF8C3A26),
    drifter: DrifterStyle.star,
    drifterColors: <Color>[
      Color(0xFFC62828),
      Color(0xFF1B1B1B),
      Color(0xFF18795C),
    ],
    ambient: AmbientStyle.sparkle,
    ambientColor: Color(0xFFFFE0B2),
  );

  static const HolidayTheme mlkDay = HolidayTheme(
    name: 'Martin Luther King Jr. Day',
    gradient: <Color>[
      Color(0xFFF3F0F8),
      Color(0xFFCFC4E0),
      Color(0xFF8E7BAE),
    ],
    accent: Color(0xFF4A3A6B),
    onAccent: Colors.white,
    heading: Color(0xFF2C2142),
    subheading: Color(0xFF4A3A6B),
    drifter: DrifterStyle.star,
    drifterColors: <Color>[
      Color(0xFF4A3A6B),
      Color(0xFFC9A227),
      Color(0xFFE8E2F2),
    ],
    ambient: AmbientStyle.sparkle,
    ambientColor: Color(0xFFEBE4F5),
  );

  static const HolidayTheme indigenousPeoples = HolidayTheme(
    name: "Indigenous Peoples' Day",
    gradient: <Color>[
      Color(0xFFFDF2E3),
      Color(0xFFE8BE8E),
      Color(0xFFB5764A),
    ],
    accent: Color(0xFF8A4B2A),
    onAccent: Colors.white,
    heading: Color(0xFF4F2A14),
    subheading: Color(0xFF8A4B2A),
    drifter: DrifterStyle.star,
    drifterColors: <Color>[
      Color(0xFF8A4B2A),
      Color(0xFFD98E4A),
      Color(0xFF3F6B5B),
    ],
    ambient: AmbientStyle.sparkle,
    ambientColor: Color(0xFFF6DCC0),
  );

  /// Only the major holidays get a theme; everything else keeps the ocean.
  static const Map<String, HolidayTheme> _byHolidayName =
      <String, HolidayTheme>{
        "New Year's Day": fireworksNight,
        "New Year's Eve": fireworksNight,
        'Martin Luther King Jr. Day': mlkDay,
        "Presidents' Day": patriotic,
        'Memorial Day': remembrance,
        'Juneteenth': juneteenth,
        'Independence Day': independenceDay,
        'Labor Day': laborDay,
        "Columbus Day / Indigenous Peoples' Day": indigenousPeoples,
        'Veterans Day': patriotic,
        'Thanksgiving': thanksgiving,
        'Halloween': halloween,
        'Christmas Day': christmas,
        'Christmas Eve': christmas,
        "Valentine's Day": valentines,
        "St. Patrick's Day": stPatricks,
        'Easter Sunday': easter,
        "Mother's Day": mothersDay,
        "Father's Day": fathersDay,
      };
}
