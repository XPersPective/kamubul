import 'package:kamubul_core/kamubul_core.dart';
import 'package:test/test.dart';

const _text = '''
Başvuru şartları:
Kamu haklarından mahrum bulunmamak.
Başvuru tarihi itibarıyla 35 yaşını doldurmamış olmak.
Lisans mezunu olmak (KPSS P3 puan türünden en az 70 puan almış olmak).
Bu ilan 657 sayılı Kanunun 4/B maddesi kapsamında sözleşmeli personel alımıdır.
''';

const _all = AiEnrichmentPolicy(
  enabledFields: kAiFieldNames,
  summaryEnabled: true,
);

String _candidate({
  String maxAge = '{"value":35,"quote":"Başvuru tarihi itibarıyla 35 yaşını doldurmamış olmak.","confidence":0.97}',
  String education = 'null',
  String kpss = 'null',
  String quota = 'null',
  String summary = '[]',
}) =>
    '{"maxAge":$maxAge,"education":$education,"kpssType":$kpss,"quotaType":$quota,"summary":$summary}';

void main() {
  test('uzun metinde yalnızca ilgili cümleler ve komşuları seçilir', () {
    final filler = List.generate(
      400,
      (i) => 'Bu cümle konu dışı dolgu metnidir $i.',
    ).join(' ');
    final text =
        '$filler\nBaşvuru tarihi itibarıyla 35 yaşını doldurmamış olmak.\n$filler';
    final picked = selectPassages(text)!;
    expect(picked, contains('35 yaşını doldurmamış'));
    expect(picked.length, lessThan(600));
    expect(selectPassages('a. ' * 100), isNull);
    // Seçilen bölümden alınan alıntı tam metinde doğrulanır.
    final result = gateCandidate(
      '{"maxAge":{"value":35,"quote":"Başvuru tarihi itibarıyla 35 yaşını doldurmamış olmak.","confidence":0.95}}',
      text,
      policy: const AiEnrichmentPolicy(enabledFields: {'maxAge'}),
    );
    expect(result.maxAge!.value, 35);
  });

  test('kapıları geçen alanlar kabul edilir; alıntı normalize edilir', () {
    final result = gateCandidate(
      _candidate(
        education: '{"value":"Lisans","quote":"Lisans mezunu olmak (KPSS P3 puan türünden en az 70 puan almış olmak).","confidence":0.95}',
        kpss: '{"value":"P3","quote":"Lisans mezunu olmak (KPSS P3 puan türünden en az 70 puan almış olmak).","confidence":0.92}',
        quota: '{"value":"4/B","quote":"Bu ilan 657 sayılı Kanunun 4/B maddesi kapsamında sözleşmeli personel alımıdır.","confidence":0.9}',
      ),
      _text,
      policy: _all,
    );
    expect(result.maxAge!.value, 35);
    expect(result.education!.value, 'Lisans');
    expect(result.kpssType!.value, 'P3');
    expect(result.quotaType!.value, '4/B');
    expect(result.rejected, isEmpty);
  });

  test('kaynak metinde bulunmayan uydurma alıntı reddedilir', () {
    final result = gateCandidate(
      _candidate(
        maxAge: '{"value":40,"quote":"Adaylar 40 yaşından gün almamış olmalıdır.","confidence":0.99}',
      ),
      _text,
      policy: _all,
    );
    expect(result.maxAge, isNull);
    expect(result.rejected, contains('maxAge: alıntı kaynakta yok'));
  });

  test('alıntı var ama değeri desteklemiyorsa reddedilir', () {
    // 35 değeri, "35" içermeyen gerçek bir cümleyle desteklenmeye çalışılıyor.
    final result = gateCandidate(
      _candidate(
        maxAge: '{"value":35,"quote":"Kamu haklarından mahrum bulunmamak.","confidence":0.99}',
      ),
      _text,
      policy: _all,
    );
    expect(result.maxAge, isNull);
    expect(result.rejected, contains('maxAge: alıntı değeri desteklemiyor'));
    // Yüksek lisans cümlesi "Lisans" değerini desteklemez.
    final edu = gateCandidate(
      _candidate(
        maxAge: 'null',
        education: '{"value":"Lisans","quote":"Yüksek lisans mezunu olmak gerekir.","confidence":0.99}',
      ),
      '$_text\nYüksek lisans mezunu olmak gerekir.',
      policy: _all,
    );
    expect(edu.education, isNull);
  });

  test('düşük güven, sözlük dışı değer ve şema hatası alanı düşürür', () {
    final low = gateCandidate(
      _candidate(
        maxAge: '{"value":35,"quote":"Başvuru tarihi itibarıyla 35 yaşını doldurmamış olmak.","confidence":0.5}',
      ),
      _text,
      policy: _all,
    );
    expect(low.maxAge, isNull);
    expect(low.rejected, contains('maxAge: güven düşük'));

    final vocab = gateCandidate(
      _candidate(
        maxAge: 'null',
        education: '{"value":"Üniversite","quote":"Lisans mezunu olmak","confidence":1}',
      ),
      _text,
      policy: _all,
    );
    expect(vocab.education, isNull);

    final schema = gateCandidate(
      _candidate(maxAge: '{"value":"otuz beş","quote":"x","confidence":1}'),
      _text,
      policy: _all,
    );
    expect(schema.maxAge, isNull);
  });

  test('kapalı alan politikası: aday üretilse bile alan kabul edilmez', () {
    final result = gateCandidate(_candidate(), _text);
    expect(result.maxAge, isNull);
    expect(result.summary, isEmpty);
    final only = gateCandidate(
      _candidate(),
      _text,
      policy: const AiEnrichmentPolicy(enabledFields: {'maxAge'}),
    );
    expect(only.maxAge!.value, 35);
  });

  test('özet maddeleri yalnızca doğrulanmış alıntıyla kalır', () {
    final result = gateCandidate(
      _candidate(
        maxAge: 'null',
        summary:
            '[{"text":"Yaş sınırı 35","quote":"Başvuru tarihi itibarıyla 35 yaşını doldurmamış olmak."},'
            '{"text":"Maaş 100 bin TL","quote":"Aylık net maaş 100 bin TL ödenecektir."}]',
      ),
      _text,
      policy: _all,
    );
    expect(result.summary.map((b) => b.text), ['Yaş sınırı 35']);
    expect(result.rejected, contains('summary: alıntı kaynakta yok'));
  });

  test('kod çiti soyulur; bozuk JSON FormatException verir', () {
    final fenced = gateCandidate(
      '```json\n${_candidate()}\n```',
      _text,
      policy: _all,
    );
    expect(fenced.maxAge!.value, 35);
    expect(() => gateCandidate('bu json değil', _text), throwsFormatException);
    expect(() => gateCandidate('[1,2]', _text), throwsFormatException);
  });

  test('deterministik değer kazanır; yapay zekâ yalnızca boşluğu doldurur', () {
    const deterministic = ConditionFields(maxAge: ExtractedField<int>(30, 'x'));
    final ai = AiEnrichment(
      maxAge: const ExtractedField<int>(35, 'y'),
      education: const ExtractedField<String>('Lisans', 'z'),
    );
    final merged = mergeConditions(deterministic, ai);
    expect(merged.maxAge!.value, 30);
    expect(merged.education!.value, 'Lisans');
    expect(mergeConditions(deterministic, null).maxAge!.value, 30);
  });

  group('AiEnricher', () {
    AiEnricher build(LlmClient client, {int budget = 100000}) =>
        AiEnricher(client: client, policy: _all, budget: TokenBudget(budget));

    test('başarılı akış token harcamasını bütçeye işler', () async {
      final budget = TokenBudget(100000);
      final enricher = AiEnricher(
        client: _FakeLlm((_) async => _ok(_candidate())),
        policy: _all,
        budget: budget,
      );
      final result = await enricher.enrich(title: 'T', text: _text);
      expect(result.status, AiStatus.ok);
      expect(result.enrichment!.maxAge!.value, 35);
      expect(budget.used, 150);
    });

    test('ilgili bölüm bulunamayan metin gönderilmez, bütçe bitince çağrı yapılmaz', () async {
      var calls = 0;
      final fake = _FakeLlm((_) async {
        calls++;
        return _ok(_candidate());
      });
      final tooLong = await build(fake)
          .enrich(title: 'T', text: 'a' * (kAiWholeTextChars + 1));
      expect(tooLong.status, AiStatus.skippedInput);
      final none = await build(fake, budget: 0).enrich(title: 'T', text: _text);
      expect(none.status, AiStatus.budgetExhausted);
      expect(calls, 0);
    });

    test('hata, ret ve bozuk çıktı durumları ayrı raporlanır', () async {
      expect(
        (await build(
          _FakeLlm((_) async => throw const LlmException('x', statusCode: 400)),
        ).enrich(title: 'T', text: _text)).status,
        AiStatus.failed,
      );
      expect(
        (await build(
          _FakeLlm((_) async => throw const LlmException('r', refused: true)),
        ).enrich(title: 'T', text: _text)).status,
        AiStatus.refused,
      );
      expect(
        (await build(
          _FakeLlm((_) async => _ok('düz metin')),
        ).enrich(title: 'T', text: _text)).status,
        AiStatus.invalid,
      );
    });
  });
}

LlmResponse _ok(String text) =>
    LlmResponse(text: text, inputTokens: 100, outputTokens: 50, model: 'sahte');

class _FakeLlm implements LlmClient {
  _FakeLlm(this._handler);
  final Future<LlmResponse> Function(LlmRequest) _handler;
  @override
  String get provider => 'sahte';
  @override
  String get model => 'sahte';
  @override
  Future<LlmResponse> complete(LlmRequest request) => _handler(request);
}
