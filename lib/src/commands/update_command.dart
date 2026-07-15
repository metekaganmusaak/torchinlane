import 'dart:io';

import 'package:args/command_runner.dart';

import '../config/torchinlane_config.dart';
import '../project/flutter_project.dart';
import '../scaffold/fastlane_scaffolder.dart';
import '../shell/logger.dart';

/// Re-renders the generated scaffold files from the current CLI's templates and
/// applies any that changed, so a project stays in sync after the torchinlane
/// CLI itself is upgraded. User-owned files (ExportOptions.plist, release notes,
/// torchinlane.yaml) are never touched.
class UpdateCommand extends Command<int> {
  UpdateCommand({Logger logger = const Logger()}) : _logger = logger {
    argParser
      ..addFlag('yes',
          abbr: 'y',
          help: 'Apply all changes without prompting per file.',
          negatable: false)
      ..addFlag('dry-run',
          help: 'Show what would change without writing anything.',
          negatable: false);
  }

  final Logger _logger;

  @override
  String get name => 'update';

  @override
  String get description =>
      'Re-apply the current CLI\'s scaffold templates to this project (Fastfiles, ChangelogHelper, scripts/build.sh).';

  @override
  Future<int> run() async {
    final project = FlutterProject.findRoot();
    if (project == null) {
      _logger.error('Not inside a Flutter project.');
      return 1;
    }
    if (!project.torchinlaneConfigFile.existsSync()) {
      _logger.error('No torchinlane.yaml found. Run `torchinlane init` first.');
      return 1;
    }

    _logger.info(
        'Tip: to upgrade the CLI itself first, run: dart pub global activate torchinlane');

    final config = TorchinlaneConfig.load(project.torchinlaneConfigFile);
    final scaffolder = FastlaneScaffolder(project);
    final files = scaffolder.managedFiles(
      appName: config.appName,
      ios: config.ios,
      android: config.android,
      sourceLocale: config.changelogs.sourceLocale,
    );

    final applyAll = argResults!['yes'] as bool;
    final dryRun = argResults!['dry-run'] as bool;
    final root = project.root.path;

    var changed = 0;
    var applied = 0;
    var skipped = 0;

    for (final entry in files.entries) {
      final rel = entry.key;
      final newContent = entry.value;
      final file = File('$root/$rel');
      final exists = file.existsSync();
      final oldContent = exists ? file.readAsStringSync() : null;

      if (oldContent == newContent) continue; // up to date
      changed++;

      if (!exists) {
        _logger.info('\n[new] $rel');
      } else {
        _logger.info('\n[changed] $rel');
        _printDiff(oldContent!, newContent);
      }

      if (dryRun) continue;

      var apply = applyAll;
      if (!applyAll) {
        apply = _askYesNo('Apply update to $rel?');
      }

      if (apply) {
        if (exists) file.copySync('${file.path}.bak');
        file.createSync(recursive: true);
        file.writeAsStringSync(newContent);
        if (FastlaneScaffolder.executablePaths.contains(rel) &&
            !Platform.isWindows) {
          Process.runSync('chmod', ['+x', file.path]);
        }
        applied++;
      } else {
        skipped++;
      }
    }

    if (changed == 0) {
      _logger.success('Everything is up to date. Nothing to update.');
      return 0;
    }

    if (dryRun) {
      _logger.info(
          '\n$changed file(s) would change. Re-run without --dry-run to apply.');
      return 0;
    }

    _logger.success(
        '\nUpdated $applied file(s), skipped $skipped. Backups saved as *.bak.');
    if (skipped > 0) {
      _logger.info(
          'To force a full regeneration instead, run: torchinlane init --force');
    }
    return 0;
  }

  /// Minimal line-level diff: shows removed (-) and added (+) lines.
  void _printDiff(String oldContent, String newContent) {
    final oldLines = oldContent.split('\n');
    final newLines = newContent.split('\n');
    final oldSet = oldLines.toSet();
    final newSet = newLines.toSet();

    for (final line in oldLines) {
      if (!newSet.contains(line)) _logger.info('  - $line');
    }
    for (final line in newLines) {
      if (!oldSet.contains(line)) _logger.info('  + $line');
    }
  }

  bool _askYesNo(String question) {
    while (true) {
      stdout.write('$question (y/n): ');
      final answer = stdin.readLineSync()?.trim().toLowerCase();
      if (answer == 'y' || answer == 'yes') return true;
      if (answer == 'n' || answer == 'no') return false;
      stdout.writeln('Please answer y or n.');
    }
  }
}
