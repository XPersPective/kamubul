import 'dart:io';

import 'package:test/test.dart';
import 'package:kamubul_core/kamubul_core.dart';

void main() {
  // Fikstür 2026-10-04'te esube.iskur.gov.tr "Kamu" araması sonuç tablosundan.
  final fixture = File('test/fixtures/iskur_kamu_grid.html').readAsStringSync();

  test('kamu satırlarını kurum, kontenjan, yer ve son tarihle okur', () {
    final items = parseIskurKamuGrid(fixture);
    expect(items, hasLength(9));
    final first = items.first;
    expect(first.id, '00009817965');
    expect(first.occupation, 'Servis Elemanı (Garson)');
    expect(first.institution, 'POLİS EVİ');
    expect(first.period, 'Daimi');
    expect(first.quota, 4);
    expect(first.city, 'Iğdır');
    expect(first.deadline, DateTime(2026, 10, 6, 23, 59));
    expect(first.url.queryParameters['uiID'], '00009817965');
    final record = iskurRecord(first, DateTime(2026, 10, 4));
    expect(record.title, 'POLİS EVİ - Servis Elemanı (Garson)');
    expect(record.category, 'İşçi (Daimi)');
    expect(record.places, ['Iğdır']);
  });

  test('özel sektör satırı asla alınmaz', () {
    final private = fixture
        .replaceAll('&#39;Kamu&#39;', '&#39;Özel&#39;');
    expect(parseIskurKamuGrid(private), isEmpty);
    final mislabeled = fixture.replaceAll(
      'ctlIsverenTurDL">Kamu<',
      'ctlIsverenTurDL">Özel Sektör<',
    );
    expect(parseIskurKamuGrid(mislabeled), isEmpty);
  });

  test('telefona verilen eski tarz HTML (<b>, <font>) de okunur', () {
    const row =
        '<table id="ctl04_ctlGridAcikIslerListeDetail"><tr bgcolor="#F0F0F0"><td><font>'
        '<a onclick="PopupJobDetails(&#39;00009830885&#39;,&#39;Kamu&#39;,&#39;0&#39;);return false;" id="x"><b> Beden İşçisi (Genel)</b></a>'
        '<span id="g_ctl03_ctlIsverenDL"><b>KARŞIYAKA BELEDİYE BAŞKANLIĞI</b></span>'
        '<span id="g_ctl03_ctlIsverenTurDL">Kamu</span> / <span id="g_ctl03_ctlCalismaPeriyotDL">Geçici</span>'
        '<span id="g_ctl03_Label9">40</span>'
        '<span id="g_ctl03_ctlCalismaYeriDL"><b>İl Geneli Başvuru <br> (Çalışma Yeri: İZMİR / KARŞIYAKA) </b></span>'
        '<span id="g_ctl03_ctlSonBasvuruTarihi" title="Son Başvuru Tarihi">5.10.2026</span>'
        '</font></td></tr></table>';
    final item = parseIskurKamuGrid(row).single;
    expect(item.occupation, 'Beden İşçisi (Genel)');
    expect(item.institution, 'KARŞIYAKA BELEDİYE BAŞKANLIĞI');
    expect(item.quota, 40);
    expect(item.city, 'İzmir');
    expect(item.district, 'KARŞIYAKA');
  });

  test('sonuç tablosu yoksa hata verir', () {
    expect(() => parseIskurKamuGrid('<html></html>'), throwsFormatException);
  });
}
