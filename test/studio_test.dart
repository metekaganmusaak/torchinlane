import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:torchinlane/src/project/flutter_project.dart';
import 'package:torchinlane/src/studio/server.dart';
import 'test_project.dart';

void main() {
  late FlutterProject project;
  late StudioServer server;
  late Uri uri;
  late HttpClient client;
  setUp(() async {
    project = createTestProject();
    server = StudioServer(project,
        preferencesFile:
            File('${project.root.path}/.torchinlane/test-preferences.json'));
    uri = await server.start();
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await server.close();
    project.root.deleteSync(recursive: true);
  });
  Future<(int, dynamic)> request(String path,
      {Map<String, dynamic>? data, bool token = true, String? origin}) async {
    final req = await client.openUrl(
        data == null ? 'GET' : 'POST', uri.replace(path: path, fragment: ''));
    if (token) req.headers.set('X-Torchinlane-Token', server.token);
    if (origin != null) req.headers.set('origin', origin);
    if (data != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(data));
    }
    final res = await req.close();
    final body = await utf8.decoder.bind(res).join();
    return (
      res.statusCode,
      res.headers.contentType?.mimeType == 'application/json'
          ? jsonDecode(body)
          : body
    );
  }

  test(
      'interface preference persists across server restart without editing project settings',
      () async {
    final before = project.torchinlaneConfigFile.readAsStringSync();
    expect(
        (await request('/api/preferences', data: {'language': 'de'})).$1, 400);
    server.job['running'] = true;
    expect(
        (await request('/api/preferences', data: {'language': 'en'})).$1, 200);
    server.job['running'] = false;
    expect((await request('/api/state')).$2['uiLanguage'], 'en');
    await server.close();
    server = StudioServer(project, preferencesFile: server.preferencesFile);
    uri = await server.start();
    expect((await request('/api/state')).$2['uiLanguage'], 'en');
    expect(project.torchinlaneConfigFile.readAsStringSync(), before);
    expect(
        (await request('/api/preferences',
                data: {'language': 'tr'}, origin: 'https://evil.example'))
            .$1,
        403);
  });
  test(
      'local GUI loads but authenticated API rejects missing token and foreign origins',
      () async {
    expect((await request('/')).$1, 200);
    expect((await request('/api/state', token: false)).$1, 403);
    expect(
        (await request('/api/state', origin: 'https://evil.example')).$1, 403);
    expect((await request('/api/state')).$2['available']['ios'],
        contains('bn-BD'));
  });
  test(
      'wizard reports existing setup, sync is idempotent, malformed config remains visible',
      () async {
    final state = (await request('/api/state')).$2;
    expect(state['readiness']['platforms']['android']['scaffoldReady'], isTrue);
    final helper = File('${project.root.path}/fastlane/StoreHelper.rb');
    final originalTime = helper.lastModifiedSync();
    expect((await request('/api/sync', data: {})).$1, 200);
    expect(helper.lastModifiedSync(), originalTime);
    project.torchinlaneConfigFile.writeAsStringSync('bad: [');
    final malformed = await request('/api/state');
    expect(malformed.$1, 200);
    expect(malformed.$2['readiness']['configError'], isNotNull);
  });
  test(
      'source reuse preserves target fields and rejects incompatible notes atomically',
      () async {
    await request('/api/save', data: {
      'platform': 'ios',
      'locale': 'en-US',
      'fields': {
        'name': 'Source Brand',
        'description': 'Calendar',
        'release_notes': 'ü' * 501
      }
    });
    await request('/api/save', data: {
      'platform': 'android',
      'locale': 'en-US',
      'fields': {'title': 'Existing'}
    });
    final target = File('${project.root.path}/store/android/en-US.json');
    final before = target.readAsStringSync();
    expect(
        (await request('/api/copy-source', data: {'platform': 'android'})).$1,
        400);
    expect(target.readAsStringSync(), before);
    await request('/api/save', data: {
      'platform': 'ios',
      'locale': 'en-US',
      'fields': {
        'name': 'Source Brand',
        'description': 'Calendar',
        'release_notes': 'Fixes'
      }
    });
    expect(
        (await request('/api/copy-source', data: {'platform': 'android'})).$1,
        200);
    expect(jsonDecode(target.readAsStringSync()), {
      'title': 'Existing',
      'full_description': 'Calendar',
      'release_notes': 'Fixes'
    });
    expect(
        (await request('/api/copy-source', data: {'platform': '../../keys'}))
            .$1,
        400);
  });
  test('GUI prepares agent task without credentials and keeps files unchanged',
      () async {
    await request('/api/init', data: {
      'platform': 'android',
      'locales': ['en', 'tr']
    });
    await request('/api/save', data: {
      'platform': 'android',
      'locale': 'en-US',
      'fields': {'title': 'Brand'}
    });
    final file = File('${project.root.path}/store/android/tr-TR.json');
    final before = file.readAsStringSync();
    final result = await request('/api/translation-task',
        data: {'platform': 'android', 'from': 'en-US'});
    expect(result.$1, 200);
    expect(result.$2['prompt'], contains('store/android/tr-TR.json'));
    expect(file.readAsStringSync(), before);
    expect(
        (await request('/api/translation-task',
                data: {'platform': '../ios', 'from': 'en'}))
            .$1,
        400);
  });
  test('GUI creates locale, saves metadata, validates, and runs dry upload job',
      () async {
    expect(
        (await request('/api/init', data: {
          'platform': 'android',
          'locales': ['en']
        }))
            .$1,
        200);
    expect(
        (await request('/api/save', data: {
          'platform': 'android',
          'locale': 'en-US',
          'fields': {'title': 'App', 'release_notes': 'Fixes'}
        }))
            .$1,
        200);
    expect(
        (await request('/api/validate', data: {'platform': 'android'}))
            .$2['errors'],
        isEmpty);
    expect(
        (await request('/api/job', data: {
          'action': 'push',
          'platform': 'android',
          'versionCode': '42',
          'dryRun': true
        }))
            .$1,
        200);
    for (var i = 0; i < 50; i++) {
      if (server.job['running'] == false) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(server.job['exitCode'], 0);
    expect(server.job['logs'].last, 'Completed.');
  });
  test('GUI rejects traversal and overlapping mutating operations', () async {
    expect(
        (await request('/api/save', data: {
          'platform': 'ios',
          'locale': '../../keys',
          'fields': {}
        }))
            .$1,
        400);
    server.job['running'] = true;
    expect(
        (await request('/api/init', data: {
          'platform': 'ios',
          'locales': ['en']
        }))
            .$1,
        409);
    server.job['running'] = false;
  });
  test('setup preserves advanced config and backs up generated files',
      () async {
    final before = project.torchinlaneConfigFile.readAsStringSync();
    expect(
        (await request('/api/setup', data: {
          'app_name': 'Updated: App',
          'bundle_id': 'com.example.new',
          'team_id': 'NEWTEAM',
          'apple_id': 'dev@example.com',
          'asc_key_id': 'NEWKEY',
          'asc_issuer_id': 'newissuer',
          'package_name': 'com.example.new',
          'source_locale': 'tr'
        }))
            .$1,
        200);
    expect(File('${project.torchinlaneConfigFile.path}.bak').readAsStringSync(),
        before);
    expect(project.torchinlaneConfigFile.readAsStringSync(),
        contains('keys/apple.p8'));
  });
}
