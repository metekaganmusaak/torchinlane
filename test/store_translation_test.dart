import 'dart:convert';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:torchinlane/src/store/translation.dart';

void main() {
  test('translation schema and request contain only translatable fields',
      () async {
    final translator = StoreTranslator(
        apiKey: 'test',
        client: MockClient((request) async {
          final body = jsonDecode(request.body);
          expect(
              body['output_config']['format']['schema']['required'], ['title']);
          expect(body['messages'][0]['content'],
              isNot(contains('https://private.example')));
          return http.Response(
              jsonEncode({
                'content': [
                  {'type': 'text', 'text': '{"title":"Uygulama"}'}
                ],
                'stop_reason': 'end_turn'
              }),
              200);
        }));
    expect(
        await translator.translate('android', 'en-US', 'tr-TR',
            {'title': 'App', 'video': 'https://private.example'}),
        {'title': 'Uygulama'});
    translator.close();
  });
  test('incomplete or over-limit output fails before any file write', () async {
    for (final text in [
      '{}',
      jsonEncode({'title': 'x' * 31})
    ]) {
      final translator = StoreTranslator(
          apiKey: 'test',
          client: MockClient((_) async => http.Response(
              jsonEncode({
                'content': [
                  {'type': 'text', 'text': text}
                ],
                'stop_reason': 'end_turn'
              }),
              200)));
      await expectLater(
          translator.translate('android', 'en-US', 'tr-TR', {'title': 'App'}),
          throwsStateError);
      translator.close();
    }
  });
  test('API failures do not expose response bodies with possible credentials',
      () async {
    final translator = StoreTranslator(
        apiKey: 'test',
        client: MockClient((_) async => http.Response('SECRET', 401)));
    try {
      await translator.translate('ios', 'en-US', 'tr', {'name': 'App'});
      fail('Expected failure');
    } catch (e) {
      expect(e.toString(), isNot(contains('SECRET')));
    }
    translator.close();
  });
}
