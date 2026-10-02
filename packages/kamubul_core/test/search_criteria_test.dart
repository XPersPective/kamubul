import 'dart:convert';
import 'dart:io';

import 'package:kamubul_core/data/search_criteria.dart';
import 'package:kamubul_core/data/turkish_cities.dart';
import 'package:test/test.dart';

void main() {
  final corpus = jsonDecode(
    File('../../contracts/criteria-v2.json').readAsStringSync(),
  ) as List;
  for (final raw in corpus) {
    final row = raw as Map;
    test('Worker parity: ${row['name']}', () {
      final criteria = row['legacy'] != null
          ? SearchCriteria.fromLegacy(
              Map<String, String>.from(row['legacy'] as Map),
            )
          : SearchCriteria.parse(
              Map<String, Object?>.from(row['criteria'] as Map),
            );
      final outcome = criteria.match(
        Map<String, Object?>.from(row['listing'] as Map),
        now: row['now'] == null
            ? DateTime.utc(2026, 9, 30, 12)
            : DateTime.parse(row['now'] as String),
      );
      expect(
        outcome == CriteriaMatch.noMatch ? 'no_match' : outcome.name,
        row['expected'],
      );
    });
  }
  test('criteria date/type/version are validated', () {
    for (final invalid in [
      {'version': 1},
      {'age': 30, 'ageAsOf': '2026-02-30'},
      {'kpssScore': 70},
      {'cities': 'Ankara'},
    ]) {
      expect(() => SearchCriteria.parse(invalid), throwsFormatException);
    }
  });
  test('education codes and spelling aliases use readable labels', () {
    expect(educationLabel('education:associate'), 'Ön lisans');
    expect(educationLabel('ÖNLİSANS'), 'Ön lisans');
    expect(educationLabel('education:master'), 'Yüksek lisans');
    expect(educationLabel('Üniversite mezunu'), 'Üniversite mezunu');
  });
  test(
    'all city identities resolve without treating districts as provinces',
    () {
      for (final city in turkishCities) {
        final id = 'city:${foldTurkish(city).toLowerCase()}';
        expect(cityLabel(id), city);
        expect(
          SearchCriteria.parse({
            'version': 2,
            'cities': [id],
          }).match({
            'title': 'İlan',
            'places': [city],
          }, now: DateTime.utc(2026, 9, 30)),
          CriteriaMatch.match,
        );
      }
      expect(cityLabel('city:unknown'), 'city:unknown');
      expect(cityLabel('ANKARA'), 'ANKARA');
      expect(canonicalCity('Çankaya'), isNull);
    },
  );
}
