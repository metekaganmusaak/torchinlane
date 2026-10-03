import 'dart:convert';
import 'package:test/test.dart';
import 'package:torchinlane/src/studio/localization.dart';
import 'package:torchinlane/src/studio/ui.dart';

void main() {
  test(
      'embedded English catalog covers Turkish static text and runtime messages',
      () {
    final json = RegExp(r'const uiMessages = (\{[\s\S]*?\n\});')
        .firstMatch(studioLocalizationScript)!
        .group(1)!;
    final messages = Map<String, String>.from(jsonDecode(json) as Map);
    expect(messages.length, greaterThan(250));
    expect(messages.values.every((text) => text.trim().isNotEmpty), isTrue);
    expect(messages['Proje ayarları ve yardımcı dosyalar'],
        'Project settings and helper files');
    expect(messages['Kaydedilen içerik kontrol edildi; sorun bulunmadı.'],
        contains('no issues'));
    final html = studioHtml.split('<script>').first;
    for (final match in RegExp(r'>([^<>]+)<').allMatches(html)) {
      final text = match.group(1)!.trim();
      if (!text.contains(RegExp(r'[çğıöşüÇĞİÖŞÜ]')) ||
          text.contains('{') ||
          text.contains('signing --help')) {
        continue;
      }
      expect(messages.containsKey(text), isTrue,
          reason: 'Missing English UI text: $text');
    }
    expect(studioHtml, contains('id="uiLanguage"'));
  });
}
