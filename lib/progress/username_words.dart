/// The words a username is built from: one adjective and one sea creature.
///
/// Names are picked from these lists, never typed, so nothing inappropriate can
/// be entered however it is spelled. This is a copy of
/// functions/usernameWords.json for the picker; the server accepts only names
/// built from that file, and a test fails if the two drift apart.
library;

const List<String> usernameAdjectives = <String>[
  'Amazing',
  'Bold',
  'Brave',
  'Bright',
  'Bubbly',
  'Calm',
  'Cheerful',
  'Clever',
  'Cosmic',
  'Cozy',
  'Curious',
  'Daring',
  'Dazzling',
  'Eager',
  'Epic',
  'Fearless',
  'Friendly',
  'Gentle',
  'Glowing',
  'Golden',
  'Happy',
  'Helpful',
  'Hopeful',
  'Jolly',
  'Joyful',
  'Keen',
  'Kind',
  'Lively',
  'Lucky',
  'Merry',
  'Mighty',
  'Nimble',
  'Noble',
  'Patient',
  'Peaceful',
  'Playful',
  'Proud',
  'Quick',
  'Radiant',
  'Shiny',
  'Sparkly',
  'Speedy',
  'Splendid',
  'Steady',
  'Stellar',
  'Sunny',
  'Swift',
  'Thoughtful',
  'Tidal',
  'Trusty',
  'Valiant',
  'Vivid',
  'Wise',
  'Witty',
  'Zesty',
  'Zippy',
];

const List<String> usernameCreatures = <String>[
  'Albatross',
  'Anchovy',
  'Angelfish',
  'Barracuda',
  'Beluga',
  'Clownfish',
  'Conch',
  'Coral',
  'Crab',
  'Dolphin',
  'Dugong',
  'Eel',
  'Flounder',
  'Gull',
  'Jellyfish',
  'Kelp',
  'Krill',
  'Lobster',
  'Mackerel',
  'Manatee',
  'Manta',
  'Marlin',
  'Minnow',
  'Narwhal',
  'Nautilus',
  'Octopus',
  'Orca',
  'Otter',
  'Oyster',
  'Pelican',
  'Penguin',
  'Plankton',
  'Puffin',
  'Salmon',
  'Sardine',
  'Seahorse',
  'Seal',
  'Snapper',
  'Squid',
  'Starfish',
  'Stingray',
  'Sunfish',
  'Swordfish',
  'Tarpon',
  'Tuna',
  'Turtle',
  'Urchin',
  'Walrus',
  'Whale',
];

/// Pairs whose avatar initials read badly ("Swift Seal" -> SS) are left out.
const Set<String> blockedUsernameInitials = <String>{
  'AF',
  'AH',
  'AS',
  'BJ',
  'BS',
  'CP',
  'DP',
  'FK',
  'FU',
  'HH',
  'HJ',
  'HO',
  'KK',
  'KY',
  'MF',
  'NS',
  'PP',
  'SS',
  'VD',
  'WP',
};

/// "BO" for Brave Otter.
String usernameInitials(String adjective, String creature) =>
    '${adjective[0]}${creature[0]}'.toUpperCase();

/// Whether the server will accept this pair.
bool isAllowedUsername(String adjective, String creature) =>
    usernameAdjectives.contains(adjective) &&
    usernameCreatures.contains(creature) &&
    !blockedUsernameInitials.contains(usernameInitials(adjective, creature));

/// The creatures that can go with [adjective].
List<String> creaturesFor(String adjective) => <String>[
  for (final String creature in usernameCreatures)
    if (isAllowedUsername(adjective, creature)) creature,
];
