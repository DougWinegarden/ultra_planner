import 'package:cloud_functions/cloud_functions.dart';

class QuackersChatMessage {
  const QuackersChatMessage({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}

/// Talks to Quackers through Cloud Functions.
///
/// The user's Gemini API key is sent once to `saveGeminiKey`, encrypted
/// server-side, and stored as ciphertext. It is never held here, never written
/// to the device, and cannot be read back -- the app can ask *whether* a key is
/// saved and see its last four characters, never the key itself.
///
/// See functions/index.js and Part 5 of SETUP.md.
class GeminiQuackersService {
  GeminiQuackersService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  /// Must match the region the function is deployed to (functions/index.js).
  static const String _region = 'us-central1';
  static const String _ask = 'askQuackers';
  static const String _saveKey = 'saveGeminiKey';
  static const String _status = 'quackersStatus';
  static const String _deleteKey = 'deleteGeminiKey';

  final FirebaseFunctions? _functions;

  FirebaseFunctions get _client =>
      _functions ?? FirebaseFunctions.instanceFor(region: _region);

  /// Whether this account has a key saved, and its last four characters.
  Future<QuackersKeyStatus> keyStatus() async {
    try {
      final HttpsCallableResult<dynamic> result = await _client
          .httpsCallable(_status)
          .call<dynamic>();
      final Object? data = result.data;
      if (data is Map) {
        return QuackersKeyStatus(
          hasKey: data['hasKey'] == true,
          hint: data['hint']?.toString(),
        );
      }
      return const QuackersKeyStatus(hasKey: false);
    } on FirebaseFunctionsException catch (error) {
      throw QuackersException(
        error.message ?? 'Could not check your Quackers setup.',
        retryable: error.code == 'unavailable',
      );
    }
  }

  /// Sends the key to be encrypted and stored. Returns its display hint.
  Future<String?> saveApiKey(String apiKey) async {
    try {
      final HttpsCallableResult<dynamic> result = await _client
          .httpsCallable(_saveKey)
          .call<dynamic>(<String, dynamic>{'apiKey': apiKey});
      final Object? data = result.data;
      return data is Map ? data['hint']?.toString() : null;
    } on FirebaseFunctionsException catch (error) {
      throw QuackersException(
        error.message ?? 'Could not save your API key.',
        retryable: error.code == 'unavailable',
      );
    }
  }

  /// Forgets the stored key for this account.
  Future<void> deleteApiKey() async {
    try {
      await _client.httpsCallable(_deleteKey).call<dynamic>();
    } on FirebaseFunctionsException catch (error) {
      throw QuackersException(
        error.message ?? 'Could not remove your API key.',
      );
    }
  }

  Future<String> respond({
    required String question,
    required String taskContext,
    required List<QuackersChatMessage> conversation,
  }) async {
    try {
      final HttpsCallableResult<dynamic> result = await _client
          .httpsCallable(_ask)
          .call<dynamic>(<String, dynamic>{
            'question': question,
            'taskContext': taskContext,
            'conversation': conversation
                .map(
                  (QuackersChatMessage message) => <String, dynamic>{
                    'text': message.text,
                    'isUser': message.isUser,
                  },
                )
                .toList(),
          });

      final Object? data = result.data;
      final String? text = data is Map
          ? data['text']?.toString()
          : data?.toString();

      if (text == null || text.trim().isEmpty) {
        throw const QuackersException(
          'Quackers did not receive a response. Please try again.',
        );
      }
      return text.trim();
    } on FirebaseFunctionsException catch (error) {
      throw QuackersException(
        error.message ?? 'Quackers could not answer that one.',
        // These clear on their own; everything else needs a change, not a retry.
        retryable:
            error.code == 'unavailable' || error.code == 'resource-exhausted',
        // Both mean the saved key is missing or no longer works, so the UI
        // should send the user back to the setup panel.
        needsApiKey:
            error.code == 'failed-precondition' ||
            error.code == 'permission-denied',
      );
    }
  }
}

/// A chat failure that already carries a user-facing message.
class QuackersException implements Exception {
  const QuackersException(
    this.message, {
    this.retryable = false,
    this.needsApiKey = false,
  });

  final String message;
  final bool retryable;

  /// True when the fix is for the user to (re-)enter their Gemini key.
  final bool needsApiKey;

  @override
  String toString() => 'QuackersException: $message';
}

/// Whether an account has a Gemini key saved, and a safe hint for showing it.
class QuackersKeyStatus {
  const QuackersKeyStatus({required this.hasKey, this.hint});

  final bool hasKey;

  /// Last four characters only, e.g. "...bQ8f". Never the whole key.
  final String? hint;
}
