import 'package:test/test.dart';
import 'package:torchinlane/src/changelog/locale_maps.dart';

void main() {
  test('every native locale resolves to itself for its store', () {
    for (final code in appleStoreLocales) {
      expect(storeLocale('ios', code), code);
    }
    for (final code in googleStoreLocales) {
      expect(storeLocale('android', code), code);
    }
  });
  test('legacy codes resolve to corrected official store codes', () {
    expect(storeLocale('ios', 'bn'), 'bn-BD');
    expect(storeLocale('android', 'he'), 'iw-IL');
    expect(storeLocale('ios', 'tl'), isNull);
    expect(storeLocale('android', 'tl'), 'fil');
    expect(storeLocale('ios', 'fa'), isNull);
    expect(storeLocale('android', 'fa'), 'fa');
    expect(storeLocale('ios', 'tr-TR'), 'tr');
  });
  test('regional variants are distinct and unknown languages are rejected', () {
    expect(storeLocale('ios', 'pt-PT'), 'pt-PT');
    expect(storeLocale('ios', 'zh-Hant'), 'zh-Hant');
    expect(storeLocale('ios', 'en-GB'), 'en-GB');
    expect(storeLocale('android', 'es-419'), 'es-419');
    expect(storeLocale('ios', '../../secrets'), isNull);
    expect(() => parsePlatforms('android,unknown'), throwsArgumentError);
  });
}
