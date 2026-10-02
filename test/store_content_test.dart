import 'dart:io';
import 'package:test/test.dart';
import 'package:image/image.dart' as img;
import 'package:torchinlane/src/project/flutter_project.dart';
import 'package:torchinlane/src/store/content.dart';
import 'package:torchinlane/src/store/service.dart';
import 'test_project.dart';

void main() {
  late FlutterProject project;
  late StoreContent content;
  setUp(() {
    project = createTestProject();
    content = StoreContent(project);
  });
  tearDown(() => project.root.deleteSync(recursive: true));
  test(
      'initialization separates native store locales and preserves authored text',
      () {
    content.initialize(['ios', 'android'], ['en', 'tr', 'fa', 'tl', 'pt-PT']);
    expect(content.locales('ios'), containsAll(['en-US', 'tr', 'pt-PT']));
    expect(content.locales('ios'), isNot(contains('fil')));
    expect(content.locales('android'),
        containsAll(['en-US', 'tr-TR', 'fil', 'fa']));
    content.write('ios', 'tr', {'name': 'Uygulama'});
    content.initialize(['ios'], ['tr']);
    expect(content.read('ios', 'tr')['name'], 'Uygulama');
  });
  test(
      'over-limit fields fail rather than silently truncate; Unicode counts code points',
      () {
    content.write('android', 'en-US', {'release_notes': '🔥' * 500});
    expect(content.validate(['android']), isEmpty);
    content.write('android', 'en-US', {'release_notes': '🔥' * 501});
    expect(content.validate(['android']).single, contains('501/500'));
    expect(
        () => content
            .exportTo(Directory('${project.root.path}/output'), ['android']),
        throwsStateError);
  });
  test('Apple keywords enforce UTF-8 byte limits', () {
    content.write('ios', 'en-US', {'keywords': 'ş' * 60});
    expect(content.validate(['ios']).single, contains('120/100 UTF-8 bytes'));
  });
  test('export skips blanks and separates notes from listing text', () {
    content.write('android', 'en-US', {
      'title': 'New app',
      'full_description': '',
      'release_notes': 'Fixed a bug.'
    });
    final out = Directory('${project.root.path}/export');
    content.exportTo(out, ['android'], versionCode: '42');
    expect(
        File('${out.path}/android/metadata/en-US/title.txt').readAsStringSync(),
        'New app');
    expect(
        File('${out.path}/android/metadata/en-US/full_description.txt')
            .existsSync(),
        isFalse);
    expect(
        File('${out.path}/android/metadata/en-US/changelogs/42.txt')
            .readAsStringSync(),
        'Fixed a bug.');
  });
  test('scoped uploads validate/export only selected content', () {
    content.write(
        'android', 'en-US', {'title': 'x' * 40, 'release_notes': 'Short note'});
    expect(content.validate(['android'], scope: 'notes'), isEmpty);
    final out = Directory('${project.root.path}/notes');
    content.exportTo(out, ['android'], scope: 'notes', versionCode: '42');
    expect(File('${out.path}/android/metadata/en-US/title.txt').existsSync(),
        isFalse);
  });
  test(
      'image validation rejects wrong dimensions/transparency and preserves upload order',
      () {
    final dir = content.images('android', 'en-US', 'featureGraphic')
      ..createSync(recursive: true);
    final wrong = File('${dir.path}/wrong.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 512, height: 512)));
    expect(content.validate(['android']).single, contains('1024x500'));
    wrong.deleteSync();
    final valid = img.Image(width: 1024, height: 500);
    File('${dir.path}/01.png').writeAsBytesSync(img.encodePng(valid));
    expect(content.validate(['android']), isEmpty);
    final out = Directory('${project.root.path}/images');
    content.exportTo(out, ['android'], scope: 'images');
    expect(
        File('${out.path}/android/metadata/en-US/images/featureGraphic.png')
            .existsSync(),
        isTrue);
    final transparent = img.Image(width: 1024, height: 500, numChannels: 4);
    expect(
        StoreContent.validateImage(
            File('${dir.path}/alpha.png')
              ..writeAsBytesSync(img.encodePng(transparent)),
            'android',
            'featureGraphic'),
        contains('transparent'));
  });
  test(
      'explicit skip notes ignores over-limit notes while exporting other content',
      () {
    content.write(
        'android', 'en-US', {'title': 'App', 'release_notes': 'x' * 501});
    expect(content.validate(['android'], skipNotes: true), isEmpty);
    final out = Directory('${project.root.path}/skipped-notes');
    content.exportTo(out, ['android'], skipNotes: true);
    expect(File('${out.path}/android/metadata/en-US/title.txt').existsSync(),
        isTrue);
    expect(
        File('${out.path}/android/metadata/en-US/changelogs/default.txt')
            .existsSync(),
        isFalse);
  });
  test('path traversal and symlink assets cannot access credentials', () {
    expect(() => content.safeAsset('../torchinlane.yaml'), throwsArgumentError);
    expect(() => content.file('ios', '../../key'), throwsArgumentError);
    final dir = content.images('android', 'en-US', 'phoneScreenshots')
      ..createSync(recursive: true);
    if (!Platform.isWindows) {
      Link('${dir.path}/secret.png')
          .createSync(project.torchinlaneConfigFile.path);
      expect(
          () => content
              .safeAsset('android/images/en-US/phoneScreenshots/secret.png'),
          throwsArgumentError);
    }
  });
  test(
      'dry-run validates without spawning Fastlane; Google notes need explicit version',
      () async {
    content.write('android', 'en-US', {'release_notes': 'Fixes'});
    final logs = <String>[];
    final service = StoreService(project, log: logs.add);
    await expectLater(
        service.push(['android'], dryRun: true), throwsArgumentError);
    expect(await service.push(['android'], dryRun: true, versionCode: '42'), 0);
    expect(logs.last, contains('no store request'));
  });
}
