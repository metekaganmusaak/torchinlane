import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';
import 'package:torchinlane/src/setup/ci.dart';
import 'package:torchinlane/src/setup/android_signing.dart';
import 'package:torchinlane/src/project/flutter_project.dart';
import 'test_project.dart';

void main() {
  test(
      'workflow YAML contains independent jobs, WIF and iOS signing; embedded scripts parse',
      () async {
    final text = renderCi(
        platforms: ['ios', 'android'],
        flutterVersion: '3.35.0',
        wifProvider:
            'projects/123/locations/global/workloadIdentityPools/pool/providers/github',
        serviceAccount: 'release@example.iam.gserviceaccount.com',
        signingGitUrl: 'https://github.com/company/certs.git');
    final yaml = loadYaml(text) as YamlMap;
    expect(yaml['jobs'].keys.toSet(), {'ios', 'android'});
    expect(text, contains('google-github-actions/auth@v3'));
    expect(text, isNot(contains('GOOGLE_PLAY_CREDENTIALS_JSON')));
    expect(text, contains('torchinlane signing sync'));
    expect(
        () => renderCi(
            platforms: ['android'], flutterVersion: 'stable; echo secret'),
        throwsArgumentError);
    expect(() => renderCi(platforms: ['android'], wifProvider: 'provider'),
        throwsArgumentError);
    final temp = Directory.systemTemp.createTempSync('torchinlane-ci-test-');
    try {
      Directory('${temp.path}/android').createSync();
      var index = 0;
      for (final job in (yaml['jobs'] as YamlMap).values) {
        for (final step in job['steps']) {
          final run = step['run'];
          if (run is! String) continue;
          final script = File('${temp.path}/step-${index++}.sh')
            ..writeAsStringSync(run);
          if (!Platform.isWindows) {
            final result = await Process.run('bash', ['-n', script.path]);
            expect(result.exitCode, 0, reason: result.stderr.toString());
          }
          if (run.contains("python3 - <<'PY'")) {
            final python = run.split("python3 - <<'PY'\n")[1].split('\nPY')[0];
            final file = File('${temp.path}/signing.py')
              ..writeAsStringSync(python);
            final result = await Process.run('python3', [file.path],
                workingDirectory: temp.path,
                environment: {
                  'KEYSTORE_BASE64': base64Encode([1, 2, 3]),
                  'KEYSTORE_PASSWORD': r'pass\word',
                  'KEY_PASSWORD': 'hello\nworld',
                  'KEY_ALIAS': 'upload'
                });
            expect(result.exitCode, 0, reason: result.stderr.toString());
            final properties = File('${temp.path}/android/key.properties');
            // fixture has no android/ initially; create and retry actual script.
            if (!properties.existsSync()) fail('Properties were not generated');
            expect(properties.readAsStringSync(), contains(r'pass\\word'));
            expect(properties.readAsStringSync(), contains(r'hello\nworld'));
          }
        }
      }
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
  test(
      'Android Gradle setup replaces stock debug signing in both DSLs and is idempotent',
      () {
    final kotlin =
        'plugins { id("com.android.application") }\nandroid {\n buildTypes { release { signingConfig = signingConfigs.getByName("debug") } }\n}\n';
    final groovy =
        'plugins { id "com.android.application" }\nandroid {\n buildTypes { release { signingConfig signingConfigs.debug } }\n}\n';
    for (final pair in [(kotlin, true), (groovy, false)]) {
      final result = configureAndroidGradle(pair.$1, kotlin: pair.$2);
      expect(result, contains('key.properties'));
      expect(result, isNot(contains('signingConfigs.debug')));
      expect(result, isNot(contains('getByName("debug")')));
      expect(configureAndroidGradle(result, kotlin: pair.$2), result);
    }
    expect(
        () => configureAndroidGradle(
            'android { signingConfigs { release {} } }',
            kotlin: false),
        throwsStateError);
  });
  test('signing preserves custom layouts, backs up Gradle and protects secrets',
      () {
    final FlutterProject project = createTestProject();
    final temp = Directory.systemTemp.createTempSync('torchinlane-key-');
    try {
      final gradle = File('${project.root.path}/android/app/build.gradle.kts');
      gradle.parent.createSync(recursive: true);
      final original =
          'plugins {}\nandroid { buildTypes { release { signingConfig = signingConfigs.getByName("debug") } } }';
      gradle.writeAsStringSync(original);
      final key = File('${temp.path}/upload.jks')..writeAsBytesSync([1, 2, 3]);
      setupAndroidSigning(project,
          keystore: key,
          alias: 'upload',
          storePassword: 'pass',
          keyPassword: 'pass',
          dryRun: true);
      expect(gradle.readAsStringSync(), original);
      setupAndroidSigning(project,
          keystore: key,
          alias: 'upload',
          storePassword: 'pass',
          keyPassword: 'pass');
      expect(File('${gradle.path}.bak').readAsStringSync(), original);
      expect(
          File('${project.root.path}/android/key.properties')
              .readAsStringSync(),
          contains('keyAlias=upload'));
      expect(File('${project.root.path}/.gitignore').readAsStringSync(),
          contains('android/key.properties'));
    } finally {
      project.root.deleteSync(recursive: true);
      temp.deleteSync(recursive: true);
    }
  });
}
