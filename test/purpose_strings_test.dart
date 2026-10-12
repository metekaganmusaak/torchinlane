import 'dart:io';

import 'package:test/test.dart';
import 'package:torchinlane/src/project/purpose_strings.dart';

void main() {
  test('flags a framework that uses Photos without a purpose string', () {
    final root = Directory.systemTemp.createTempSync('torchinlane-purpose-');
    addTearDown(() => root.deleteSync(recursive: true));
    final app = Directory('${root.path}/Runner.app')..createSync();
    final framework = Directory('${app.path}/Frameworks/Picker.framework')
      ..createSync(recursive: true);
    final source = File('${root.path}/picker.m')
      ..writeAsStringSync(
          '#import <Photos/Photos.h>\nint main(void) { return [PHPhotoLibrary class] != nil; }\n');
    final build = Process.runSync('xcrun', [
      'clang',
      '-x',
      'objective-c',
      '-framework',
      'Foundation',
      '-framework',
      'Photos',
      '-o',
      '${framework.path}/Picker',
      source.path
    ]);
    expect(build.exitCode, 0, reason: build.stderr.toString());
    void plist(String extra) => File('${app.path}/Info.plist').writeAsStringSync(
        '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>'
        '<key>CFBundleExecutable</key><string>Runner</string>$extra</dict></plist>');

    plist('');
    expect(missingPurposeStrings(app), [
      'Picker uses PHPhotoLibrary: add NSPhotoLibraryUsageDescription to ios/Runner/Info.plist or drop the code that uses it'
    ]);
    plist('<key>NSPhotoLibraryUsageDescription</key><string>Pick photos</string>');
    expect(missingPurposeStrings(app), isEmpty);
  }, skip: Platform.isMacOS ? false : 'Requires Xcode command line tools');
}
