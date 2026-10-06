import 'package:flutter/material.dart';

/// Resmî ilan metnini okunur bloklara ayırır: başlık, paragraf, madde ve
/// tablo. Kaynak metin değiştirilmez; yalnız sunumu düzenlenir. Tablo
/// satırları ham "hücre | hücre" yerine başlık etiketli satır kartlarıdır.
sealed class NoticeBlock {
  const NoticeBlock();
}

class NoticeHeading extends NoticeBlock {
  const NoticeHeading(this.text);
  final String text;
}

class NoticeParagraph extends NoticeBlock {
  const NoticeParagraph(this.text);
  final String text;
}

class NoticeBullet extends NoticeBlock {
  const NoticeBullet(this.marker, this.text);
  final String marker;
  final String text;
}

class NoticeTable extends NoticeBlock {
  const NoticeTable(this.headers, this.rows);

  /// Boşsa tabloda başlık satırı yoktur.
  final List<String> headers;
  final List<List<String>> rows;
}

final _bullet = RegExp(r'^([-•*▪●]|\d{1,2}[.)-]|[a-zçğıöşü][).])\s*(?=\S)');

List<String> tableCells(String line) {
  final cells = line.split('|').map((c) => c.trim()).toList();
  while (cells.isNotEmpty && cells.first.isEmpty) {
    cells.removeAt(0);
  }
  while (cells.isNotEmpty && cells.last.isEmpty) {
    cells.removeLast();
  }
  return cells;
}

bool _isHeading(String line) {
  if (line.length > 90 || line.contains('|')) return false;
  if (line.endsWith(':') && line.length <= 60) return true;
  final letters = line.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
  if (letters.length < 4 || RegExp(r'[.,;]$').hasMatch(line)) return false;
  final upper = letters
      .split('')
      .where((c) => c == c.toUpperCase() && c != c.toLowerCase())
      .length;
  return upper / letters.length >= 0.8;
}

List<NoticeBlock> parseNotice(String text) {
  final blocks = <NoticeBlock>[];
  List<List<String>>? table;
  void closeTable() {
    final rows = table;
    table = null;
    if (rows == null || rows.isEmpty) return;
    final width = rows.first.length;
    final headed =
        rows.length > 1 &&
        width > 2 &&
        rows.skip(1).where((r) => r.length == width).length >=
            (rows.length - 1) / 2;
    blocks.add(
      headed
          ? NoticeTable(rows.first, rows.sublist(1))
          : NoticeTable(const [], rows),
    );
  }

  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final cells = line.contains('|') ? tableCells(line) : const <String>[];
    if (cells.length >= 2) {
      (table ??= []).add(cells);
      continue;
    }
    closeTable();
    final value = cells.length == 1 ? cells.single : line;
    final bullet = _bullet.firstMatch(value);
    if (_isHeading(value)) {
      blocks.add(NoticeHeading(value));
    } else if (bullet != null && value.length > bullet.end + 2) {
      blocks.add(
        NoticeBullet(bullet.group(1)!, value.substring(bullet.end).trim()),
      );
    } else {
      blocks.add(NoticeParagraph(value));
    }
  }
  closeTable();
  return blocks;
}

// "mezun olmak", "almış olmak", "olması şartı aranır": nitelik cümlesi fiil taşır.
final _requirementVerb = RegExp(
  r'(?:m[ae]k|m[ıiuü]ş|m[ae]s[ıi]|[ıi]l[ıi]r|m[ıiuü]şt[ıiuü]r|ecektir|acaktır|olup)(?=[\s.,;:)]|$)',
  caseSensitive: false,
);
// Dikey tablo anahtarı: "ÖĞRENİM | Önlisans", "ARANILAN ŞARTLAR | ...".
final _tableKey = RegExp(r'^[\p{Lu}\s]{2,30}$', unicode: true);

/// Pozisyon satırı: etiket, kod ve kişi sayısı hücreleri başlıkta zaten
/// gösterildiği için tekrarlanmaz. Nitelik cümleleri madde olur ("*" maddeleri
/// ayrılır); birim, cinsiyet, puan türü gibi kısa hücreler tek satırda kalır.
({List<String> facts, List<String> requirements}) positionDetails(
  String text,
  String label,
  int? quota,
) {
  final facts = <String>[], requirements = <String>[];
  final labelText = label.toLowerCase();
  final lines = [
    for (final raw in text.split('\n'))
      if (raw.trim().isNotEmpty) raw.trim(),
  ];
  // "6 (Erkek-Kadın)", "8 kişi": sayı başlıkta; parantezdeki koşul kalır.
  final counted = quota == null
      ? null
      : RegExp('^$quota\\s*(?:kişi|adet)?\\s*(?:\\((.+)\\))?\$');
  for (final line in lines) {
    var parts = line.contains('|') ? tableCells(line) : [line];
    if (lines.length > 1 && parts.length == 2 && _tableKey.hasMatch(parts[0])) {
      parts = [parts[1]];
    }
    for (final cell in parts) {
      final lower = cell.toLowerCase();
      if (cell.isEmpty ||
          cell == '-' ||
          labelText.contains(lower) ||
          (cell.length <= 12 &&
              RegExp(r'^[\p{Lu}\d/.-]+$', unicode: true).hasMatch(cell))) {
        continue;
      }
      final count = counted?.firstMatch(cell);
      if (count != null) {
        if (count.group(1) case final String condition) facts.add(condition);
      } else if (cell.length > 60 || _requirementVerb.hasMatch(cell)) {
        requirements.addAll(
          cell
              .split(RegExp(r'(?:^|\s)\*(?=\S)'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty),
        );
      } else {
        facts.add(cell);
      }
    }
  }
  return (facts: facts, requirements: requirements);
}

/// Bloğu ekrana çizer; seçilebilir metin üst SelectionArea ile sağlanır.
class NoticeBlockView extends StatelessWidget {
  const NoticeBlockView(this.block, {super.key});

  final NoticeBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyLarge?.copyWith(height: 1.55);
    return switch (block) {
      NoticeHeading(:final text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            height: 1.35,
          ),
        ),
      ),
      NoticeParagraph(:final text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: body),
      ),
      NoticeBullet(:final marker, :final text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 30,
              child: Text(
                marker == '*' || marker == '-' ? '•' : marker,
                style: body?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(child: Text(text, style: body)),
          ],
        ),
      ),
      NoticeTable(:final headers, :final rows) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in rows) _TableRowCard(headers: headers, row: row),
          ],
        ),
      ),
    };
  }
}

class _TableRowCard extends StatelessWidget {
  const _TableRowCard({required this.headers, required this.row});

  final List<String> headers;
  final List<String> row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labelled = headers.isNotEmpty && headers.length == row.length;
    final pairs = labelled
        ? [
            for (var i = 0; i < row.length; i++)
              if (row[i].isNotEmpty && row[i] != '-') (headers[i], row[i]),
          ]
        : row.length == 2
        ? [(row.first.replaceFirst(RegExp(r'\s*:\s*$'), ''), row.last)]
        : [for (final cell in row) ('', cell)];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, (key, value)) in pairs.indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
              child: key.isEmpty
                  ? Text(value, style: theme.textTheme.bodyMedium)
                  : Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$key\n',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text: value,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}
