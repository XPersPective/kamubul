/// Türkiye ve cihaz saatleri "duvar saati" olarak taşınır: saat dilimi
/// bilgisi olmayan (naif) `DateTime`. Ayrıştırıcılar, eşleştirici ve sessiz
/// saat mantığı bu biçimle çalışır; sunucu ortamı `TZ=UTC` ile çalıştırılır,
/// böylece iki naif zaman her yerde aynı biçimde karşılaştırılır.
library;

/// Türkiye'nin sabit UTC farkı (dakika); DST yoktur.
const int kTurkeyUtcOffsetMinutes = 180;

/// [utcNow] anının [utcOffsetMinutes] farklı yerdeki duvar saatini döndürür.
DateTime wallClock(
  DateTime utcNow, {
  int utcOffsetMinutes = kTurkeyUtcOffsetMinutes,
}) {
  final shifted = utcNow.toUtc().add(Duration(minutes: utcOffsetMinutes));
  return DateTime(
    shifted.year,
    shifted.month,
    shifted.day,
    shifted.hour,
    shifted.minute,
    shifted.second,
  );
}

/// `YYYY-MM-DD` gün anahtarı.
String dayKey(DateTime wall) =>
    '${wall.year.toString().padLeft(4, '0')}-'
    '${wall.month.toString().padLeft(2, '0')}-'
    '${wall.day.toString().padLeft(2, '0')}';

/// Naif ISO-8601 (ofsetsiz) yazım; UTC işaretli değer alan değerleriyle yazılır.
String wallIso(DateTime value) => DateTime(
  value.year,
  value.month,
  value.day,
  value.hour,
  value.minute,
  value.second,
).toIso8601String();

/// Ofsetli yazımı reddeder: sunucu yalnızca naif duvar saati yayınlar.
DateTime? parseWallIso(Object? raw) {
  if (raw is! String || raw.isEmpty || raw.length > 40) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null || parsed.isUtc) return null;
  return parsed;
}
