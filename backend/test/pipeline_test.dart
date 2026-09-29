import 'dart:convert';
import 'dart:io';

import 'package:kamubul_backend/src/file_storage.dart';
import 'package:kamubul_backend/src/pipeline.dart';
import 'package:kamubul_backend/src/push.dart';
import 'package:kamubul_backend/src/sources.dart';
import 'package:kamubul_core/kamubul_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

const _u1 = 'https://kariyerkapisi.gov.tr/IlanDetay?i=1';
const _u2 = 'https://kariyerkapisi.gov.tr/IlanDetay?i=2';
const _u3 = 'https://kariyerkapisi.gov.tr/IlanDetay?i=3';
const _u4 = 'https://kariyerkapisi.gov.tr/IlanDetay?i=4';

class _Source implements SourceAdapter {
  _Source(this.records);
  List<ListingRecord> records;
  bool fail = false;

  @override
  String get id => kKariyerSourceId;
  @override
  String get name => 'Kariyer Kapısı';
  @override
  bool get providesListings => true;

  @override
  Future<SourceOutcome> run(DateTime now, SourceStatus? previous) async {
    if (fail) {
      return SourceOutcome(
        SourceStatus(
          id: id,
          name: name,
          state: SourceState.failed,
          lastAttemptAt: now,
          lastSuccessAt: previous?.lastSuccessAt,
          note: 'kapalı',
        ),
      );
    }
    return SourceOutcome(
      SourceStatus(
        id: id,
        name: name,
        state: SourceState.ok,
        lastAttemptAt: now,
        lastSuccessAt: now,
        listingCount: records.length,
      ),
      records,
    );
  }
}

class _Push implements PushSender {
  final sent = <PushMessage>[];
  PushOutcome Function(PushMessage) outcome = (_) => PushOutcome.sent;

  @override
  Future<PushOutcome> send(PushMessage message) async {
    final result = outcome(message);
    if (result == PushOutcome.sent) sent.add(message);
    return result;
  }
}

class _Llm implements LlmClient {
  _Llm(this.handler);
  final String Function(String user) handler;
  @override
  String get provider => 'sahte';
  @override
  String get model => 'sahte';
  @override
  Future<LlmResponse> complete(LlmRequest request) async => LlmResponse(
    text: handler(request.user),
    inputTokens: 100,
    outputTokens: 50,
    model: 'sahte',
  );
}

KariyerDetail _detail(
  List<String> places, {
  String body = 'Başvuru tarihi itibarıyla 35 yaşını doldurmamış olmak.',
}) => KariyerDetail(
  institution: 'KURUM',
  body: body,
  start: null,
  deadline: DateTime(2026, 10, 12, 23, 59),
  applyUrl: null,
  positions: [
    KariyerPosition(
      title: 'Memur',
      profession: 'Genel',
      conditions: 'Lisans mezunu olmak.',
      quota: 2,
      places: places,
    ),
  ],
);

void main() {
  late Directory dir;
  late FileStorage storage;
  late _Push push;
  late _Source source;
  late Map<String, KariyerDetail> details;
  var clockUtc = DateTime.utc(2026, 9, 29, 10); // Türkiye 13:00

  ListingRecord fresh(String url, String title) => listing(url, title: title);

  PipelineDeps deps({AiEnricher? enricher}) => PipelineDeps(
    storage: storage,
    sources: [source],
    push: push,
    detailLoader: (uri) async {
      final detail = details[uri.toString()];
      if (detail == null) throw const FormatException('ayrıntı yok');
      return detail;
    },
    enricher: enricher,
    delay: (_) async {},
    clock: () => clockUtc,
  );

  Future<CatalogueSnapshot> snapshot() async =>
      CatalogueSnapshot.decode((await storage.readSnapshot())!);

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('kamubul_pipe_');
    storage = FileStorage(dir.path);
    push = _Push();
    clockUtc = DateTime.utc(2026, 9, 29, 10);
    source = _Source([
      fresh(_u1, 'ANKARA KURUMU - Memur'),
      fresh(_u2, 'İZMİR KURUMU - Memur'),
      fresh(_u3, 'BURSA KURUMU - Memur'),
    ]);
    details = {
      _u1: _detail(['ANKARA']),
      _u2: _detail(['İZMİR']),
      // _u3 için ayrıntı yok: okunamaz.
    };
    await storage.putDevice(deviceRecord());
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('ilk çalışma: birleştirir, ayrıntı ve şartları işler, anlık görüntüyü yazar, eşleşene bildirir', () async {
    final report = await runPipeline(deps());
    expect(report.added, 3);
    expect(report.total, 3);
    expect(report.detailFetched, 2);
    expect(report.detailFailed, 1);
    final snap = await snapshot();
    final u1 = snap.listings.firstWhere((r) => r.url == _u1);
    expect(u1.places, ['ANKARA']);
    expect(u1.quota, 2);
    expect(u1.maxAge, 35);
    expect(u1.maxAgeQuote, contains('35 yaşını'));
    expect(snap.sources.single.state, SourceState.ok);
    // Yalnızca Ankara etiketine uyan ilan için bildirim.
    expect(push.sent.map((m) => m.url), [_u1]);
    expect(report.pushSent, 1);
    final state = (await storage.readState())!;
    expect(state['pendingPush'], isEmpty);
  });

  test('ikinci çalışma aynı ilanı tekrar bildirmez; okunamayan ayrıntı 3 denemede bırakılır', () async {
    await runPipeline(deps());
    push.sent.clear();
    final second = await runPipeline(deps());
    expect(second.added, 0);
    expect(push.sent, isEmpty);
    expect(second.detailFailed, 1); // _u3 yeniden denendi
    final third = await runPipeline(deps());
    expect(third.detailFailed, 1);
    final fourth = await runPipeline(deps());
    expect(fourth.detailFailed, 0); // 3 başarısızlıktan sonra bırakıldı
  });

  test('yeni ilan gelince yalnızca o bildirilir', () async {
    await runPipeline(deps());
    push.sent.clear();
    source.records = [
      ...source.records,
      fresh(_u4, 'ANKARA BAŞKA KURUM - Memur'),
    ];
    details[_u4] = _detail(['ANKARA']);
    final report = await runPipeline(deps());
    expect(report.added, 1);
    expect(push.sent.map((m) => m.url), [_u4]);
  });

  test(
    'kaynak düşerse önceki liste ve son başarı zamanı korunur, bildirim yok',
    () async {
      await runPipeline(deps());
      push.sent.clear();
      source.fail = true;
      clockUtc = DateTime.utc(2026, 9, 29, 15);
      final report = await runPipeline(deps());
      expect(report.sourcesFailed, 1);
      expect(report.total, 3);
      final snap = await snapshot();
      expect(snap.listings, hasLength(3));
      expect(snap.sources.single.state, SourceState.failed);
      expect(snap.sources.single.lastSuccessAt, DateTime(2026, 9, 29, 13));
      expect(push.sent, isEmpty);
    },
  );

  test('geçersiz FCM jetonu cihaz kaydını siler', () async {
    push.outcome = (_) => PushOutcome.invalidToken;
    final report = await runPipeline(deps());
    expect(report.devicesRemoved, 1);
    expect(await storage.getDevice(deviceId), isNull);
  });

  test(
    'geçici gönderim hatasında bildirim kuyruğa döner, sayaç artmaz',
    () async {
      push.outcome = (_) => PushOutcome.failed;
      final report = await runPipeline(deps());
      expect(report.pushRequeued, 1);
      final device = (await storage.getDevice(deviceId))!;
      expect(device.state.queue.single.listingUrl, _u1);
      expect(device.state.instantSentToday, 0);
      // Sonraki çalışmada (yeni ilan olmasa da) kuyruk boşalır.
      push.outcome = (_) => PushOutcome.sent;
      clockUtc = DateTime.utc(2026, 9, 29, 15);
      await runPipeline(deps());
      expect(push.sent.map((m) => m.url), [_u1]);
      expect((await storage.getDevice(deviceId))!.state.queue, isEmpty);
    },
  );

  test('sessiz saatte gönderilmez, sabah kuyruktan gönderilir', () async {
    clockUtc = DateTime.utc(2026, 9, 29, 20); // Türkiye 23:00
    await runPipeline(deps());
    expect(push.sent, isEmpty);
    expect((await storage.getDevice(deviceId))!.state.queue, hasLength(1));
    clockUtc = DateTime.utc(2026, 9, 30, 6); // Türkiye 09:00
    await runPipeline(deps());
    expect(push.sent.map((m) => m.url), [_u1]);
  });

  test('çökme kurtarma: durumdaki bekleyen bildirim bir sonraki çalışmada gönderilir', () async {
    final first = await runPipeline(deps());
    expect(first.pushSent, 1);
    push.sent.clear();
    final state = (await storage.readState())!;
    state['pendingPush'] = [_u1];
    await storage.writeState(state);
    await runPipeline(deps());
    expect(push.sent.map((m) => m.url), [_u1]);
    expect(((await storage.readState())!['pendingPush'] as List), isEmpty);
  });

  test('120 günden eski cihaz kaydı temizlenir', () async {
    await storage.putDevice(
      deviceRecord(id: 'b' * 32, updatedAt: DateTime.utc(2026, 5, 1)),
    );
    final report = await runPipeline(deps());
    expect(report.devicesRemoved, 1);
    expect(await storage.getDevice('b' * 32), isNull);
    expect(await storage.getDevice(deviceId), isNotNull);
  });

  test('yapay zekâ özeti doğrulanmış alıntıyla kayda girer; hata yeniden deneme sayar', () async {
    details[_u1] = _detail(
      ['ANKARA'],
      body: 'Adaylar kamu haklarından mahrum olmamalıdır. Başvuru tarihi itibarıyla 35 yaşını doldurmamış olmak.',
    );
    final enricher = AiEnricher(
      client: _Llm(
        (_) => jsonEncode({
          'summary': [
            {
              'text': 'Yaş sınırı 35',
              'quote': 'Başvuru tarihi itibarıyla 35 yaşını doldurmamış olmak.',
            },
            {'text': 'Maaş yüksek', 'quote': 'Maaş çok yüksektir ve ödenir.'},
          ],
        }),
      ),
      policy: const AiEnrichmentPolicy(summaryEnabled: true),
      budget: TokenBudget(100000),
    );
    final report = await runPipeline(deps(enricher: enricher));
    expect(report.aiEnriched, greaterThan(0));
    final u1 = (await snapshot()).listings.firstWhere((r) => r.url == _u1);
    expect(u1.summary, ['Yaş sınırı 35']);

    // AI hatası: ilan ayrıntısı alınır, AI yeniden deneme listesine girer.
    await storage.writeState({});
    await storage.writeSnapshot(
      CatalogueSnapshot(
        generatedAt: DateTime(2026, 9, 29),
        sources: const [],
        listings: const [],
      ).encode(),
    );
    final failing = AiEnricher(
      client: _FailingLlm(),
      policy: const AiEnrichmentPolicy(summaryEnabled: true),
      budget: TokenBudget(100000),
    );
    await runPipeline(deps(enricher: failing));
    final retry = (await storage.readState())!['aiRetry'] as Map;
    expect(retry[_u1], 1);
  });

  test(
    'yapay zekâ kapalıyken (enricher yok) akış deterministik çalışır',
    () async {
      final report = await runPipeline(deps());
      expect(report.aiEnriched, 0);
      expect(
        (await snapshot()).listings.every((r) => r.summary.isEmpty),
        isTrue,
      );
    },
  );
}

class _FailingLlm implements LlmClient {
  @override
  String get provider => 'sahte';
  @override
  String get model => 'sahte';
  @override
  Future<LlmResponse> complete(LlmRequest request) =>
      throw const LlmException('kapalı', statusCode: 503);
}
