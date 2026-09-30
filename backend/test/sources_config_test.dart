import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kamubul_backend/src/config.dart';
import 'package:kamubul_backend/src/sources.dart';
import 'package:kamubul_core/kamubul_core.dart';
import 'package:test/test.dart';

final _now = DateTime(2026, 9, 29, 13);

ProbeSource _probe(MockClientHandler handler) => ProbeSource(
  id: 'iskur',
  name: 'İŞKUR',
  url: Uri.parse('https://esube.iskur.gov.tr/'),
  client: MockClient(handler),
);

void main() {
  group('ProbeSource', () {
    test('WAF reddi ve 403 engel olarak kaydedilir', () async {
      final waf = await _probe(
        (_) async => http.Response('<html>Request Rejected</html>', 200),
      ).run(_now, null);
      expect(waf.status.state, SourceState.blocked);
      final forbidden = await _probe((_) async => http.Response('yok', 403))
          .run(_now, null);
      expect(forbidden.status.state, SourceState.blocked);
      expect(forbidden.listings, isEmpty);
    });

    test(
      'erişilebilir ana sayfa "ayrıştırıcı yok" olarak dürüstçe kaydedilir',
      () async {
        final ok = await _probe(
          (_) async => http.Response('<html>Merhaba</html>', 200),
        ).run(_now, null);
        expect(ok.status.state, SourceState.disabled);
        expect(ok.status.note, contains('ayrıştırıcısı henüz yok'));
      },
    );

    test('ağ hatası failed olur ve önceki başarı zamanı korunur', () async {
      final previous = SourceStatus(
        id: 'iskur',
        name: 'İŞKUR',
        state: SourceState.ok,
        lastSuccessAt: DateTime(2026, 9, 1),
      );
      final result = await _probe((_) async => throw http.ClientException('ağ'))
          .run(_now, previous);
      expect(result.status.state, SourceState.failed);
      expect(result.status.lastSuccessAt, DateTime(2026, 9, 1));
    });
  });

  group('Kariyer/SBB adaptörleri', () {
    test('başarı kayıt üretir; hata önceki başarıyı korur', () async {
      final ok = await KariyerSource(
        loader: () async => [
          PublicListing(
            title: 'KURUM - İlan',
            category: 'Personel',
            url: Uri.parse('https://kariyerkapisi.gov.tr/IlanDetay?i=1'),
            publishedAt: DateTime(2026, 9, 28),
          ),
        ],
      ).run(_now, null);
      expect(ok.status.state, SourceState.ok);
      expect(ok.listings.single.sourceId, kKariyerSourceId);

      final previous = ok.status;
      final failed = await SbbSource(
        loader: () async => throw const FormatException('düzen değişti'),
      ).run(_now.add(const Duration(hours: 5)), previous);
      expect(failed.status.state, SourceState.failed);
      expect(failed.status.note, contains('düzen değişti'));
    });
  });

  group('BackendConfig', () {
    test('varsayılanlar taşınabilir dosya + günlük push', () {
      final config = BackendConfig.fromEnv({});
      expect(config.storage, 'file');
      expect(config.push, 'log');
      expect(config.llm, isNull);
      expect(config.port, 8080);
      expect(config.scheduleTimes, isEmpty);
    });

    test('Google yapılandırması proje gerektirir', () {
      expect(
        () => BackendConfig.fromEnv({'STORAGE': 'firestore'}),
        throwsArgumentError,
      );
      expect(() => BackendConfig.fromEnv({'PUSH': 'fcm'}), throwsArgumentError);
      final config = BackendConfig.fromEnv({
        'STORAGE': 'firestore',
        'PUSH': 'fcm',
        'GCP_PROJECT': 'p',
        'PORT': '9000',
      });
      expect(config.gcpProject, 'p');
      expect(config.port, 9000);
      expect(
        () => BackendConfig.fromEnv({'STORAGE': 'redis'}),
        throwsArgumentError,
      );
    });

    test('AI ve zamanlama ayarları doğrulanır', () {
      final config = BackendConfig.fromEnv({
        'AI_PROVIDER': 'anthropic',
        'AI_MODEL': 'claude-opus-5-5',
        'AI_API_KEY': 'k',
        'AI_FIELDS': 'maxAge, education, uydurma',
        'AI_SUMMARY': '1',
        'SCHEDULE_TIMES': '08:00, 13:00,25:00,18:00',
      });
      expect(config.llm!.provider, 'anthropic');
      expect(config.aiPolicy.enabledFields, {'maxAge', 'education'});
      expect(config.aiPolicy.summaryEnabled, isTrue);
      expect(config.scheduleTimes, ['08:00', '13:00', '18:00']);
      expect(
        () => BackendConfig.fromEnv({
          'AI_PROVIDER': 'anthropic',
          'AI_MODEL': 'm',
        }),
        throwsArgumentError,
      );
    });
  });
}
