import 'package:test/test.dart';
import 'package:torchinlane/src/changelog/locale_maps.dart';
import 'package:torchinlane/src/config/torchinlane_config.dart';
import 'package:torchinlane/src/store/service.dart';

void main() {
  test('default changelog folders use store listing language codes', () {
    expect(defaultLocales.where((l) => !listingLanguages.containsKey(l)),
        isEmpty);
  });
  test('old fastlane is stopped only when newer Apple locales are uploaded',
      () {
    expect(fastlaneLocaleError('2.230.0', ['en-US', 'de-DE']), isNull);
    expect(fastlaneLocaleError('2.230.0', ['en-US', 'kn-IN', 'bn-BD']),
        contains('cannot upload Apple locales bn-BD, kn-IN'));
    expect(fastlaneLocaleError('2.234.0', ['kn-IN']), isNull);
    expect(fastlaneLocaleError('3.0.0', ['kn-IN']), isNull);
  });
}
