import 'dart:convert';
import 'dart:io';
import 'package:yaml_edit/yaml_edit.dart';
import 'package:test/test.dart';
import 'package:torchinlane/src/project/flutter_project.dart';
import 'package:torchinlane/src/setup/credentials.dart';
import 'package:torchinlane/src/config/torchinlane_config.dart';
import 'test_project.dart';

void main() {
  late FlutterProject project;
  setUp(() => project = createTestProject());
  tearDown(() => project.root.deleteSync(recursive: true));
  test('absolute credential paths inside the project are ignored by Git', () {
    final editor = YamlEditor(project.torchinlaneConfigFile.readAsStringSync());
    editor.update(['android', 'service_account_json'],
        '${project.root.path}/private/google.json');
    project.torchinlaneConfigFile.writeAsStringSync(editor.toString());
    Credentials(project).import(
        'android',
        jsonEncode({
          'type': 'service_account',
          'client_email': 'test@example.com',
          'private_key': 'PRIVATE'
        }));
    expect(File('${project.root.path}/.gitignore').readAsStringSync(),
        contains('private/google.json'));
  });
  test(
      'imports Google credential without logging key, protects gitignore and refuses rotation overwrite',
      () {
    final value = jsonEncode({
      'type': 'service_account',
      'client_email': 'test@example.com',
      'private_key': 'PRIVATE'
    });
    final file = Credentials(project).import('android', value);
    expect(file.readAsStringSync(), value);
    expect(File('${project.root.path}/.gitignore').readAsStringSync(),
        contains('keys/google.json'));
    expect(
        () => Credentials(project)
            .import('android', value.replaceFirst('PRIVATE', 'NEW')),
        throwsStateError);
  });
  test(
      'accepts keyless Google external-account format and rejects arbitrary JSON',
      () {
    Credentials.validateContents(
        'android',
        jsonEncode({
          'type': 'external_account',
          'audience': 'wif',
          'credential_source': {'file': 'token'}
        }));
    expect(() => Credentials.validateContents('android', '{}'),
        throwsFormatException);
    expect(() => Credentials.validateContents('ios', 'wrong key'),
        throwsFormatException);
  });
  test('YAML round-trip handles names with colons and numeric-looking team IDs',
      () {
    final config = TorchinlaneConfig.load(project.torchinlaneConfigFile);
    project.torchinlaneConfigFile.writeAsStringSync(TorchinlaneConfig.render(
        appName: 'App: "Hello"',
        ios: config.ios,
        android: config.android,
        changelogsDir: 'custom notes',
        sourceLocale: 'en'));
    final loaded = TorchinlaneConfig.load(project.torchinlaneConfigFile);
    expect(loaded.appName, 'App: "Hello"');
    expect(loaded.ios.itcTeamId, '123456');
    expect(loaded.changelogs.dir, 'custom notes');
  });
}
