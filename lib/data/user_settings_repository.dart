import 'package:cloud_firestore/cloud_firestore.dart';

/// Per-user settings that follow the account across devices.
///
/// Stored at `users/{uid}/private/settings`. The `private` subcollection is
/// locked in firestore.rules so a document is readable and writable only by the
/// account that owns it.
///
/// SECURITY NOTE: this keeps the Gemini key out of the app bundle and off other
/// people's devices, but it is still stored in plaintext in Firestore and is
/// visible to anyone with owner access to the Firebase console. It also still
/// reaches the device at runtime, so a determined user can read their own key
/// out of the app. The only way to prevent a client from ever holding the key is
/// to proxy Gemini through a Cloud Function and never send the key down at all.
class UserSettingsRepository {
  UserSettingsRepository({required this.uid, FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> get _settings =>
      _db.collection('users').doc(uid).collection('private').doc('settings');

  /// Returns the saved key, or null if this account has not set one up yet.
  Future<String?> loadGeminiApiKey() async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await _settings
        .get();
    final String? key = snapshot.data()?['geminiApiKey'] as String?;
    if (key == null || key.trim().isEmpty) {
      return null;
    }
    return key.trim();
  }

  Future<void> saveGeminiApiKey(String apiKey) {
    return _settings.set(<String, dynamic>{
      'geminiApiKey': apiKey.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Clears the stored key so the assistant falls back to its setup screen.
  Future<void> clearGeminiApiKey() {
    return _settings.set(<String, dynamic>{
      'geminiApiKey': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
