import 'dart:io';

import 'package:args/command_runner.dart';

import '../project/flutter_project.dart';
import '../shell/cli_prompt.dart';
import '../shell/logger.dart';

class UninstallCommand extends Command<int> {
  UninstallCommand({Logger logger = const Logger()}) : _logger = logger {
    argParser.addFlag('yes', help: 'Skip confirmation prompt.', negatable: false);
  }

  final Logger _logger;

  @override
  String get name => 'uninstall';

  @override
  String get description => 'Remove the fastlane scaffold and torchinlane.yaml created by `torchinlane init`.';

  @override
  Future<int> run() async {
    final project = FlutterProject.findRoot();
    if (project == null) {
      _logger.error('Not inside a Flutter project.');
      return 1;
    }

    final root = project.root.path;
    final targets = <FileSystemEntity>[
      Directory('$root/ios/fastlane'),
      Directory('$root/android/fastlane'),
      Directory('$root/fastlane'),
      File('$root/ios/ExportOptions.plist'),
      File('$root/scripts/build.sh'),
      project.torchinlaneConfigFile,
    ].where((e) => e.existsSync()).toList();

    if (targets.isEmpty) {
      _logger.info('Nothing to remove — no fastlane scaffold found.');
      return 0;
    }

    _logger.info('This will remove:');
    for (final target in targets) {
      _logger.info('  - ${target.path}');
    }
    _logger.info('(changelogs/ is left untouched.)');

    final skipConfirm = argResults!['yes'] as bool;
    if (!skipConfirm && !askYesNo('Proceed?')) {
      _logger.info('Aborted.');
      return 0;
    }

    for (final target in targets) {
      target.deleteSync(recursive: true);
    }

    _logger.success('\nFastlane scaffold removed. Run `torchinlane init` to set it up again.');
    return 0;
  }
}
