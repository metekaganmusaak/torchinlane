import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:torchinlane/src/setup/credentials.dart';
import 'package:torchinlane/src/store/content.dart';
import 'package:torchinlane/src/studio/readiness.dart';
import 'test_project.dart';

void main() {
  test(
      'recognizes existing files without repeating setup or claiming remote access',
      () {
    final project = createTestProject();
    addTearDown(() => project.root.deleteSync(recursive: true));
    Credentials(project).import(
        'android',
        jsonEncode({
          'type': 'service_account',
          'client_email': 'a@example.com',
          'private_key': 'PRIVATE_SECRET'
        }));
    final readiness = StudioReadiness(project, environment: {});
    final state = readiness.snapshot();
    final android = state['platforms']['android'];
    expect(android['configured'], isTrue);
    expect(android['scaffoldReady'], isTrue);
    expect(android['credential'], 'present');
    expect(android['verified'], isFalse);
    expect(jsonEncode(state), isNot(contains('PRIVATE_SECRET')));
    final tools = {
      'fastlane': {'ok': true}
    };
    expect(readiness.snapshot(tools: tools)['tools'], tools);
    final identity = readiness.verificationIdentity('android');
    expect(
        readiness.snapshot(verified: {'android': identity})['platforms']
            ['android']['verified'],
        isTrue);
    File(readiness.credentialPath('android')).writeAsStringSync(jsonEncode({
      'type': 'service_account',
      'client_email': 'b@example.com',
      'private_key': 'CHANGED'
    }));
    expect(
        readiness.snapshot(verified: {'android': identity})['platforms']
            ['android']['verified'],
        isFalse);
  });
  test('detects old scaffold and missing/invalid credentials independently',
      () {
    final project = createTestProject();
    addTearDown(() => project.root.deleteSync(recursive: true));
    final readiness = StudioReadiness(project, environment: {});
    File('${project.root.path}/android/fastlane/Fastfile')
        .writeAsStringSync('old');
    File('${project.root.path}/keys/apple.p8')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('invalid');
    final state = readiness.snapshot()['platforms'];
    expect(state['android']['credential'], 'missing');
    expect(state['ios']['credential'], 'invalid');
    expect(state['android']['outdatedFiles'],
        contains('android/fastlane/Fastfile'));
    expect(state['ios']['scaffoldReady'], isTrue);
  });
  test(
      'counts only missing translations and recognizes optional existing content',
      () {
    final project = createTestProject();
    addTearDown(() => project.root.deleteSync(recursive: true));
    final content = StoreContent(project);
    content.initialize(['android'], ['en', 'tr']);
    content.write('android', 'en-US', {
      'title': 'Brand',
      'short_description': 'Calendar',
      'video': 'https://example.com'
    });
    content.write('android', 'tr-TR', {'title': 'Marka'});
    final readiness = StudioReadiness(project, environment: {});
    var android = readiness.snapshot()['platforms']['android'];
    expect(android['sourceReady'], isTrue);
    expect(android['pendingFields'], 1);
    expect(android['imageCount'], 0);
    expect(android['textIssues'], isEmpty);
    content.write(
        'android', 'tr-TR', {'title': 'Marka', 'short_description': 'Takvim'});
    android = readiness.snapshot()['platforms']['android'];
    expect(android['pendingFields'], 0);
  });
  test('malformed config remains inspectable without leaking parser contents',
      () {
    final project = createTestProject();
    addTearDown(() => project.root.deleteSync(recursive: true));
    project.torchinlaneConfigFile.writeAsStringSync('SECRET_BAD: [');
    final state = StudioReadiness(project, environment: {}).snapshot();
    expect(state['configError'], isNotNull);
    expect(jsonEncode(state), isNot(contains('SECRET_BAD')));
    expect(state['platforms']['android']['configured'], isFalse);
  });
  test(
      'environment credential paths work and invalid JSON does not break readiness',
      () {
    final project = createTestProject();
    addTearDown(() => project.root.deleteSync(recursive: true));
    final key = File('${project.root.path}/external.json')
      ..writeAsStringSync(jsonEncode({
        'type': 'external_account',
        'audience': 'wif',
        'credential_source': {'file': 'token'}
      }));
    final content = StoreContent(project);
    content.initialize(['android'], ['en', 'tr']);
    content.file('android', 'tr-TR').writeAsStringSync('broken JSON');
    final readiness = StudioReadiness(project,
        environment: {'GOOGLE_APPLICATION_CREDENTIALS': key.path});
    final android = readiness.snapshot()['platforms']['android'];
    expect(android['credential'], 'present');
    expect(android['textIssues'], isNotEmpty);
  });
}
