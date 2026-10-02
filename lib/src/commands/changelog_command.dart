import 'dart:io';

import 'package:args/command_runner.dart';

import '../changelog/translator.dart';
import '../changelog/locale_maps.dart';
import '../store/service.dart';
import '../config/torchinlane_config.dart';
import '../project/flutter_project.dart';
import '../shell/logger.dart';

class ChangelogCommand extends Command<int> {
  ChangelogCommand({Logger logger = const Logger()}) {
    addSubcommand(_TranslateCommand(logger: logger));
    addSubcommand(_PushCommand(logger: logger));
    addSubcommand(_ClearCommand(logger: logger));
  }

  @override
  String get name => 'changelog';

  @override
  String get description => 'Translate and publish store changelogs.';
}

class _TranslateCommand extends Command<int> {
  _TranslateCommand({Logger logger = const Logger()}) : _logger = logger {
    argParser
      ..addOption('from', help: 'Source locale.')
      ..addOption('text', help: 'Source text (overrides reading from file).')
      ..addFlag('overwrite',
          help: 'Overwrite existing non-empty locale files.', negatable: false);
  }

  final Logger _logger;

  @override
  String get name => 'translate';

  @override
  String get description =>
      'Translate source changelog into all configured locales via Claude API.';

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

    final config = TorchinlaneConfig.load(project.torchinlaneConfigFile);
    final sourceLocale =
        (argResults!['from'] as String?) ?? config.changelogs.sourceLocale;
    final overwrite = argResults!['overwrite'] as bool;

    String sourceText;
    final explicitText = argResults!['text'] as String?;
    if (explicitText != null) {
      sourceText = explicitText;
    } else {
      final sourceFile = File(
          '${project.root.path}/${config.changelogs.dir}/$sourceLocale/release_notes.txt');
      if (!sourceFile.existsSync() ||
          sourceFile.readAsStringSync().trim().isEmpty) {
        _logger.error(
            'Source changelog is empty: ${sourceFile.path}. Fill it in or pass --text.');
        return 1;
      }
      sourceText = sourceFile.readAsStringSync().trim();
    }

    final targets =
        config.changelogs.locales.where((l) => l != sourceLocale).toList();

    _logger.info(
        'Translating from "$sourceLocale" into ${targets.length} locales via Claude API...');
    final translator = ChangelogTranslator();
    try {
      final translations = await translator.translate(
        sourceText: sourceText,
        sourceLocale: sourceLocale,
        targetLocales: targets,
      );

      var written = 0;
      var skipped = 0;
      for (final entry in translations.entries) {
        final file = File(
            '${project.root.path}/${config.changelogs.dir}/${entry.key}/release_notes.txt');
        if (file.existsSync() &&
            file.readAsStringSync().trim().isNotEmpty &&
            !overwrite) {
          skipped++;
          continue;
        }
        file.createSync(recursive: true);
        file.writeAsStringSync(entry.value.trim());
        written++;
      }

      // Ensure source locale file itself is up to date.
      final sourceFile = File(
          '${project.root.path}/${config.changelogs.dir}/$sourceLocale/release_notes.txt');
      sourceFile.createSync(recursive: true);
      sourceFile.writeAsStringSync(sourceText);

      _logger.success(
          'Wrote $written locale files (skipped $skipped already-filled files).');
      return 0;
    } catch (e) {
      _logger.error(e.toString());
      return 1;
    } finally {
      translator.close();
    }
  }
}

class _PushCommand extends Command<int> {
  _PushCommand({Logger logger = const Logger()}) : _logger = logger {
    argParser
      ..addOption('platform',
          help: 'ios, android, or ios,android', defaultsTo: 'ios,android')
      ..addOption('track',
          allowed: ['internal', 'alpha', 'beta', 'production'],
          defaultsTo: 'internal')
      ..addOption('version-code',
          help: 'Existing Google Play version code (required for Android).')
      ..addOption('app-version', help: 'Editable App Store version.')
      ..addFlag('dry-run', negatable: false);
  }

  final Logger _logger;

  @override
  String get name => 'push';

  @override
  String get description =>
      'Push release notes to the stores without building/uploading a binary.';

  @override
  Future<int> run() async {
    final project = FlutterProject.findRoot();
    if (project == null) {
      _logger.error('Not inside a Flutter project.');
      return 1;
    }

    final platforms = parsePlatforms(argResults!['platform'] as String);
    final code = argResults!['version-code'] as String?;
    if (platforms.contains('android') &&
        (code == null || !RegExp(r'^[1-9][0-9]*$').hasMatch(code))) {
      throw ArgumentError('Android note updates require --version-code.');
    }
    if (argResults!['dry-run'] as bool) {
      _logger.info(
          'Would update notes on ${platforms.join(',')} track=${argResults!['track']} version=$code');
      return 0;
    }
    var failed = false;
    final service = StoreService(project, log: _logger.info);
    for (final platform in platforms) {
      try {
        final result =
            await service.lane(platform, 'update_release_notes', env: {
          'TORCHINLANE_TRACK': argResults!['track'] as String,
          if (code != null) 'TORCHINLANE_VERSION_CODE': code,
          if (argResults!['app-version'] != null)
            'TORCHINLANE_APP_VERSION': argResults!['app-version'] as String,
        });
        failed |= result != 0;
      } catch (e) {
        failed = true;
        _logger.error('$platform: $e');
      }
    }
    if (failed) return 1;

    _logger.success('Release notes pushed.');
    return 0;
  }
}

class _ClearCommand extends Command<int> {
  _ClearCommand({Logger logger = const Logger()}) : _logger = logger;

  final Logger _logger;

  @override
  String get name => 'clear';

  @override
  String get description => 'Clear all changelog files (post-release cleanup).';

  @override
  Future<int> run() async {
    final project = FlutterProject.findRoot();
    if (project == null) {
      _logger.error('Not inside a Flutter project.');
      return 1;
    }
    final config = TorchinlaneConfig.load(project.torchinlaneConfigFile);
    final directory =
        Directory('${project.root.path}/${config.changelogs.dir}');
    if (!directory.existsSync()) {
      _logger.error('No changelogs directory found.');
      return 1;
    }

    var cleared = 0;
    for (final entity in directory.listSync()) {
      if (entity is! Directory) continue;
      final file = File('${entity.path}/release_notes.txt');
      if (file.existsSync()) {
        file.writeAsStringSync('');
        cleared++;
      }
    }

    _logger.success('Cleared $cleared changelog files.');
    return 0;
  }
}
