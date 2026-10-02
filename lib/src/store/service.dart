import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../config/torchinlane_config.dart';
import '../project/flutter_project.dart';
import '../shell/toolchain.dart';
import '../shell/logger.dart';
import '../changelog/locale_maps.dart';
import 'content.dart';

typedef StoreLog = void Function(String text);

class StoreService {
  StoreService(this.project, {StoreLog? log}) : log = log ?? stdout.writeln;
  final FlutterProject project;
  final StoreLog log;

  Future<int> lane(String platform, String name,
      {Map<String, String> env = const {}}) async {
    if (!File('${project.root.path}/fastlane/StoreHelper.rb').existsSync()) {
      throw StateError(
          'Run torchinlane update -y (or complete Setup) before store operations.');
    }
    final process = await Process.start('fastlane', [name],
        workingDirectory: '${project.root.path}/$platform',
        environment: Toolchain(logger: const Logger()).augmentedEnvironment({
          'FASTLANE_SKIP_UPDATE_CHECK': '1',
          'FASTLANE_DISABLE_COLORS': '1',
          'CI': 'true',
          ...env,
        }));
    // Drain both pipes before returning, including the last output line.
    final out = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(log);
    final err = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(log);
    final code = await process.exitCode;
    await Future.wait([out, err]);
    return code;
  }

  Future<int> push(List<String> platforms,
      {String scope = 'all',
      String track = 'internal',
      String? versionCode,
      String? appVersion,
      bool dryRun = false,
      bool replaceImages = false,
      bool skipNotes = false}) async {
    if (!['all', 'metadata', 'images', 'notes'].contains(scope)) {
      throw ArgumentError('Invalid scope');
    }
    if (!['internal', 'alpha', 'beta', 'production'].contains(track)) {
      throw ArgumentError('Invalid track');
    }
    if (versionCode != null &&
        !RegExp(r'^[1-9][0-9]*$').hasMatch(versionCode)) {
      throw ArgumentError('Invalid version code');
    }
    final content = StoreContent(project);
    final problems =
        content.validate(platforms, scope: scope, skipNotes: skipNotes);
    if (problems.isNotEmpty) throw StateError(problems.join('\n'));
    final hasGoogleNotes = !skipNotes &&
        platforms.contains('android') &&
        ['all', 'notes'].contains(scope) &&
        content.locales('android').any((l) =>
            (content.read('android', l)['release_notes'] ?? '')
                .trim()
                .isNotEmpty);
    if (hasGoogleNotes && versionCode == null) {
      throw ArgumentError(
          'Android notes require --version-code to select an existing release.');
    }
    log('Store upload: ${platforms.join(', ')}; scope=$scope; track=$track; version=${versionCode ?? appVersion ?? 'editable'}');
    if (replaceImages) {
      log('Existing Apple screenshots in supplied locales (all device sets) will be replaced.');
    }
    if (platforms.contains('android') && ['all', 'images'].contains(scope)) {
      log('Google replaces each supplied image group; omitted groups are preserved.');
    }
    if (dryRun) {
      log('Validation passed. Dry run: no store request made.');
      return 0;
    }
    final staging = Directory.systemTemp.createTempSync('torchinlane-store-');
    var failed = false;
    try {
      content.exportTo(staging, platforms,
          scope: scope, versionCode: versionCode, skipNotes: skipNotes);
      for (final platform in platforms) {
        final root = Directory('${staging.path}/$platform');
        if (!root.existsSync() ||
            root.listSync(recursive: true).whereType<File>().isEmpty) {
          log('$platform: no content to upload');
          continue;
        }
        try {
          final code = await lane(platform, 'store_push', env: {
            'TORCHINLANE_STORE_STAGING': staging.path,
            'TORCHINLANE_STORE_SCOPE': scope,
            'TORCHINLANE_TRACK': track,
            if (versionCode != null) 'TORCHINLANE_VERSION_CODE': versionCode,
            if (appVersion != null) 'TORCHINLANE_APP_VERSION': appVersion,
            'TORCHINLANE_REPLACE_IMAGES': replaceImages ? '1' : '0',
          });
          failed |= code != 0;
          log('$platform: ${code == 0 ? 'uploaded' : 'failed (exit $code)'}');
        } catch (e) {
          failed = true;
          log('$platform: $e');
        }
      }
    } finally {
      staging.deleteSync(recursive: true);
    }
    return failed ? 1 : 0;
  }

  Future<int> pull(List<String> platforms,
      {bool apply = false, String? appVersion}) async {
    final temp = Directory.systemTemp.createTempSync('torchinlane-pull-');
    final content = StoreContent(project);
    var failed = false;
    try {
      for (final platform in platforms) {
        try {
          final code = await lane(platform, 'store_pull', env: {
            'TORCHINLANE_STORE_STAGING': temp.path,
            if (appVersion != null) 'TORCHINLANE_APP_VERSION': appVersion
          });
          if (code != 0) {
            failed = true;
            continue;
          }
          final source = File('${temp.path}/$platform/snapshot.json');
          final data =
              jsonDecode(source.readAsStringSync()) as Map<String, dynamic>;
          final snapshot =
              File('${content.directory.path}/.snapshots/$platform.json');
          snapshot.parent.createSync(recursive: true);
          snapshot.writeAsStringSync(source.readAsStringSync());
          log('$platform remote snapshot: ${p.relative(snapshot.path, from: project.root.path)}');
          for (final entry in data.entries) {
            if (storeLocale(platform, entry.key) != entry.key) {
              log('Skipping unsupported remote locale ${entry.key}');
              continue;
            }
            final remote = Map<String, String>.from(entry.value as Map);
            final local = content.read(platform, entry.key);
            for (final field in remote.entries) {
              if (local[field.key] != field.value) {
                log('$platform/${entry.key}/${field.key}:\n  local: ${jsonEncode(local[field.key] ?? '')}\n  remote: ${jsonEncode(field.value)}');
              }
            }
            if (apply) {
              final file = content.file(platform, entry.key);
              if (file.existsSync()) file.copySync('${file.path}.bak');
              content.write(platform, entry.key, {...local, ...remote});
            }
          }
        } catch (e) {
          failed = true;
          log('$platform: $e');
        }
      }
    } finally {
      temp.deleteSync(recursive: true);
    }
    return failed ? 1 : 0;
  }

  Future<int> verify(List<String> platforms) async {
    TorchinlaneConfig.load(project.torchinlaneConfigFile);
    var failed = false;
    for (final platform in platforms) {
      try {
        failed |= await lane(platform, 'validate_credentials') != 0;
      } catch (e) {
        failed = true;
        log('$platform: $e');
      }
    }
    return failed ? 1 : 0;
  }
}
