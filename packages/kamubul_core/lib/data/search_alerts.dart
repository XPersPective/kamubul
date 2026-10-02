import '../notifications/alert_history.dart';
import 'listing_models.dart';
import 'search_criteria.dart';

/// Hızlı filtre ve kayıtlı arama aynı kadro bazlı v2 eşleştiriciyi kullanır.
CriteriaMatch matchFilters(
  ListingRecord record,
  Map<String, String> filters, {
  DateTime? now,
  bool forSaved = false,
}) {
  if (!forSaved && record.category == 'Yurt Dışı Eğitim İlanları') {
    return CriteriaMatch.noMatch;
  }
  try {
    return SearchCriteria.fromLegacy(filters).match(
      record.matchingData,
      now: now ?? DateTime.now(),
      forSaved: forSaved,
    );
  } on FormatException {
    return CriteriaMatch.unknown;
  }
}

bool matchesFilters(
  ListingRecord record,
  Map<String, String> filters, {
  DateTime? now,
  bool forSaved = false,
}) =>
    matchFilters(record, filters, now: now, forSaved: forSaved) ==
    CriteriaMatch.match;

/// Kayıtlı aramanın bildirim modu.
enum SearchAlertMode { instant, digest, off }

SearchAlertMode alertModeOf(Map<String, String> filters) =>
    switch (filters['bildirim']) {
      'instant' => SearchAlertMode.instant,
      'digest' => SearchAlertMode.digest,
      'off' => SearchAlertMode.off,
      _ => SearchAlertMode.instant,
    };

/// Bildirim tetikleme kararları: saf, test edilebilir.
class PendingNotification {
  const PendingNotification({
    required this.searchName,
    required this.title,
    required this.body,
    required this.listingUrl,
    this.digest = false,
    this.eventId,
    this.listingId,
    this.listingRevision,
  });

  final String searchName;
  final String title;
  final String body;
  final String listingUrl;
  final String? listingId;
  final int? listingRevision;
  String get tapPayload => alertTapPayload(
    listingUrl,
    listingId: listingId,
    revision: listingRevision,
  );

  /// Günlük özet bildirimi mi (anlık günlük tavana sayılmaz).
  final bool digest;
  final String? eventId;

  /// Hex server IDs give the same OS notification identity after process restart.
  int get presentationId {
    final event = eventId;
    return event != null && RegExp(r'^[a-f\d]{64}$').hasMatch(event)
        ? int.parse(event.substring(0, 8), radix: 16) & 0x7fffffff
        : listingUrl.hashCode & 0x7fffffff;
  }
}

class NotificationDecision {
  const NotificationDecision({
    required this.notifications,
    required this.seenUrls,
    this.held = const [],
  });

  /// Gönderilecek bildirimler (anlık mod: ilan başına, günlük tavanlı;
  /// özet mod: tek toplu bildirim).
  final List<PendingNotification> notifications;

  /// Gönderimi ertelenen bildirimler: sessiz saat ya da günlük tavan dolu
  /// olduğu için şu an çıkmazlar; kuyruğa alınıp sonraki uygun denetimde
  /// gönderilirler.
  final List<PendingNotification> held;

  /// "Görüldü" işaretlenecek ilan URL'leri (bildirim gönderilse de gönderilmese
  /// de işlenmiş sayılır; aynı ilan ikinci kez bildirilmez).
  final Set<String> seenUrls;
}

class AlertConfig {
  const AlertConfig({
    required this.now,
    required this.quietStartHour,
    required this.quietEndHour,
    required this.maxInstantPerDay,
    required this.instantSentToday,
    required this.digestSentDay,
  });

  final DateTime now;
  final int quietStartHour;
  final int quietEndHour;
  final int maxInstantPerDay;
  final int instantSentToday;
  final int? digestSentDay;
}

/// Verilen kayıtlı aramalar ve yeni ilanlar için bildirim kararını üretir.
/// [previouslySeen]: bu arama için daha önce bildirilen/ görülen URL kümesi.
NotificationDecision decideAlerts({
  required SavedSearch search,
  required List<ListingRecord> listings,
  required Set<String> previouslySeen,
  required AlertConfig config,
}) {
  final mode = alertModeOf(search.filters);
  final matches = listings
      .where(
        (record) =>
            search.matchListing(record, now: config.now) == CriteriaMatch.match,
      )
      .toList();
  final seen = <String>{...previouslySeen};
  final notifications = <PendingNotification>[];
  if (mode == SearchAlertMode.off) {
    for (final record in matches) {
      seen.add(record.url);
    }
    return NotificationDecision(notifications: const [], seenUrls: seen);
  }

  final fresh = matches
      .where((record) => !previouslySeen.contains(record.url))
      .toList();
  for (final record in matches) {
    seen.add(record.url);
  }
  if (fresh.isEmpty) {
    return NotificationDecision(notifications: const [], seenUrls: seen);
  }

  final quiet = isQuietHour(
    config.now,
    config.quietStartHour,
    config.quietEndHour,
  );
  final held = <PendingNotification>[];
  if (mode == SearchAlertMode.instant) {
    // Sessiz saatte gönderim payı sıfırdır; taşanlar kuyruğa alınır.
    final room = quiet
        ? 0
        : (config.maxInstantPerDay - config.instantSentToday).clamp(
            0,
            fresh.length,
          );
    for (final record in fresh.take(room)) {
      notifications.add(
        PendingNotification(
          searchName: search.name,
          title: search.name,
          body: record.title,
          listingUrl: record.url,
        ),
      );
    }
    for (final record in fresh.skip(room)) {
      held.add(
        PendingNotification(
          searchName: search.name,
          title: search.name,
          body: record.title,
          listingUrl: record.url,
        ),
      );
    }
  } else if (mode == SearchAlertMode.digest &&
      config.digestSentDay != config.now.day) {
    final summary = fresh.length == 1
        ? fresh.single.title
        : '${fresh.length} yeni ilan';
    final digest = PendingNotification(
      searchName: search.name,
      title: '${search.name}: $summary',
      body: fresh.take(3).map((record) => record.title).join('\n'),
      listingUrl: fresh.first.url,
      digest: true,
    );
    (quiet ? held : notifications).add(digest);
  }
  // Ertelenen bildirimler kuyruğa alınır ve bir sonraki uygun denetimde
  // gönderilir; ilan "görüldü" işaretlendiği için aynı ilan tekrar
  // bildirilmez.
  return NotificationDecision(
    notifications: notifications,
    held: held,
    seenUrls: seen,
  );
}

/// Son başvuru hatırlatıcısı: kaydedilen ilanlar için son X gün içinde bir kez.
PendingNotification? deadlineReminder({
  required ListingRecord record,
  required Set<String> alreadyReminded,
  required DateTime now,
  int daysBefore = 3,
}) {
  if (!record.saved || alreadyReminded.contains(record.url)) return null;
  final deadline = record.deadline;
  if (deadline == null || !deadline.isAfter(now)) return null;
  final end = deadline.toLocal(), today = now.toLocal();
  final remaining = DateTime.utc(
    end.year,
    end.month,
    end.day,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  if (remaining < 0 || remaining > daysBefore) return null;
  return PendingNotification(
    searchName: 'Son başvuru',
    title: remaining == 0 ? 'Bugün son gün' : 'Son $remaining gün',
    body: record.title,
    listingUrl: record.url,
  );
}
