import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_planner/progress/username_words.dart';

void main() {
  // The server only accepts names from this file. If the app offered a word
  // the server lacks, picking it would fail; this keeps the two identical.
  final Map<String, dynamic> server =
      jsonDecode(File('functions/usernameWords.json').readAsStringSync())
          as Map<String, dynamic>;

  test('the picker offers exactly the server\'s words', () {
    expect(usernameAdjectives, server['adjectives']);
    expect(usernameCreatures, server['creatures']);
    expect(
      blockedUsernameInitials,
      (server['blockedInitials'] as List<dynamic>).toSet(),
    );
  });

  test('initials come from both words', () {
    expect(usernameInitials('Brave', 'Otter'), 'BO');
  });

  test('pairs with blocked initials are never offered', () {
    expect(isAllowedUsername('Swift', 'Seal'), isFalse);
    expect(creaturesFor('Swift'), isNot(contains('Seal')));
    expect(creaturesFor('Fearless'), isNot(contains('Urchin')));

    for (final String adjective in usernameAdjectives) {
      for (final String creature in creaturesFor(adjective)) {
        expect(
          blockedUsernameInitials,
          isNot(contains(usernameInitials(adjective, creature))),
        );
      }
    }
  });

  test('every adjective has creatures to go with it', () {
    for (final String adjective in usernameAdjectives) {
      expect(creaturesFor(adjective), isNotEmpty, reason: adjective);
    }
  });

  test('words outside the lists are not allowed', () {
    expect(isAllowedUsername('brave', 'Otter'), isFalse);
    expect(isAllowedUsername('Brave', 'Otters'), isFalse);
    expect(isAllowedUsername('Brave', 'Otter'), isTrue);
  });
}
