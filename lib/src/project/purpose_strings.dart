import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Classes whose use, even only by a dependency, makes App Store Connect
/// reject the build without the matching Info.plist purpose string
/// (ITMS-90683) after the upload has already used up the build number.
const purposeStringClasses = {
  'AVCaptureDevice': 'NSCameraUsageDescription',
  'CBCentralManager': 'NSBluetoothAlwaysUsageDescription',
  'CLLocationManager': 'NSLocationWhenInUseUsageDescription',
  'CMMotionActivityManager': 'NSMotionUsageDescription',
  'CNContactStore': 'NSContactsUsageDescription',
  'EKEventStore': 'NSCalendarsUsageDescription',
  'HKHealthStore': 'NSHealthShareUsageDescription',
  'MPMediaLibrary': 'NSAppleMusicUsageDescription',
  'PHPhotoLibrary': 'NSPhotoLibraryUsageDescription',
  'SFSpeechRecognizer': 'NSSpeechRecognitionUsageDescription',
};

/// Purpose strings a built `.app` lacks, checked on the app binary and every
/// embedded framework. Empty when the bundle cannot be read.
List<String> missingPurposeStrings(Directory app) {
  final plist = Process.runSync('plutil',
      ['-convert', 'json', '-o', '-', p.join(app.path, 'Info.plist')]);
  if (plist.exitCode != 0) return [];
  final info = jsonDecode(plist.stdout as String) as Map<String, dynamic>;
  final executable = info['CFBundleExecutable'] as String? ??
      p.basenameWithoutExtension(app.path);
  final frameworks = Directory(p.join(app.path, 'Frameworks'));
  final binaries = [
    File(p.join(app.path, executable)),
    if (frameworks.existsSync())
      for (final framework in frameworks.listSync().whereType<Directory>())
        File(p.join(framework.path, p.basenameWithoutExtension(framework.path)))
  ].where((f) => f.existsSync());
  final problems = <String>[];
  for (final binary in binaries) {
    final nm = Process.runSync('xcrun', ['nm', '-u', binary.path]);
    if (nm.exitCode != 0) continue;
    final symbols = nm.stdout as String;
    for (final e in purposeStringClasses.entries) {
      if (info.containsKey(e.value) ||
          !RegExp('_OBJC_CLASS_\\\$_${e.key}\$', multiLine: true)
              .hasMatch(symbols)) {
        continue;
      }
      problems.add('${p.basename(binary.path)} uses ${e.key}: add ${e.value} '
          'to ios/Runner/Info.plist or drop the code that uses it');
    }
  }
  return problems;
}
