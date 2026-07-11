import 'package:test/test.dart';
import 'package:torchinlane/src/scaffold/templates.dart';

void main() {
  test('renderTemplate replaces placeholders', () {
    final out = renderTemplate('app_identifier("{{bundle_id}}")', {'bundle_id': 'com.example.app'});
    expect(out, 'app_identifier("com.example.app")');
  });

  test('renderTemplate keeps conditional block when flag true', () {
    const tpl = 'before\n{{#firebase}}\nfirebase-line\n{{/firebase}}\nafter';
    final out = renderTemplate(tpl, {}, flags: {'firebase': true});
    expect(out, contains('firebase-line'));
  });

  test('renderTemplate strips conditional block when flag false', () {
    const tpl = 'before\n{{#firebase}}\nfirebase-line\n{{/firebase}}\nafter';
    final out = renderTemplate(tpl, {}, flags: {'firebase': false});
    expect(out, isNot(contains('firebase-line')));
  });

  test('iosFastfileTemplate renders without leftover placeholders', () {
    final out = renderTemplate(
      iosFastfileTemplate,
      {'asc_key_id': 'KEY123', 'asc_issuer_id': 'ISSUER123', 'source_locale': 'en'},
      flags: {'firebase': true},
    );
    expect(out, isNot(contains('{{')));
    expect(out, contains('KEY123'));
    expect(out, contains('upload_dsyms_to_crashlytics'));
  });
}
