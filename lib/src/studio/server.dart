import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'package:yaml_edit/yaml_edit.dart';
import '../changelog/locale_maps.dart';
import '../config/torchinlane_config.dart';
import '../project/flutter_project.dart';
import '../scaffold/fastlane_scaffolder.dart';
import '../setup/credentials.dart';
import '../store/content.dart';
import '../shell/toolchain.dart';
import 'readiness.dart';
import '../store/service.dart';
import '../store/translation.dart';
import '../store/translation_task.dart';
import 'ui.dart';

class StudioServer {
  StudioServer(this.project, {File? preferencesFile})
      : preferencesFile = preferencesFile ??
            File(Platform.environment['TORCHINLANE_STUDIO_PREFERENCES'] ??
                p.join(
                    Platform.environment['HOME'] ??
                        Platform.environment['USERPROFILE'] ??
                        project.root.path,
                    '.torchinlane',
                    'studio-preferences.json')),
        token = base64Url
            .encode(List.generate(32, (_) => Random.secure().nextInt(256)));
  final FlutterProject project;
  final File preferencesFile;
  final String token;
  HttpServer? _server;
  bool _writing = false;
  final Map<String, dynamic> job = {
    'running': false,
    'logs': <String>[],
    'exitCode': null
  };
  final Map<String, String> _verified = {};
  final Map<String, dynamic> _tools = {};
  StudioReadiness get readiness => StudioReadiness(project);
  bool get busy => job['running'] == true || _writing;
  StoreContent get content => StoreContent(project);

  Future<Uri> start({int port = 0}) async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen(_handle);
    return Uri.parse('http://127.0.0.1:${_server!.port}/#$token');
  }

  Future<void> close() async => _server?.close(force: true);

  Future<Map<String, dynamic>> _body(HttpRequest request) async {
    if (request.headers.contentType?.mimeType != 'application/json') {
      throw ArgumentError('JSON body required');
    }
    final bytes = <int>[];
    await for (final chunk in request) {
      if (bytes.length + chunk.length > 28 * 1024 * 1024) {
        throw ArgumentError('Request exceeds 28 MB');
      }
      bytes.addAll(chunk);
    }
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('Referrer-Policy', 'no-referrer');
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('Content-Security-Policy',
        "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' blob:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
    final expected = '127.0.0.1:${_server!.port}';
    if (request.headers.value('host') != expected) {
      response.statusCode = 403;
      await response.close();
      return;
    }
    final origin = request.headers.value('origin');
    if (origin != null && origin != 'http://$expected') {
      response.statusCode = 403;
      await response.close();
      return;
    }
    if (request.uri.path == '/' && request.method == 'GET') {
      response.headers.contentType = ContentType.html;
      response.write(studioHtml);
      await response.close();
      return;
    }
    final supplied = request.headers.value('X-Torchinlane-Token') ??
        request.uri.queryParameters['token'];
    if (supplied != token) {
      response.statusCode = 403;
      response.write('Invalid session token');
      await response.close();
      return;
    }
    try {
      if (request.uri.path == '/asset' && request.method == 'GET') {
        final relative = request.uri.queryParameters['path'] ?? '';
        if (!RegExp(r'^(ios|android)/images/').hasMatch(relative) ||
            !['.png', '.jpg', '.jpeg']
                .contains(p.extension(relative).toLowerCase())) {
          throw ArgumentError('Invalid image');
        }
        final file = content.safeAsset(relative);
        if (!file.existsSync()) {
          response.statusCode = 404;
          await response.close();
          return;
        }
        response.headers.contentType = ContentType('image',
            p.extension(file.path).toLowerCase() == '.png' ? 'png' : 'jpeg');
        await response.addStream(file.openRead());
        await response.close();
        return;
      }
      dynamic result;
      if (request.method == 'GET' && request.uri.path == '/api/state') {
        final config = readiness.config;
        result = {
          'configured': config != null,
          'uiLanguage': _savedLanguage(),
          'projectPath': project.root.path,
          'readiness': readiness.snapshot(verified: _verified, tools: _tools),
          'appName': config?.appName ?? project.readAppName(),
          'fields': storeFields,
          'groups': imageGroups,
          'available': {
            'ios': appleStoreLocales,
            'android': googleStoreLocales
          },
          'locales': {
            for (final platform in ['ios', 'android'])
              platform: content.locales(platform)
          },
          'config': config == null
              ? {}
              : {
                  'app_name': config.appName,
                  'bundle_id': config.ios.bundleId,
                  'team_id': config.ios.teamId,
                  'apple_id': config.ios.appleId,
                  'asc_key_id': config.ios.ascKeyId,
                  'asc_issuer_id': config.ios.ascIssuerId,
                  'package_name': config.android.packageName,
                  'source_locale': config.changelogs.sourceLocale
                },
          'aiAvailable':
              (Platform.environment['ANTHROPIC_API_KEY'] ?? '').isNotEmpty
        };
      } else if (request.method == 'GET' &&
          request.uri.path == '/api/content') {
        final platform = request.uri.queryParameters['platform']!,
            locale = request.uri.queryParameters['locale']!;
        result = {
          'fields': content.read(platform, locale),
          'images': {
            for (final group in imageGroups[platform]!)
              group: content
                  .imageFiles(platform, locale, group)
                  .map((f) => p.relative(f.path, from: content.directory.path))
                  .toList()
          }
        };
      } else if (request.method == 'GET' && request.uri.path == '/api/job') {
        result = job;
      } else if (request.method == 'POST' &&
          request.uri.path == '/api/preferences') {
        final data = await _body(request);
        final language = data['language'];
        if (!['tr', 'en'].contains(language)) {
          throw ArgumentError('Unsupported interface language');
        }
        final existed = preferencesFile.parent.existsSync();
        preferencesFile.parent.createSync(recursive: true);
        preferencesFile
            .writeAsStringSync('${jsonEncode({'language': language})}\n');
        if (!Platform.isWindows) {
          Process.runSync('chmod', ['600', preferencesFile.path]);
          if (!existed) {
            Process.runSync('chmod', ['700', preferencesFile.parent.path]);
          }
        }
        result = {'ok': true};
      } else if (request.method == 'POST' &&
          request.uri.path.startsWith('/api/')) {
        if (busy) {
          response.statusCode = 409;
          throw StateError(
              'Another operation is running. Wait until it finishes.');
        }
        _writing = true;
        try {
          final data = await _body(request);
          switch (request.uri.path) {
            case '/api/copy-source':
              final platform = data['platform'] as String;
              if (!['ios', 'android'].contains(platform)) {
                throw ArgumentError('Invalid platform');
              }
              final c = readiness.config;
              final from = platform == 'ios' ? 'android' : 'ios';
              final locale =
                  storeLocale(platform, c?.changelogs.sourceLocale ?? 'en');
              final source =
                  storeLocale(from, c?.changelogs.sourceLocale ?? 'en');
              if (locale == null || source == null) {
                throw ArgumentError('Unsupported source locale');
              }
              final original = content.read(from, source);
              final target = content.read(platform, locale);
              final mapping = platform == 'ios'
                  ? {
                      'title': 'name',
                      'full_description': 'description',
                      'release_notes': 'release_notes'
                    }
                  : {
                      'name': 'title',
                      'description': 'full_description',
                      'release_notes': 'release_notes'
                    };
              final merged = {...target};
              for (final entry in mapping.entries) {
                final value = original[entry.key] ?? '';
                if (value.trim().isNotEmpty &&
                    (target[entry.value] ?? '').trim().isEmpty) {
                  if (storeFieldLength(platform, entry.value, value) >
                      storeFields[platform]![entry.value]!) {
                    throw ArgumentError(
                        '${entry.value}: source text exceeds target store limit. Shorten it manually.');
                  }
                  merged[entry.value] = value;
                }
              }
              if (merged.length == target.length &&
                  merged.entries.every((e) => target[e.key] == e.value)) {
                throw StateError('No missing common fields to copy.');
              }
              content.write(platform, locale, merged);
              result = {'ok': true};
            case '/api/sync':
              if (readiness.config == null) {
                throw StateError('Önce proje ayarlarını kaydedin.');
              }
              Credentials(project).sync();
              result = {'ok': true};
            case '/api/translation-task':
              result = {
                'prompt': StoreTranslationTask(content).build(
                    parsePlatforms(data['platform'] as String),
                    from: data['from'] as String,
                    overwrite: data['overwrite'] == true)
              };
            case '/api/setup':
              _setup(data);
              result = {'ok': true};
            case '/api/save':
              content.write(
                  data['platform'] as String,
                  data['locale'] as String,
                  Map<String, String>.from(data['fields'] as Map));
              result = {'ok': true};
            case '/api/init':
              content.initialize(parsePlatforms(data['platform'] as String),
                  List<String>.from(data['locales'] as List));
              result = {'ok': true};
            case '/api/validate':
              result = {
                'errors': content.validate(
                    parsePlatforms(data['platform'] as String),
                    scope: data['scope'] as String? ?? 'all')
              };
            case '/api/credential':
              final file = Credentials(project).import(
                  data['platform'] as String, data['contents'] as String,
                  profile: data['profile'] as String?);
              result = {'ok': true, 'path': file.path};
            case '/api/image':
              final platform = data['platform'] as String,
                  locale = data['locale'] as String,
                  group = data['group'] as String;
              content.images(platform, locale, group);
              final name = p
                  .basename(data['name'] as String)
                  .replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
              final relative = '$platform/images/$locale/$group/$name';
              final file = content.safeAsset(relative);
              if (file.existsSync()) {
                throw StateError(
                    'Image exists; delete or rename it before importing.');
              }
              final bytes = base64Decode(data['bytes'] as String);
              final temp =
                  Directory.systemTemp.createTempSync('torchinlane-image-');
              try {
                final candidate = File('${temp.path}/$name')
                  ..writeAsBytesSync(bytes);
                final issue =
                    StoreContent.validateImage(candidate, platform, group);
                if (issue != null) throw ArgumentError(issue);
                file.parent.createSync(recursive: true);
                candidate.copySync(file.path);
              } finally {
                temp.deleteSync(recursive: true);
              }
              result = {'ok': true};
            case '/api/delete-image':
              final relative = data['path'] as String;
              if (!RegExp(
                      r'^(ios|android)/images/[^/]+/[^/]+/[^/]+\.(png|jpg|jpeg)$',
                      caseSensitive: false)
                  .hasMatch(relative)) {
                throw ArgumentError('Not an image path');
              }
              content.safeAsset(relative).deleteSync();
              result = {'ok': true};
            case '/api/reorder':
              final platform = data['platform'] as String,
                  locale = data['locale'] as String,
                  group = data['group'] as String;
              final files = content.imageFiles(platform, locale, group);
              final ordered = List<String>.from(data['paths'] as List);
              final expected = files
                  .map((f) => p.relative(f.path, from: content.directory.path))
                  .toSet();
              if (ordered.toSet().length != ordered.length ||
                  ordered.length != expected.length ||
                  !expected.containsAll(ordered)) {
                throw ArgumentError(
                    'Reorder must include each existing image exactly once');
              }
              final temp =
                  Directory.systemTemp.createTempSync('torchinlane-order-');
              try {
                for (var i = 0; i < ordered.length; i++) {
                  content
                      .safeAsset(ordered[i])
                      .copySync('${temp.path}/$i${p.extension(ordered[i])}');
                }
                for (final f in files) {
                  f.deleteSync();
                }
                for (var i = 0; i < ordered.length; i++) {
                  File('${temp.path}/$i${p.extension(ordered[i])}').copySync(
                      '${content.images(platform, locale, group).path}/${i.toString().padLeft(3, '0')}_image${p.extension(ordered[i])}');
                }
              } finally {
                temp.deleteSync(recursive: true);
              }
              result = {'ok': true};
            case '/api/job':
              _startJob(data);
              result = {'ok': true};
            default:
              response.statusCode = 404;
              result = {'error': 'Unknown operation'};
          }
        } finally {
          _writing = false;
        }
      } else {
        response.statusCode = 404;
        result = {'error': 'Unknown endpoint'};
      }
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(result));
    } catch (e) {
      if (response.statusCode == 200) response.statusCode = 400;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await response.close();
    }
  }

  void _setup(Map<String, dynamic> data) {
    final previous = project.torchinlaneConfigFile.existsSync()
        ? TorchinlaneConfig.load(project.torchinlaneConfigFile)
        : null;
    final app = (data['app_name'] as String? ?? '').trim();
    if (app.isEmpty) throw ArgumentError('App name required');
    final ios = IosConfig(
        bundleId: data['bundle_id'] as String? ?? '',
        teamId: data['team_id'] as String? ?? '',
        itcTeamId: previous?.ios.itcTeamId ?? data['team_id'] as String? ?? '',
        appleId: data['apple_id'] as String? ?? '',
        ascKeyId: data['asc_key_id'] as String? ?? '',
        ascIssuerId: data['asc_issuer_id'] as String? ?? '',
        ascKeyPath: previous?.ios.ascKeyPath ?? 'ios/fastlane/api_key.p8',
        firebaseCrashlytics: previous?.ios.firebaseCrashlytics ?? false,
        firebaseAppId: previous?.ios.firebaseAppId ?? '');
    final android = AndroidConfig(
        packageName: data['package_name'] as String? ?? '',
        serviceAccountJson: previous?.android.serviceAccountJson ??
            'android/fastlane/fastlane-service-account.json',
        firebaseAppId: previous?.android.firebaseAppId ?? '');
    final source = data['source_locale'] as String? ?? 'en';
    if (storeLocale('ios', source) == null &&
        storeLocale('android', source) == null) {
      throw ArgumentError('Unsupported source locale');
    }
    final scaffolder = FastlaneScaffolder(project);
    if (previous == null) {
      scaffolder.scaffold(
          appName: app, ios: ios, android: android, sourceLocale: source);
    } else {
      final file = project.torchinlaneConfigFile;
      final editor = YamlEditor(file.readAsStringSync());
      editor.update(['app_name'], app);
      for (final key in [
        'bundle_id',
        'team_id',
        'apple_id',
        'asc_key_id',
        'asc_issuer_id'
      ]) {
        editor.update(['ios', key], data[key] ?? '');
      }
      editor.update(['android', 'package_name'], android.packageName);
      editor.update(['changelogs', 'source_locale'], source);
      if (editor.toString() != file.readAsStringSync()) {
        file.copySync('${file.path}.bak');
        file.writeAsStringSync(editor.toString());
      }
      Credentials(project).sync();
    }
    content.initialize(['ios', 'android'], [source]);
  }

  void _startJob(Map<String, dynamic> data) {
    if (![
      'push',
      'pull',
      'verify',
      'translate',
      'deploy',
      'tools',
      'check-tools',
      'export'
    ].contains(data['action'])) {
      throw ArgumentError('Unknown job');
    }
    final platforms =
        parsePlatforms(data['platform'] as String? ?? 'ios,android');
    final action = data['action'] as String;
    job['running'] = true;
    job['exitCode'] = null;
    (job['logs'] as List).clear();
    void log(String text) {
      final logs = job['logs'] as List;
      logs.add(text);
      if (logs.length > 2000) logs.removeAt(0);
    }

    unawaited(() async {
      var code = 1;
      try {
        final service = StoreService(project, log: log);
        switch (action) {
          case 'export':
            final target = Directory(
                '${project.root.path}/build/torchinlane-export-${DateTime.now().millisecondsSinceEpoch}');
            content.exportTo(target, platforms,
                scope: data['scope'] as String? ?? 'all',
                versionCode: _optional(data['versionCode']));
            log('Exported Fastlane files: ${target.path}');
            code = 0;
          case 'check-tools':
            code = await _checkTools(platforms, log);
          case 'verify':
            var failed = false;
            for (final platform in platforms) {
              _verified.remove(platform);
              final identity = readiness.verificationIdentity(platform);
              final result = await service.verify([platform]);
              if (result == 0 &&
                  identity == readiness.verificationIdentity(platform)) {
                _verified[platform] = identity;
              } else {
                failed = true;
              }
            }
            code = failed ? 1 : 0;
          case 'push':
            code = await service.push(platforms,
                scope: data['scope'] as String? ?? 'all',
                track: data['track'] as String? ?? 'internal',
                versionCode: _optional(data['versionCode']),
                appVersion: _optional(data['appVersion']),
                dryRun: data['dryRun'] == true,
                replaceImages: data['replaceImages'] == true);
          case 'pull':
            code = await service.pull(platforms,
                apply: data['apply'] == true,
                appVersion: _optional(data['appVersion']));
          case 'translate':
            final translator = StoreTranslator();
            var failed = false;
            try {
              for (final platform in platforms) {
                final from =
                    storeLocale(platform, data['from'] as String? ?? 'en');
                if (from == null) {
                  throw ArgumentError('Unsupported translation source');
                }
                final fields = content.read(platform, from);
                if (fields.values.every((s) => s.trim().isEmpty)) {
                  throw StateError('Source metadata is empty');
                }
                for (final locale
                    in content.locales(platform).where((l) => l != from)) {
                  final existing = content.read(platform, locale);
                  final pending = {
                    for (final e in fields.entries)
                      if (data['overwrite'] == true ||
                          (existing[e.key] ?? '').trim().isEmpty)
                        e.key: e.value
                  };
                  try {
                    final translated = await translator.translate(
                        platform, from, locale, pending);
                    if (translated.isNotEmpty) {
                      content.write(
                          platform, locale, {...existing, ...translated});
                    }
                    log('$platform/$locale: ${translated.length} fields translated');
                  } catch (e) {
                    failed = true;
                    log('$platform/$locale: $e');
                  }
                }
              }
            } finally {
              translator.close();
            }
            code = failed ? 1 : 0;
          case 'deploy':
          case 'tools':
            final args = action == 'tools'
                ? [
                    'doctor',
                    '--fix',
                    '--tools-only',
                    '--platform',
                    platforms.join(',')
                  ]
                : [
                    'deploy',
                    '--platform',
                    platforms.join(','),
                    '--target',
                    data['target'] == 'production' ? 'production' : 'internal',
                    if (data['uploadOnly'] == true) '--upload-only',
                    if (data['withStore'] == true) '--with-store',
                    if (data['dryRun'] == true) '--dry-run'
                  ];
            final proc = await Process.start(
                Platform.resolvedExecutable,
                [
                  if (p.normalize(Platform.resolvedExecutable) !=
                      p.normalize(Platform.script.toFilePath()))
                    Platform.script.toFilePath(),
                  ...args
                ],
                workingDirectory: project.root.path,
                environment: {
                  ...Platform.environment,
                  'CI': 'true',
                  'TORCHINLANE_SKIP_VERSION_CHECK': '1'
                });
            final out = proc.stdout
                .transform(utf8.decoder)
                .transform(const LineSplitter())
                .forEach(log);
            final err = proc.stderr
                .transform(utf8.decoder)
                .transform(const LineSplitter())
                .forEach(log);
            code = await proc.exitCode;
            await Future.wait([out, err]);
            if (action == 'tools') code = await _checkTools(platforms, log);
        }
      } catch (e) {
        log(e.toString());
      } finally {
        job['exitCode'] = code;
        job['running'] = false;
        log(code == 0 ? 'Completed.' : 'Failed. Review the log and retry.');
      }
    }());
  }

  String? _savedLanguage() {
    try {
      final data = jsonDecode(preferencesFile.readAsStringSync());
      return data is Map && ['tr', 'en'].contains(data['language'])
          ? data['language'] as String
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<int> _checkTools(
      List<String> platforms, void Function(String) log) async {
    final env = const Toolchain().augmentedEnvironment(
        {'FASTLANE_SKIP_UPDATE_CHECK': '1', 'CI': 'true'});
    final commands = <String, List<String>>{
      'flutter': ['--version'],
      'ruby': ['--version'],
      'fastlane': ['--version'],
      if (platforms.contains('ios') && Platform.isMacOS) 'pod': ['--version'],
      if (platforms.contains('ios') && Platform.isMacOS)
        'xcodebuild': ['-version'],
    };
    var failed = platforms.contains('ios') && !Platform.isMacOS;
    if (platforms.contains('ios') && !Platform.isMacOS) {
      _tools['xcodebuild'] = {
        'ok': false,
        'message': 'iOS build için macOS gerekir.'
      };
    }
    await Future.wait(commands.entries.map((entry) async {
      Process? process;
      var ok = false;
      try {
        process = await Process.start(entry.key, entry.value, environment: env);
        final out = process.stdout.drain<void>();
        final err = process.stderr.drain<void>();
        ok = await process.exitCode.timeout(const Duration(seconds: 30)) == 0;
        await Future.wait([out, err]);
      } catch (_) {
        process?.kill();
      }
      _tools[entry.key] = {'ok': ok};
      failed |= !ok;
      log('${entry.key}: ${ok ? 'hazır' : 'bulunamadı veya çalışmıyor'}');
    }));
    return failed ? 1 : 0;
  }

  String? _optional(dynamic value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}
