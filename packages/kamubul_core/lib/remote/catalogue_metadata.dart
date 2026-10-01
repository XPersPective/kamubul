import 'snapshot.dart';

class CatalogueMetadata {
  CatalogueMetadata._(
    this.json,
    this.latestSeq,
    this.oldestRetainedSeq,
    this.sources,
  );
  final Map<String, Object?> json;
  final int latestSeq;
  final int oldestRetainedSeq;
  final List<SourceStatus> sources;

  static CatalogueMetadata decode(Object? raw) {
    if (raw is! Map ||
        raw['schemaVersion'] != 2 ||
        raw['taxonomyVersion'] is! int ||
        (raw['taxonomyVersion'] as int) < 1) {
      throw const FormatException('metadata schema');
    }
    final latest = raw['latestSeq'],
        oldest = raw['oldestRetainedSeq'],
        sources = raw['sources'];
    if (latest is! int ||
        oldest is! int ||
        latest < 0 ||
        latest > 9007199254740991 ||
        oldest < 0 ||
        oldest > latest ||
        sources is! List ||
        sources.length > 50) {
      throw const FormatException('metadata cursor/sources');
    }
    final parsed = <SourceStatus>[];
    final ids = <String>{};
    for (final source in sources) {
      if (source is! Map ||
          source['id'] is! String ||
          source['name'] is! String ||
          !['ok', 'failed', 'blocked', 'disabled'].contains(source['state']) ||
          !ids.add(source['id'] as String)) {
        throw const FormatException('metadata source');
      }
      DateTime? date(String key) {
        final value = source[key];
        if (value == null) return null;
        if (value is! String ||
            value.length > 40 ||
            DateTime.tryParse(value) == null) {
          throw const FormatException('metadata date');
        }
        return DateTime.parse(value);
      }

      final id = source['id'] as String,
          name = source['name'] as String,
          note = source['note'];
      if (id.isEmpty ||
          id.length > 40 ||
          name.isEmpty ||
          name.length > 80 ||
          (note != null && (note is! String || note.length > 300))) {
        throw const FormatException('metadata source length');
      }
      parsed.add(
        SourceStatus(
          id: id,
          name: name,
          state: SourceState.parse(source['state']),
          lastAttemptAt: date('last_attempt'),
          lastSuccessAt: date('last_success'),
          note: note as String?,
        ),
      );
    }
    return CatalogueMetadata._(
      Map<String, Object?>.unmodifiable(Map<String, Object?>.from(raw)),
      latest,
      oldest,
      List.unmodifiable(parsed),
    );
  }
}
