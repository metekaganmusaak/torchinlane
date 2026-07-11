import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../project/flutter_project.dart';

class StorePromptGenerationException implements Exception {
  StorePromptGenerationException(this.message);
  final String message;
  @override
  String toString() => 'StorePromptGenerationException: $message';
}

class StorePromptGenerator {
  StorePromptGenerator({http.Client? httpClient, String? apiKey})
      : _client = httpClient ?? http.Client(),
        _apiKey = apiKey ?? Platform.environment['ANTHROPIC_API_KEY'];

  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-opus-4-8';
  static const appStoreMaxScreenshots = 10;
  static const playStoreMaxScreenshots = 8;

  final http.Client _client;
  final String? _apiKey;

  /// Gathers pubspec metadata, README, page/screen file names, and any
  /// captured screenshot manifest into a project summary Claude can reason about.
  String buildProjectSummary(FlutterProject project) {
    final buffer = StringBuffer();

    final pubspec = project.pubspecFile;
    if (pubspec.existsSync()) {
      buffer.writeln('--- pubspec.yaml ---');
      buffer.writeln(pubspec.readAsStringSync());
    }

    final readme = File('${project.root.path}/README.md');
    if (readme.existsSync()) {
      buffer.writeln('--- README.md (first 2000 chars) ---');
      final content = readme.readAsStringSync();
      buffer.writeln(content.substring(0, content.length.clamp(0, 2000)));
    }

    final libDir = Directory('${project.root.path}/lib');
    if (libDir.existsSync()) {
      final pageFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => RegExp(r'(_page|_screen)\.dart$').hasMatch(f.path))
          .map((f) => f.path.split('/lib/').last)
          .toList()
        ..sort();
      buffer.writeln('--- Screens/pages found in lib/ ---');
      buffer.writeln(pageFiles.join('\n'));
    }

    final manifestFile = File('${project.root.path}/screenshots/manifest.json');
    if (manifestFile.existsSync()) {
      buffer.writeln('--- Captured screenshots manifest ---');
      buffer.writeln(manifestFile.readAsStringSync());
    }

    return buffer.toString();
  }

  Future<String> generateMarkdown(String projectSummary) async {
    if (_apiKey == null || _apiKey.isEmpty) {
      throw StorePromptGenerationException(
        'ANTHROPIC_API_KEY is not set. Get a key at https://console.anthropic.com/settings/keys',
      );
    }

    final prompt = '''
You are helping prepare App Store and Google Play marketing screenshots for a Flutter app.

Below is a summary of the project: its pubspec metadata, README, the screen/page files found in lib/, and (if present) a manifest of already-captured raw screenshots.

$projectSummary

Task:
1. Identify the app's most compelling, sellable features from the code/README evidence above.
2. Produce exactly $appStoreMaxScreenshots App Store screenshot scenarios (Apple's max) and exactly $playStoreMaxScreenshots Google Play screenshot scenarios (Play's max), ranked by how well they sell the app.
3. For each scenario give:
   - Which captured screenshot (by page name from the manifest, or the closest matching screen file) should be used as the base image.
   - A short marketing headline/subtitle to overlay on the image.
   - A complete, detailed image-generation prompt that, when given to an AI image tool together with the raw screenshot, would produce a store-ready marketing image (device mockup, background, text placement, style).

Output as clean Markdown with two sections: "## App Store (10)" and "## Google Play (8)", each a numbered list.
''';

    final body = jsonEncode({
      'model': _model,
      'max_tokens': 8192,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
    });

    final response = await _client.post(
      Uri.parse(_endpoint),
      headers: {
        'content-type': 'application/json',
        'x-api-key': _apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      throw StorePromptGenerationException('API error ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final content = decoded['content'] as List<dynamic>;
    final textBlock = content.firstWhere((b) => (b as Map)['type'] == 'text') as Map<String, dynamic>;
    return textBlock['text'] as String;
  }
}
