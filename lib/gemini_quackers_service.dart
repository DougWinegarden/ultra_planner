import 'package:cloud_functions/cloud_functions.dart';

class QuackersChatMessage {
  const QuackersChatMessage({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}

/// Talks to Quackers through the `askQuackers` Cloud Function.
///
/// The Gemini API key is never held here. It lives in Secret Manager and is
/// read only inside the function, so nothing the client can inspect -- the app
/// bundle, Firestore, or the device -- contains a usable credential. The
/// function requires a signed-in caller and rate limits per account, since one
/// key now serves every user.
///
/// See functions/index.js and the deployment steps in SETUP.md.
class GeminiQuackersService {
  GeminiQuackersService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  /// Must match the region the function is deployed to (functions/index.js).
  static const String _region = 'us-central1';
  static const String _callableName = 'askQuackers';

  final FirebaseFunctions? _functions;

  FirebaseFunctions get _client =>
      _functions ?? FirebaseFunctions.instanceFor(region: _region);

  Future<String> respond({
    required String question,
    required String taskContext,
    required List<QuackersChatMessage> conversation,
  }) async {
    try {
      final HttpsCallableResult<dynamic> result = await _client
          .httpsCallable(_callableName)
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
        // These are the codes the function raises for conditions that clear on
        // their own; everything else needs a change, not a retry.
        retryable:
            error.code == 'unavailable' || error.code == 'resource-exhausted',
      );
    }
  }
}

/// A chat failure that already carries a user-facing message.
class QuackersException implements Exception {
  const QuackersException(this.message, {this.retryable = false});

  final String message;
  final bool retryable;

  @override
  String toString() => 'QuackersException: $message';
}
