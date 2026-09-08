import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shipglows_email_engine_app/central_email_api.dart';
import 'package:shipglows_email_engine_app/campaign_repository.dart';
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

void main() {
  test('rejects insecure remote origins and credential URLs', () {
    for (final url in [
      'http://example.com',
      'https://user:secret@example.com',
      'https://example.com?token=secret',
    ]) {
      expect(
        () => CentralEmailApi(
          origin: Uri.parse(url),
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
        throwsArgumentError,
      );
    }
  });

  test(
    'uncertain command retry retains its key and does not auto retry',
    () async {
      final requests = <http.Request>[];
      final api = CentralEmailApi(
        origin: Uri.parse('https://example.test'),
        client: MockClient((request) async {
          requests.add(request);
          if (requests.length == 1) {
            throw http.ClientException('sensitive raw response');
          }
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        api.post('campaigns/a/approve', {'expected_version': 2}),
        throwsA(
          isA<EmailApiException>().having(
            (e) => e.code,
            'code',
            'outcome_unknown',
          ),
        ),
      );
      expect(requests, hasLength(1));
      await api.post('campaigns/a/approve', {'expected_version': 2});
      expect(
        requests[0].headers['Idempotency-Key'],
        requests[1].headers['Idempotency-Key'],
      );
      expect(requests[0].followRedirects, isFalse);
      expect(
        requests[0].headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
    },
  );

  test(
    'rejects redirected login and malformed success with safe errors',
    () async {
      for (final status in [302, 200]) {
        final api = CentralEmailApi(
          origin: Uri.parse('https://example.test'),
          client: MockClient(
            (_) async => http.Response('<html>private detail</html>', status),
          ),
        );
        await expectLater(
          api.get('context'),
          throwsA(
            isA<EmailApiException>().having(
              (e) => e.toString(),
              'message',
              isNot(contains('private')),
            ),
          ),
        );
      }
    },
  );

  test('rejects oversized server response', () async {
    final api = CentralEmailApi(
      origin: Uri.parse('https://example.test'),
      client: MockClient(
        (_) async =>
            http.Response('x' * (CentralEmailApi.maxResponseBytes + 1), 200),
      ),
    );
    await expectLater(api.get('context'), throwsA(isA<EmailApiException>()));
  });

  test('serializes draft writes with authoritative server versions', () async {
    var version = 1;
    final expected = <int>[];
    final record = <String, dynamic>{
      'id': 'a',
      'business_id': 'b',
      'title': 'Draft',
      'subject': '',
      'preheader': '',
      'audience_id': 'readers',
      'locale': 'fr',
      'blocks': [],
      'version': version,
      'state': 'draft',
    };
    final api = CentralEmailApi(
      origin: Uri.parse('https://example.test'),
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        expected.add(body['expected_version'] as int);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        version++;
        return http.Response(
          jsonEncode({
            'campaign': {...record, 'version': version},
          }),
          200,
        );
      }),
    );
    final business = EmailBusiness({
      'id': 'b',
      'brand': 'Brand',
      'from': 'sender@example.test',
      'audiences': [
        {'id': 'readers', 'purpose': 'marketing'},
      ],
      'capabilities': {},
    });
    final session = CampaignEditorSession(api, business, record);
    final first = session.draft.copyWith(subject: 'First', revision: 10);
    final second = first.copyWith(subject: 'Second', revision: 11);
    final saves = await Future.wait([
      session.save(first),
      session.save(second),
    ]);
    expect(expected, [1, 2]);
    expect(saves.last.revision, 11);
    expect(saves.last.saveState, NewsletterSaveState.saved);
    expect(session.version, 3);
  });
}
