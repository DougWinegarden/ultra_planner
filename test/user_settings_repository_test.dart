import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_planner/data/user_settings_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late UserSettingsRepository settings;

  setUp(() {
    db = FakeFirebaseFirestore();
    settings = UserSettingsRepository(uid: 'user-a', firestore: db);
  });

  test('returns null before a key is saved', () async {
    expect(await settings.loadGeminiApiKey(), isNull);
  });

  test('round-trips a saved key', () async {
    await settings.saveGeminiApiKey('  AIzaTestKey  ');
    expect(await settings.loadGeminiApiKey(), 'AIzaTestKey');
  });

  test('keys are scoped per user', () async {
    await settings.saveGeminiApiKey('key-for-a');
    final UserSettingsRepository other = UserSettingsRepository(
      uid: 'user-b',
      firestore: db,
    );

    expect(await other.loadGeminiApiKey(), isNull);
    expect(await settings.loadGeminiApiKey(), 'key-for-a');
  });

  test('blank keys read back as null', () async {
    await settings.saveGeminiApiKey('   ');
    expect(await settings.loadGeminiApiKey(), isNull);
  });

  test('clearGeminiApiKey removes the stored value', () async {
    await settings.saveGeminiApiKey('AIzaTestKey');
    await settings.clearGeminiApiKey();
    expect(await settings.loadGeminiApiKey(), isNull);
  });
}
