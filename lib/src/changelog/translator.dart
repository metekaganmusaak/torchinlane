import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ChangelogTranslationException implements Exception {
  ChangelogTranslationException(this.message);
  final String message;
  @override
  String toString() => 'ChangelogTranslationException: $message';
}

/// Translates a source changelog string into multiple target locales using
/// the Claude Messages API. One request per batch of locales (default: all
/// at once, falling back to groups of 8 on failure).
class ChangelogTranslator {
  ChangelogTranslator({http.Client? httpClient, String? apiKey})
      : _client = httpClient ?? http.Client(),
        _apiKey = apiKey ?? Platform.environment['ANTHROPIC_API_KEY'];

  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-opus-4-8';

  final http.Client _client;
  final String? _apiKey;

  Future<Map<String, String>> translate({
    required String sourceText,
    required String sourceLocale,
    required List<String> targetLocales,
  }) async {
    if (_apiKey == null || _apiKey.isEmpty) {
      throw ChangelogTranslationException(
        'ANTHROPIC_API_KEY is not set. Get a key at https://console.anthropic.com/settings/keys',
      );
    }

    final results = <String, String>{};
    const batchSize = 8;
    for (var i = 0; i < targetLocales.length; i += batchSize) {
      final batch = targetLocales.sublist(i, (i + batchSize).clamp(0, targetLocales.length));
      final translated = await _translateBatch(
        sourceText: sourceText,
        sourceLocale: sourceLocale,
        targetLocales: batch,
      );
      results.addAll(translated);
    }
    return results;
  }

  Future<Map<String, String>> _translateBatch({
    required String sourceText,
    required String sourceLocale,
    required List<String> targetLocales,
  }) async {
    final schema = {
      'type': 'object',
      'properties': {
        for (final locale in targetLocales) locale: {'type': 'string'},
      },
      'required': targetLocales,
      'additionalProperties': false,
    };

    final prompt = '''
Translate the following app store changelog / release notes from "$sourceLocale" into these locale codes: ${targetLocales.join(', ')}.

Rules:
- Keep the tone and length similar to the source.
- Keep the result under 500 characters per locale (Google Play limit) and well under 4000 (App Store limit).
- Do not add commentary, only the translated text per locale.
- Preserve any emoji or formatting present in the source.

Source text:
"""
$sourceText
"""
''';

    final body = jsonEncode({
      'model': _model,
      'max_tokens': 4096,
      'output_config': {
        'format': {'type': 'json_schema', 'schema': schema},
      },
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
    });

    final response = await _client.post(
      Uri.parse(_endpoint),
      headers: {
        'content-type': 'application/json',
        'x-api-key': _apiKey!,
        'anthropic-version': '2023-06-01',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      throw ChangelogTranslationException('API error ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final content = decoded['content'] as List<dynamic>;
    final textBlock = content.firstWhere((b) => (b as Map)['type'] == 'text') as Map<String, dynamic>;
    final parsed = jsonDecode(textBlock['text'] as String) as Map<String, dynamic>;

    return parsed.map((key, value) => MapEntry(key, value as String));
  }
}
