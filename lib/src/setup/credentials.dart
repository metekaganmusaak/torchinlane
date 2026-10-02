import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml_edit/yaml_edit.dart';
import '../config/torchinlane_config.dart';
import '../project/flutter_project.dart';
import '../scaffold/fastlane_scaffolder.dart';

class Credentials {
  Credentials(this.project);
  final FlutterProject project;

  static void validateContents(String platform, String contents) {
    if (platform == 'ios') {
      if (!contents.contains('-----BEGIN PRIVATE KEY-----') ||
          !contents.contains('-----END PRIVATE KEY-----')) {
        throw FormatException('Expected an Apple .p8 PKCS#8 private key.');
      }
    } else {
      final data = jsonDecode(contents) as Map<String, dynamic>;
      final type = data['type'];
      if (!['service_account', 'external_account', 'authorized_user']
          .contains(type)) {
        throw FormatException('Unsupported Google credential type.');
      }
      if (type == 'service_account' &&
          (data['client_email'] is! String || data['private_key'] is! String)) {
        throw FormatException(
            'Service account JSON needs client_email and private_key.');
      }
      if (type == 'external_account' &&
          (data['audience'] == null || data['credential_source'] == null)) {
        throw FormatException(
            'External account JSON needs audience and credential_source.');
      }
      if (type == 'authorized_user' &&
          (data['refresh_token'] == null ||
              data['client_id'] == null ||
              data['client_secret'] == null)) {
        throw FormatException(
            'OAuth JSON needs client_id, client_secret and refresh_token.');
      }
    }
  }

  File import(String platform, String contents, {String? profile}) {
    if (!['ios', 'android'].contains(platform)) {
      throw ArgumentError('Invalid credential platform');
    }
    validateContents(platform, contents);
    final config = TorchinlaneConfig.load(project.torchinlaneConfigFile);
    final configured = platform == 'ios'
        ? config.ios.ascKeyPath
        : config.android.serviceAccountJson;
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (profile != null &&
        (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(profile) || home == null)) {
      throw ArgumentError('Invalid profile name/home');
    }
    final target = File(profile == null
        ? p.absolute(project.root.path, configured)
        : '$home/.torchinlane/credentials/$profile/${platform == 'ios' ? 'api_key.p8' : 'google.json'}');
    target.parent.createSync(recursive: true);
    if (target.existsSync() && target.readAsStringSync() != contents) {
      throw StateError(
          'Credential already exists at ${target.path}; choose another profile/path to rotate it.');
    }
    target.writeAsStringSync(contents);
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['600', target.path]);
      if (profile != null) {
        Process.runSync('chmod', ['700', target.parent.path]);
      }
    }
    final editor = YamlEditor(project.torchinlaneConfigFile.readAsStringSync());
    editor.update([
      platform == 'ios' ? 'ios' : 'android',
      platform == 'ios' ? 'asc_key_path' : 'service_account_json'
    ], profile == null ? configured : target.path);
    project.torchinlaneConfigFile.writeAsStringSync(editor.toString());
    final ignore = File('${project.root.path}/.gitignore');
    final text = ignore.existsSync() ? ignore.readAsStringSync() : '';
    final relative = p.relative(target.path, from: project.root.path);
    if (profile == null &&
        p.isWithin(project.root.path, target.path) &&
        !text.split('\n').contains(relative)) {
      ignore.writeAsStringSync('$text\n# torchinlane credentials\n$relative\n');
    }
    return target;
  }

  void sync() {
    final config = TorchinlaneConfig.load(project.torchinlaneConfigFile);
    final scaffolder = FastlaneScaffolder(project);
    scaffolder.ensureGitignore(config.ios, config.android);
    final files = scaffolder.managedFiles(
        appName: config.appName,
        ios: config.ios,
        android: config.android,
        sourceLocale: config.changelogs.sourceLocale,
        changelogsDir: config.changelogs.dir);
    for (final entry in files.entries) {
      final file = File('${project.root.path}/${entry.key}');
      if (file.existsSync() && file.readAsStringSync() != entry.value) {
        file.copySync('${file.path}.bak');
      }
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
      if (FastlaneScaffolder.executablePaths.contains(entry.key) &&
          !Platform.isWindows) {
        Process.runSync('chmod', ['+x', file.path]);
      }
    }
  }
}
