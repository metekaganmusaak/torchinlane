import 'dart:io';
import 'package:args/command_runner.dart';
import '../changelog/locale_maps.dart';
import '../config/torchinlane_config.dart';
import '../project/flutter_project.dart';
import '../store/content.dart';
import '../store/service.dart';
import '../store/translation.dart';
import '../store/translation_task.dart';

class StoreCommand extends Command<int> {
  StoreCommand() {
    for (final action in [
      'init',
      'locales',
      'validate',
      'export',
      'push',
      'pull',
      'translate',
      'prompt'
    ]) {
      addSubcommand(_StoreAction(action));
    }
  }
  @override
  String get name => 'store';
  @override
  String get description =>
      'Manage localized store texts, images and release notes.';
}

class _StoreAction extends Command<int> {
  _StoreAction(this.action) {
    argParser
      ..addOption('platform',
          defaultsTo: 'ios,android', help: 'ios, android, or ios,android')
      ..addOption('locales', help: 'Comma-separated locale codes, or all.')
      ..addOption('scope',
          allowed: ['all', 'metadata', 'images', 'notes'], defaultsTo: 'all')
      ..addOption('track',
          allowed: ['internal', 'alpha', 'beta', 'production'],
          defaultsTo: 'internal')
      ..addOption('version-code',
          help: 'Existing Google Play release version code.')
      ..addOption('app-version', help: 'Apple editable version string.')
      ..addOption('output', defaultsTo: 'build/torchinlane-store')
      ..addOption('from', defaultsTo: 'en')
      ..addFlag('api',
          negatable: false,
          help:
              'Use optional paid Anthropic translation instead of generating an agent task.')
      ..addFlag('dry-run', negatable: false)
      ..addFlag('replace-images',
          negatable: false,
          help: 'Replace supplied Apple screenshot display classes.')
      ..addFlag('apply',
          negatable: false,
          help: 'Import remote text snapshot; backs up local files.')
      ..addFlag('overwrite',
          negatable: false, help: 'Replace existing translated text fields.');
  }
  final String action;
  @override
  String get name => action;
  @override
  String get description => {
        'init':
            'Create editable locale JSON files without overwriting content.',
        'locales': 'List supported native locale codes for each store.',
        'validate': 'Check field limits, URLs, image dimensions and counts.',
        'export': 'Export content in Fastlane directory layout.',
        'push': 'Upload store content without building or publishing a binary.',
        'pull':
            'Download remote texts, compare, optionally import with backups.',
        'translate':
            'Prepare a coding-agent translation task; --api enables optional API translation.',
        'prompt': 'Print an API-free Claude Code/Codex translation task.',
      }[action]!;
  @override
  Future<int> run() async {
    final args = argResults!;
    final platforms = parsePlatforms(args['platform'] as String);
    if (action == 'locales') {
      for (final platform in platforms) {
        stdout.writeln(
            '$platform: ${(platform == 'ios' ? appleStoreLocales : googleStoreLocales).join(', ')}');
      }
      return 0;
    }
    final project = FlutterProject.findRoot();
    if (project == null) {
      throw StateError('Run inside a Flutter project with ios/ and android/.');
    }
    final content = StoreContent(project);
    final requested = args['locales'] as String?;
    final config = project.torchinlaneConfigFile.existsSync()
        ? TorchinlaneConfig.load(project.torchinlaneConfigFile)
        : null;
    final locales = requested == 'all'
        ? {...appleStoreLocales, ...googleStoreLocales}.toList()
        : requested?.split(',').map((s) => s.trim()).toList() ??
            config?.changelogs.locales ??
            ['en'];
    if (action == 'init') {
      content.initialize(platforms, locales);
      stdout.writeln(
          'Store files created in store/. Existing content preserved.');
      return 0;
    }
    final scope = args['scope'] as String;
    if (action == 'validate') {
      final errors = content.validate(platforms, scope: scope);
      for (final e in errors) {
        stderr.writeln(e);
      }
      stdout.writeln(errors.isEmpty
          ? 'Store content is valid.'
          : '${errors.length} validation errors.');
      return errors.isEmpty ? 0 : 1;
    }
    if (action == 'export') {
      final destination = Directory('${project.root.path}/${args['output']}');
      if (destination.existsSync() && destination.listSync().isNotEmpty) {
        throw StateError(
            'Export directory is not empty; use a new --output path.');
      }
      content.exportTo(destination, platforms,
          scope: scope, versionCode: args['version-code'] as String?);
      stdout.writeln('Exported to ${destination.path}');
      return 0;
    }
    final service = StoreService(project);
    if (action == 'push') {
      return service.push(platforms,
          scope: scope,
          track: args['track'] as String,
          versionCode: args['version-code'] as String?,
          appVersion: args['app-version'] as String?,
          dryRun: args['dry-run'] as bool,
          replaceImages: args['replace-images'] as bool);
    }
    if (action == 'pull') {
      return service.pull(platforms,
          apply: args['apply'] as bool,
          appVersion: args['app-version'] as String?);
    }
    if (action == 'prompt' || !(args['api'] as bool)) {
      stdout.write(StoreTranslationTask(content).build(platforms,
          from: args['from'] as String,
          locales: requested == null ? null : locales,
          overwrite: args['overwrite'] as bool));
      return 0;
    }
    final translator = StoreTranslator();
    var failed = false;
    try {
      for (final platform in platforms) {
        final source = storeLocale(platform, args['from'] as String);
        if (source == null) {
          stdout.writeln('Skipping unsupported source locale on $platform');
          continue;
        }
        final fields = content.read(platform, source);
        if (fields.values.every((s) => s.trim().isEmpty)) {
          throw StateError('Fill store/$platform/$source.json first.');
        }
        for (final locale in locales
            .map((l) => storeLocale(platform, l))
            .whereType<String>()
            .toSet()) {
          if (locale == source) continue;
          try {
            final existing = content.read(platform, locale);
            final pending = {
              for (final e in fields.entries)
                if ((args['overwrite'] as bool) ||
                    (existing[e.key] ?? '').trim().isEmpty)
                  e.key: e.value
            };
            final translated =
                await translator.translate(platform, source, locale, pending);
            if (translated.isNotEmpty) {
              content.write(platform, locale, {
                ...existing,
                ...translated,
                for (final e in fields.entries
                    .where((e) => (storeFields[platform]![e.key] ?? 0) == 0))
                  if ((existing[e.key] ?? '').isEmpty) e.key: e.value
              });
            }
            stdout.writeln(
                '$platform/$locale: ${translated.length} fields translated');
          } catch (e) {
            failed = true;
            stderr.writeln('$platform/$locale: $e');
          }
        }
      }
    } finally {
      translator.close();
    }
    return failed ? 1 : 0;
  }
}
