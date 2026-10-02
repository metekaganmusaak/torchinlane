import 'dart:io';
import 'package:path/path.dart' as p;
import '../project/flutter_project.dart';

/// Integrates the stock Flutter Gradle debug-signing placeholder. Existing
/// custom release signing is preserved and must be managed by its owner.
String configureAndroidGradle(String source, {required bool kotlin}) {
  if (source.contains('key.properties') &&
      source.contains('keystoreProperties') &&
      source.contains('signingConfigs') &&
      source.contains('release')) {
    return source;
  }
  if (RegExp(r'signingConfigs\s*\{').hasMatch(source)) {
    throw StateError(
        'Custom signingConfigs already exists. Wire android/key.properties into that configuration (doc/automation.md).');
  }
  final debug = kotlin
      ? 'signingConfig = signingConfigs.getByName("debug")'
      : 'signingConfig = signingConfigs.debug';
  final alternative = 'signingConfig signingConfigs.debug';
  if (!source.contains(debug) && !(!kotlin && source.contains(alternative))) {
    throw StateError(
        'Stock Flutter debug signing placeholder not found. Preserve your custom signing and integrate key.properties manually.');
  }
  final android = RegExp(r'android\s*\{').firstMatch(source);
  if (android == null) throw StateError('android block not found');
  final properties = kotlin
      ? r'''
val keystoreProperties = java.util.Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

'''
      : r'''
def keystoreProperties = new java.util.Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.withInputStream { keystoreProperties.load(it) }
}

''';
  final signing = kotlin
      ? r'''
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }
'''
      : r'''
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }
''';
  var result =
      '${source.substring(0, android.start)}$properties${source.substring(android.start, android.end)}$signing${source.substring(android.end)}';
  result = result.replaceAll(
      debug,
      kotlin
          ? 'signingConfig = signingConfigs.getByName("release")'
          : 'signingConfig = signingConfigs.release');
  if (!kotlin) {
    result =
        result.replaceAll(alternative, 'signingConfig signingConfigs.release');
  }
  return result;
}

void setupAndroidSigning(FlutterProject project,
    {required File keystore,
    required String alias,
    required String storePassword,
    required String keyPassword,
    bool dryRun = false}) {
  if (!keystore.existsSync() || keystore.lengthSync() == 0) {
    throw ArgumentError('Keystore file is missing/empty');
  }
  if (alias.isEmpty || storePassword.isEmpty || keyPassword.isEmpty) {
    throw ArgumentError(
        'Alias and password environment variables are required');
  }
  final kotlinFile = File('${project.root.path}/android/app/build.gradle.kts');
  final gradle = kotlinFile.existsSync()
      ? kotlinFile
      : File('${project.root.path}/android/app/build.gradle');
  if (!gradle.existsSync()) {
    throw StateError('Android app Gradle file not found');
  }
  final original = gradle.readAsStringSync();
  final updated =
      configureAndroidGradle(original, kotlin: kotlinFile.existsSync());
  if (dryRun) return;
  final target = File('${project.root.path}/.torchinlane/upload-keystore.jks');
  target.parent.createSync(recursive: true);
  if (target.existsSync() &&
      p.canonicalize(keystore.path) != p.canonicalize(target.path)) {
    if (sameKeystore(target, keystore) == false) {
      throw StateError(
          'An upload keystore is already configured; use the same signing identity');
    }
  }
  if (p.canonicalize(keystore.path) != p.canonicalize(target.path)) {
    keystore.copySync(target.path);
  }
  String escape(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('=', r'\=')
      .replaceAll(':', r'\:');
  final properties = File('${project.root.path}/android/key.properties');
  properties.writeAsStringSync('${{
    'storePassword': storePassword,
    'keyPassword': keyPassword,
    'keyAlias': alias,
    'storeFile': target.absolute.path
  }.entries.map((e) => '${e.key}=${escape(e.value)}').join('\n')}\n');
  if (!Platform.isWindows) {
    Process.runSync('chmod', ['600', target.path, properties.path]);
  }
  if (updated != original) {
    gradle.copySync('${gradle.path}.bak');
    gradle.writeAsStringSync(updated);
  }
  final ignore = File('${project.root.path}/.gitignore');
  final existing = ignore.existsSync() ? ignore.readAsStringSync() : '';
  final entries = [
    '.torchinlane/',
    'android/key.properties',
    '**/*.bak',
    'gha-creds-*.json'
  ].where((v) => !existing.split('\n').contains(v));
  if (entries.isNotEmpty) {
    ignore.writeAsStringSync(
        '$existing\n# torchinlane signing\n${entries.join('\n')}\n');
  }
}

bool sameKeystore(File a, File b) {
  final x = a.readAsBytesSync(), y = b.readAsBytesSync();
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}
