import 'dart:io';
import 'package:torchinlane/src/config/torchinlane_config.dart';
import 'package:torchinlane/src/project/flutter_project.dart';
import 'package:torchinlane/src/scaffold/fastlane_scaffolder.dart';

FlutterProject createTestProject() {
  final root = Directory.systemTemp.createTempSync('torchinlane-test-');
  Directory('${root.path}/ios').createSync();
  Directory('${root.path}/android').createSync();
  File('${root.path}/pubspec.yaml')
      .writeAsStringSync('name: test_app\nversion: 1.2.0+42\n');
  final project = FlutterProject(root);
  FastlaneScaffolder(project).scaffold(
      appName: 'Test App',
      ios: IosConfig(
          bundleId: 'com.example.test',
          teamId: 'TEAM123',
          itcTeamId: '123456',
          appleId: 'dev@example.com',
          ascKeyId: 'KEY123',
          ascIssuerId: 'issuer',
          ascKeyPath: 'keys/apple.p8',
          firebaseCrashlytics: false),
      android: AndroidConfig(
          packageName: 'com.example.test',
          serviceAccountJson: 'keys/google.json'),
      sourceLocale: 'en');
  return project;
}
