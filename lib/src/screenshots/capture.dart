import 'dart:convert';
import 'dart:io';

class CaptureManifestEntry {
  CaptureManifestEntry({
    required this.pageName,
    required this.platform,
    required this.locale,
    required this.path,
    required this.capturedAt,
  });

  final String pageName;
  final String platform;
  final String locale;
  final String path;
  final DateTime capturedAt;

  Map<String, dynamic> toJson() => {
        'page_name': pageName,
        'platform': platform,
        'locale': locale,
        'path': path,
        'captured_at': capturedAt.toIso8601String(),
      };
}

class ScreenshotCapture {
  ScreenshotCapture({required this.outputDir});

  final Directory outputDir;

  File _targetFile(String platform, String locale, String pageName) {
    final safeName = pageName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return File('${outputDir.path}/$platform/$locale/$safeName.png');
  }

  Future<CaptureManifestEntry> captureIos({
    required String simulatorUdid,
    required String locale,
    required String pageName,
  }) async {
    final file = _targetFile('ios', locale, pageName);
    file.parent.createSync(recursive: true);
    final result = await Process.run('xcrun', ['simctl', 'io', simulatorUdid, 'screenshot', file.path]);
    if (result.exitCode != 0) {
      throw StateError('xcrun simctl screenshot failed: ${result.stderr}');
    }
    return CaptureManifestEntry(
      pageName: pageName,
      platform: 'ios',
      locale: locale,
      path: file.path,
      capturedAt: DateTime.now(),
    );
  }

  Future<CaptureManifestEntry> captureAndroid({
    required String serial,
    required String locale,
    required String pageName,
  }) async {
    final file = _targetFile('android', locale, pageName);
    file.parent.createSync(recursive: true);
    final result = await Process.run('adb', ['-s', serial, 'exec-out', 'screencap', '-p']);
    if (result.exitCode != 0) {
      throw StateError('adb screencap failed: ${result.stderr}');
    }
    file.writeAsBytesSync(result.stdout as List<int>);
    return CaptureManifestEntry(
      pageName: pageName,
      platform: 'android',
      locale: locale,
      path: file.path,
      capturedAt: DateTime.now(),
    );
  }

  void appendToManifest(CaptureManifestEntry entry) {
    final manifestFile = File('${outputDir.path}/manifest.json');
    List<dynamic> entries = [];
    if (manifestFile.existsSync()) {
      entries = jsonDecode(manifestFile.readAsStringSync()) as List<dynamic>;
    }
    entries.add(entry.toJson());
    manifestFile.createSync(recursive: true);
    manifestFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(entries));
  }

  static Future<List<Map<String, String>>> listIosSimulators() async {
    final result = await Process.run('xcrun', ['simctl', 'list', 'devices', 'booted', '--json']);
    if (result.exitCode != 0) return [];
    final decoded = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final devices = <Map<String, String>>[];
    (decoded['devices'] as Map<String, dynamic>).forEach((runtime, list) {
      for (final device in (list as List<dynamic>)) {
        final d = device as Map<String, dynamic>;
        devices.add({'name': d['name'] as String, 'udid': d['udid'] as String});
      }
    });
    return devices;
  }

  static Future<List<String>> listAndroidDevices() async {
    final result = await Process.run('adb', ['devices']);
    if (result.exitCode != 0) return [];
    final lines = (result.stdout as String).split('\n').skip(1);
    return lines
        .where((l) => l.trim().isNotEmpty && l.contains('\tdevice'))
        .map((l) => l.split('\t').first.trim())
        .toList();
  }
}
