import 'dart:io';

import 'package:test/test.dart';
import 'package:torchinlane/src/config/torchinlane_config.dart';

void main() {
  test('render then load round-trips correctly', () {
    final yaml = TorchinlaneConfig.render(
      appName: 'TestApp',
      ios: IosConfig(
        bundleId: 'com.example.app',
        teamId: 'TEAM123',
        itcTeamId: 'TEAM123',
        appleId: 'dev@example.com',
        ascKeyId: 'KEY123',
        ascIssuerId: 'ISSUER123',
        ascKeyPath: 'ios/api_key.p8',
        firebaseCrashlytics: true,
      ),
      android: AndroidConfig(
        packageName: 'com.example.app',
        serviceAccountJson: 'android/fastlane/fastlane-service-account.json',
      ),
      changelogsDir: 'changelogs',
      sourceLocale: 'en',
    );

    final tempFile = File('${Directory.systemTemp.path}/torchinlane_test_config.yaml');
    tempFile.writeAsStringSync(yaml);

    final config = TorchinlaneConfig.load(tempFile);
    expect(config.appName, 'TestApp');
    expect(config.ios.bundleId, 'com.example.app');
    expect(config.ios.firebaseCrashlytics, true);
    expect(config.android.packageName, 'com.example.app');
    expect(config.changelogs.sourceLocale, 'en');
    expect(config.changelogs.locales.length, 32);

    tempFile.deleteSync();
  });
}
