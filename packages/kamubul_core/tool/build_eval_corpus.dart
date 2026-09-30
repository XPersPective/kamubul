import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:kamubul_core/listings/kariyer_detail.dart';
import 'package:kamubul_core/listings/kariyer_feed.dart';
import 'package:kamubul_core/listings/sbb_feed.dart';

/// PB-007 değerlendirme korpusu yakalayıcı (tek seferlik kanıt aracı).
///
/// Her kaynaktan gerçek resmî ilan metinlerini toplar; etiketler
/// `test/fixtures/eval/gold_*.json` dosyalarına kaynak metin OKUNARAK
/// elle yazılır (döngüsellik yok: etiketler çıkarımcıdan bağımsızdır).
///
/// Kariyer Kapısı yalnızca açık ilanları listeler; geçmiş ilan kimlikleri
/// Wayback CDX dizininden (yalnızca URL kılavuzu) toplanır ve İÇERİK her
/// durumda resmî api.kariyerkapisi.gov.tr ayrıntı uçlarından alınır
/// (C-001: veri yalnızca resmî kanaldan).
///
/// Kullanım:
///   dart run tool/build_eval_corpus.dart kariyer [adet]
///   dart run tool/build_eval_corpus.dart sbb [adet]
///
/// Çıktı: `test/fixtures/eval/kaynak.jsonl` + `.tmp/labeling/kaynak.txt`
Future<void> main(List<String> args) async {
  final command = args.isEmpty ? 'all' : args.first;
  final client = http.Client();
  try {
    switch (command) {
      case 'kariyer':
        await _captureKariyer(client, _intArg(args, 1) ?? 55);
      case 'sbb':
        await _captureSbb(client, _intArg(args, 1) ?? 55);
      case 'all':
        await _captureKariyer(client, 55);
        await _captureSbb(client, 55);
      default:
        stderr.writeln('Bilinmeyen komut: $command');
        exitCode = 64;
    }
  } finally {
    client.close();
  }
}

int? _intArg(List<String> args, int index) =>
    args.length > index ? int.tryParse(args[index]) : null;

final _evalDir = Directory('test/fixtures/eval');
final _labelDir = Directory('.tmp/labeling');

void _resetItems(String source) {
  _evalDir.createSync(recursive: true);
  File('${_evalDir.path}/$source.jsonl').writeAsStringSync('');
}

void _writeItem(String source, Map<String, Object?> item) {
  _evalDir.createSync(recursive: true);
  final file = File('${_evalDir.path}/$source.jsonl');
  file.writeAsStringSync('${jsonEncode(item)}\n', mode: FileMode.append);
}

void _writeDigest(String source, String digest) {
  _labelDir.createSync(recursive: true);
  File('${_labelDir.path}/$source.txt').writeAsStringSync(digest);
}

/// Geniş anahtar kelime taraması: etiketleme okumasını yönlendirir.
/// Desenler çıkarımcıdan GENİŞTİR; daraltırsa etiketler yanlı olur.
final _hintWords = RegExp(
  r'kpss|puan|yaş|doğum|mezun|eğitim|düzey|lise|önlisans|lisans|yüksek|'
  r'doktora|kadro|sözleşmeli|işçi|memur|engelli|hükümlü|375|kontenjan|'
  r'sınav|şart|aranan|görev|unvan|özel şart',
  caseSensitive: false,
);
final _sentenceSplit = RegExp(r'(?<=[.;:])\s+|\n+');

List<String> hintSentences(String text) {
  final hits = <String>[];
  for (final sentence in text.split(_sentenceSplit)) {
    final candidate = sentence.trim();
    if (candidate.length < 12) continue;
    if (_hintWords.hasMatch(candidate)) {
      hits.add(
        candidate.length > 400
            ? '${candidate.substring(0, 397)}...'
            : candidate,
      );
    }
    if (hits.length >= 40) break;
  }
  return hits;
}

Future<void> _captureKariyer(http.Client client, int count) async {
  stdout.writeln('Kariyer: açık ilanlar alınıyor...');
  _resetItems('kariyer');
  final guids = <String>[];
  final titles = <String, String>{};
  final seen = <String>{};
  void add(String guid, String title) {
    if (seen.add(guid)) {
      guids.add(guid);
      titles[guid] = title;
    }
  }

  try {
    for (final item in await loadKariyerListings(client: client)) {
      add(item.url.queryParameters['i']!, item.title);
    }
  } on Exception catch (e) {
    stderr.writeln('Açık liste alınamadı: $e');
  }
  stdout.writeln('  ${guids.length} açık ilan');

  // Geçmiş kimlikler: yalnızca URL kılavuzu; içerik resmî uçtan gelir.
  try {
    final cdx = await client
        .get(
          Uri.parse(
            'https://web.archive.org/cdx/search/cdx?url=kariyerkapisi.gov.tr/'
            'IlanDetay*&output=json&collapse=urlkey&limit=1000',
          ),
        )
        .timeout(const Duration(seconds: 40));
    if (cdx.statusCode == 200) {
      final rows = jsonDecode(utf8.decode(cdx.bodyBytes));
      if (rows is List) {
        for (final row in rows.skip(1)) {
          final original = row is List && row.length > 2 ? row[2] : null;
          if (original is! String) continue;
          final match = RegExp(r'i=([0-9a-f-]{36})').firstMatch(original);
          if (match != null) add(match.group(1)!, '');
        }
      }
    }
    stdout.writeln('  CDX ile toplam ${guids.length} kimlik');
  } on Exception catch (e) {
    stderr.writeln('CDX kılavuz alınamadı (devam): $e');
  }

  final buffer = StringBuffer('# Kariyer korpus özeti (etiketleme için)\n\n');
  var captured = 0;
  for (final guid in guids) {
    if (captured >= count) break;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    try {
      final url = Uri.https('kariyerkapisi.gov.tr', '/IlanDetay', {'i': guid});
      final detail = await loadKariyerDetail(url, client: client);
      final text = [
        detail.body,
        for (final position in detail.positions) position.conditions,
      ].join('\n');
      if (text.trim().isEmpty) continue;
      captured++;
      _writeItem('kariyer', {
        'id': guid,
        'source': 'kariyerkapisi',
        'url': url.toString(),
        'institution': detail.institution,
        'title':
            titles[guid] ??
            (detail.positions.isEmpty ? '' : detail.positions.first.title),
        'text': text,
      });
      buffer.writeln('## [$captured] $guid');
      buffer.writeln('Kurum: ${detail.institution}');
      if (titles[guid]?.isNotEmpty ?? false) {
        buffer.writeln('Başlık: ${titles[guid]}');
      }
      buffer.writeln(
        'İlk 400 karakter: ${text.substring(0, text.length < 400 ? text.length : 400)}',
      );
      buffer.writeln('İşaretli cümleler:');
      for (final sentence in hintSentences(text)) {
        buffer.writeln('- $sentence');
      }
      buffer.writeln();
    } on Exception catch (e) {
      stderr.writeln('  $guid atlandı: $e');
    }
  }
  _writeDigest('kariyer', buffer.toString());
  stdout.writeln('Kariyer: $captured ilan yazıldı');
}

Future<void> _captureSbb(http.Client client, int count) async {
  _resetItems('sbb');
  final buffer = StringBuffer('# SBB korpus özeti (etiketleme için)\n\n');
  final blockRegex = RegExp(
    "<a href='(ilanDetay\\.aspx\\?kod=[^']+)'[^>]*>(.*?)</a>",
    dotAll: true,
  );
  final tagRegex = RegExp(r'<[^>]+>');
  var captured = 0;
  for (final year in [2026, 2025, 2024, 2023]) {
    if (captured >= count) break;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    String page;
    try {
      page = await loadSbbListPage(client: client, year: year);
    } on Exception catch (e) {
      stderr.writeln('SBB $year okunamadı: $e');
      continue;
    }
    for (final match in blockRegex.allMatches(page)) {
      if (captured >= count) break;
      final href = match.group(1)!;
      final kod = Uri.decodeComponent(
        href.replaceFirst('ilanDetay.aspx?kod=', ''),
      );
      if (kod.isEmpty) continue;
      final raw = match.group(0)!;
      final text = tagRegex
          .allMatches(match.group(2)!)
          .fold(
            match.group(2)!,
            (current, tag) => current.replaceFirst(tag.group(0)!, ''),
          )
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      captured++;
      _writeItem('sbb', {
        'id': kod,
        'source': 'sbb',
        'url': Uri.https(sbbHost, '/ilanDetay.aspx', {'kod': kod}).toString(),
        'year': year,
        'text': text,
        'raw': raw,
      });
      buffer.writeln('[$captured] $kod ($year): $text');
    }
  }
  _writeDigest('sbb', buffer.toString());
  stdout.writeln('SBB: $captured ilan yazıldı');
}
