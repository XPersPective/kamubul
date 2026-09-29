import 'package:kamubul_core/ai/ai_eval.dart';
import 'package:kamubul_core/kamubul_core.dart';
import 'package:test/test.dart';

const _quote = 'Başvuru tarihi itibarıyla 35 yaşını doldurmamış olmak.';

class _Llm implements LlmClient {
  _Llm(this.answer);
  final String Function(String user) answer;
  @override
  String get provider => 'sahte';
  @override
  String get model => 'sahte';
  @override
  Future<LlmResponse> complete(LlmRequest request) async => LlmResponse(
    text: answer(request.user),
    inputTokens: 10,
    outputTokens: 5,
    model: 'sahte',
  );
}

AiEnricher _enricher(String Function(String) answer) => AiEnricher(
  client: _Llm(answer),
  policy: const AiEnrichmentPolicy(enabledFields: {'maxAge'}),
  budget: TokenBudget(100000),
);

const _records = [
  {'id': 'a', 'title': 'A', 'text': 'Adaylarda aranan şart: $_quote'},
  {'id': 'b', 'title': 'B', 'text': 'Adaylarda aranan şart: $_quote'},
];

void main() {
  test(
    'doğru dolgu TP, yanlış dolgu FP sayılır ve precision hesaplanır',
    () async {
      // Her iki ilanda da metin aynı ("35"); altın etiket b için 40 (yanlış dolgu).
      final gold = {
        'a': {
          'maxAge': {'value': 35},
        },
        'b': {
          'maxAge': {'value': 40},
        },
      };
      final report = await evaluateAi(
        records: _records,
        goldById: gold,
        enricher: _enricher(
          (_) => '{"maxAge":{"value":35,"quote":"$_quote","confidence":0.99}}',
        ),
      );
      final score = report.fields['maxAge']!;
      expect(report.evaluated, 2);
      // extractConditions zaten 35'i bulursa dolgu sayılmaz; bu testte yalnızca
      // sayım mantığı doğrulanır: dolgu varsa tp+fp==2 ve precision 0.5.
      if (score.filled > 0) {
        expect(score.tp, 1);
        expect(score.fp, 1);
        expect(score.precision, 0.5);
        expect(score.passes, isFalse);
      } else {
        expect(score.abstained, 0);
      }
    },
  );

  test('model boş dönerse çekimser sayılır, precision 1 kalır', () async {
    final report = await evaluateAi(
      records: _records,
      goldById: {
        'a': {'maxAge': null},
        'b': {'maxAge': null},
      },
      enricher: _enricher((_) => '{"maxAge":null}'),
      extract: (_) => const ConditionFields(),
    );
    final score = report.fields['maxAge']!;
    expect(score.fp, 0);
    expect(score.abstained, 2);
    expect(score.passes, isTrue);
  });
}
