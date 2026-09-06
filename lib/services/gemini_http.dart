import 'dart:convert';

import 'package:http/http.dart' as http;

/// Calls Google Gemini REST API ([Gemini API](https://ai.google.dev/gemini-api/docs)).
/// Single shared entry point — avoids duplicate HTTP logic and duplicate native deps.
Future<String> generateGeminiFlashText({
  required String apiKey,
  required String prompt,
  String model = 'gemini-2.0-flash',
  Duration timeout = const Duration(seconds: 20),
}) async {
  final uri = Uri.https(
    'generativelanguage.googleapis.com',
    'v1beta/models/$model:generateContent',
    {'key': apiKey},
  );
  final body = jsonEncode({
    'contents': [
      {
        'parts': [
          {'text': prompt},
        ],
      },
    ],
    'generationConfig': {'temperature': 0.3, 'maxOutputTokens': 256},
  });

  final response = await http
      .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
      .timeout(timeout);

  if (response.statusCode != 200) {
    throw Exception('Gemini HTTP ${response.statusCode}: ${response.body}');
  }

  final decoded = jsonDecode(response.body) as Map<String, dynamic>;
  return _extractGeminiText(decoded);
}

String _extractGeminiText(Map<String, dynamic> decoded) {
  final candidates = decoded['candidates'];
  if (candidates is! List || candidates.isEmpty) return '';
  final first = candidates.first;
  if (first is! Map) return '';
  final content = first['content'];
  if (content is! Map) return '';
  final parts = content['parts'];
  if (parts is! List) return '';
  final buf = StringBuffer();
  for (final p in parts) {
    if (p is Map && p['text'] is String) buf.write(p['text'] as String);
  }
  return buf.toString();
}
