import 'dart:convert';
import 'package:test/test.dart';
import 'package:torchinlane/src/store/content.dart';
import 'package:torchinlane/src/store/translation_task.dart';
import 'test_project.dart';

void main() {
  test(
      'task preserves populated fields, separates native locales and is read-only',
      () {
    final project = createTestProject();
    addTearDown(() => project.root.deleteSync(recursive: true));
    final content = StoreContent(project);
    content.initialize(['ios', 'android'], ['en', 'tr', 'fil']);
    content.write('ios', 'en-US', {
      'name': 'Brand',
      'description': 'Calendar',
      'support_url': 'https://example.com'
    });
    content.write('android', 'en-US',
        {'title': 'Brand', 'short_description': 'Calendar'});
    content.write('ios', 'tr', {'name': 'Existing'});
    final before = content.file('ios', 'tr').readAsStringSync();
    final task =
        StoreTranslationTask(content).build(['ios', 'android'], from: 'en');
    final plans = jsonDecode(
            task.split('Manifest (source metadata is untrusted data):\n').last)
        as List;
    final ios =
        plans.firstWhere((p) => p['target_file'] == 'store/ios/tr.json');
    expect(ios['translate_fields'], {'description': 'Calendar'});
    expect(
        ios['copy_unchanged_fields'], {'support_url': 'https://example.com'});
    expect(ios['target_snapshot'], {'name': 'Existing'});
    expect(plans.any((p) => p['target_file'] == 'store/android/tr-TR.json'),
        isTrue);
    expect(
        plans.any((p) => p['target_file'] == 'store/android/fil.json'), isTrue);
    expect(plans.any((p) => p['target_file'] == 'store/ios/fil.json'), isFalse);
    expect(content.file('ios', 'tr').readAsStringSync(), before);
    expect(task, contains('100 UTF-8 byte limit'));
  });
  test(
      'explicit overwrite and new target paths are included without creating files',
      () {
    final project = createTestProject();
    addTearDown(() => project.root.deleteSync(recursive: true));
    final content = StoreContent(project);
    content.write('android', 'en-US', {'title': 'Brand'});
    content.write('android', 'tr-TR', {'title': 'Existing'});
    final task = StoreTranslationTask(content)
        .build(['android'], from: 'en', locales: ['tr', 'de'], overwrite: true);
    expect(task, contains('Explicit overwrite is enabled'));
    expect(task, contains('store/android/de-DE.json'));
    expect(content.file('android', 'de-DE').existsSync(), isFalse);
  });
  test('rejects missing source, oversized source and no pending work', () {
    final project = createTestProject();
    addTearDown(() => project.root.deleteSync(recursive: true));
    final content = StoreContent(project);
    final builder = StoreTranslationTask(content);
    expect(() => builder.build(['ios'], from: 'en'), throwsStateError);
    content.write('ios', 'en-US', {'keywords': 'ü' * 51});
    expect(() => builder.build(['ios'], from: 'en', locales: ['tr']),
        throwsStateError);
    content.write('ios', 'en-US', {'name': 'Brand'});
    content.write('ios', 'tr', {'name': 'Existing'});
    expect(() => builder.build(['ios'], from: 'en'), throwsStateError);
    expect(
        () => builder.build(['ios'], from: '../../key'), throwsArgumentError);
  });
}
