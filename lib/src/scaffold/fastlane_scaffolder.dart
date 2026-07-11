import 'dart:io';

import '../config/torchinlane_config.dart';
import '../project/flutter_project.dart';
import 'templates.dart';

class FastlaneScaffolder {
  FastlaneScaffolder(this.project);

  final FlutterProject project;

  void scaffold({
    required String appName,
    required IosConfig ios,
    required AndroidConfig android,
    required String sourceLocale,
  }) {
    final root = project.root.path;

    _write('$root/ios/fastlane/Appfile', renderTemplate(iosAppfileTemplate, {
      'bundle_id': ios.bundleId,
      'apple_id': ios.appleId,
      'itc_team_id': ios.itcTeamId,
      'team_id': ios.teamId,
    }));

    _write('$root/ios/fastlane/Fastfile', renderTemplate(
      iosFastfileTemplate,
      {
        'asc_key_id': ios.ascKeyId,
        'asc_issuer_id': ios.ascIssuerId,
        'source_locale': sourceLocale,
      },
      flags: {'firebase': ios.firebaseCrashlytics},
    ));

    _write('$root/android/fastlane/Appfile', renderTemplate(androidAppfileTemplate, {
      'service_account_json': android.serviceAccountJson,
      'package_name': android.packageName,
    }));

    _write('$root/android/fastlane/Fastfile', androidFastfileTemplate);

    _write('$root/fastlane/ChangelogHelper.rb', changelogHelperTemplate);

    final exportOptions = File('$root/ios/ExportOptions.plist');
    if (!exportOptions.existsSync()) {
      _write(exportOptions.path, renderTemplate(exportOptionsPlistTemplate, {'team_id': ios.teamId}));
    }

    for (final locale in defaultLocales) {
      final file = File('$root/changelogs/$locale/release_notes.txt');
      if (!file.existsSync()) {
        file.createSync(recursive: true);
      }
    }

    final configFile = project.torchinlaneConfigFile;
    configFile.writeAsStringSync(TorchinlaneConfig.render(
      appName: appName,
      ios: ios,
      android: android,
      changelogsDir: 'changelogs',
      sourceLocale: sourceLocale,
    ));

    _updateGitignore(root, ios, android);
  }

  void _write(String path, String content) {
    final file = File(path);
    file.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void _updateGitignore(String root, IosConfig ios, AndroidConfig android) {
    final gitignore = File('$root/.gitignore');
    final entries = <String>[
      ios.ascKeyPath,
      android.serviceAccountJson,
      '**/fastlane/report.xml',
      '**/fastlane/README.md',
    ];

    final existing = gitignore.existsSync() ? gitignore.readAsStringSync() : '';
    final toAdd = entries.where((e) => !existing.contains(e)).toList();
    if (toAdd.isEmpty) return;

    final addition = '\n# torchinlane\n${toAdd.join('\n')}\n';
    gitignore.writeAsStringSync(existing + addition);
  }
}
