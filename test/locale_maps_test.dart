import 'package:test/test.dart';
import 'package:torchinlane/src/changelog/locale_maps.dart';

void main() {
  test('googlePlayLocaleMap has 32 locales', () {
    expect(googlePlayLocaleMap.length, 32);
    expect(googlePlayLocaleMap['tr'], 'tr-TR');
    expect(googlePlayLocaleMap['en'], 'en-US');
  });

  test('appStoreLocaleMap has 32 locales, fa is null (unsupported)', () {
    expect(appStoreLocaleMap.length, 32);
    expect(appStoreLocaleMap['fa'], isNull);
    expect(appStoreLocaleMap['zh'], 'zh-Hans');
  });
}
