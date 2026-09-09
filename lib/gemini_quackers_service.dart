import 'dart:convert';

import 'package:http/http.dart' as http;

class QuackersChatMessage {
  const QuackersChatMessage({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}

class GeminiQuackersService {
  GeminiQuackersService({http.Client? client})
    : _client = client ?? http.Client();

  static const String _buildTimeApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
  );
  static const String _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent';

  final http.Client _client;
  String? _sessionApiKey;

  bool get isConfigured => activeApiKey.isNotEmpty;

  String get activeApiKey => _sessionApiKey ?? _buildTimeApiKey;

  void setApiKey(String apiKey) {
    _sessionApiKey = apiKey.trim();
  }

  Future<String> respond({
    required String question,
    required String taskContext,
    required List<QuackersChatMessage> conversation,
  }) async {
    if (!isConfigured) {
      throw const QuackersException(
        'Quackers needs a Gemini key before chatting. Run with '
        '--dart-define=GEMINI_API_KEY=your_key.',
      );
    }

    final List<Map<String, dynamic>> contents = <Map<String, dynamic>>[
      ...conversation.map(
        (QuackersChatMessage message) => <String, dynamic>{
          'role': message.isUser ? 'user' : 'model',
          'parts': <Map<String, String>>[
            <String, String>{'text': message.text},
          ],
        },
      ),
      <String, dynamic>{
        'role': 'user',
        'parts': <Map<String, String>>[
          <String, String>{'text': question},
        ],
      },
    ];

    final http.Response response = await _client.post(
      Uri.parse(_endpoint),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'x-goog-api-key': activeApiKey,
      },
      body: jsonEncode(<String, dynamic>{
        'systemInstruction': <String, dynamic>{
          'parts': <Map<String, String>>[
            <String, String>{
              'text':
                  'You are Quackers, a warm, playful capybara in a duck suit. Answer the user’s questions helpfully, '
                  'including general questions, while also being a great task-planning buddy. '
                  'Use only the task context below for claims about the user’s tasks. For task or planning questions, '
                  'give short, practical advice and prioritize one next action when asked. Never pretend to have completed a task. '
                  'Do not refuse a normal, safe question merely because it is unrelated to tasks. '
                  'Keep answers to five short sentences or fewer unless the user asks for more detail. '
                  'Always finish your final sentence; never end mid-sentence.\n\n'
                  'TASK CONTEXT:\n$taskContext',
            },
          ],
        },
        'contents': contents,
        'generationConfig': <String, dynamic>{
          'maxOutputTokens': 2048,
          'thinkingConfig': <String, dynamic>{'thinkingLevel': 'minimal'},
        },
      }),
    );

    final Map<String, dynamic> body =
        jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String message = body['error'] is Map<String, dynamic>
          ? (body['error'] as Map<String, dynamic>)['message']?.toString() ??
                'Gemini could not respond.'
          : 'Gemini could not respond.';
      throw QuackersException(
        message,
        retryable: response.statusCode == 429 || response.statusCode >= 500,
      );
    }

    final List<dynamic>? candidates = body['candidates'] as List<dynamic>?;
    final Map<String, dynamic>? candidate = candidates?.isNotEmpty == true
        ? candidates!.first as Map<String, dynamic>
        : null;
    final Map<String, dynamic>? content =
        candidate?['content'] as Map<String, dynamic>?;
    final List<dynamic>? parts = content?['parts'] as List<dynamic>?;
    final Map<String, dynamic>? firstPart = parts?.isNotEmpty == true
        ? parts!.first as Map<String, dynamic>
        : null;
    final String? text = firstPart?['text']?.toString();
    if (text == null || text.trim().isEmpty) {
      throw const QuackersException(
        'Quackers did not receive a response. Please try again.',
      );
    }
    return text.trim();
  }

  void dispose() => _client.close();
}

class QuackersException implements Exception {
  const QuackersException(this.message, {this.retryable = false});

  final String message;
  final bool retryable;
}
