import '../notifications/alert_history.dart';
import 'listing_store.dart';

/// Kayıtlı arama süzgeçlerini ilan kaydına uygulayan saf eşleştirici.
/// Hem ana ekran listesi hem arka plan bildirim eşleştirmesi bunu kullanır.
bool matchesFilters(ListingRecord record, Map<String, String> filters) {
  final q = (filters['q'] ?? '').toLowerCase();
  if (q.isNotEmpty && !record.title.toLowerCase().contains(q)) return false;

  final kategori = int.tryParse(filters['kategori'] ?? '') ?? 0;
  if (kategori == 1 && !record.category.toLowerCase().contains('işçi')) {
    return false;
  }
  if (kategori == 2 && !record.category.toLowerCase().contains('personel')) {
    return false;
  }
  if (kategori == 3 && !record.title.toLowerCase().contains('belediye')) {
    return false;
  }

  if (filters['son30'] == '1') {
    final published = record.publishedAt;
    if (published == null ||
        published.isBefore(DateTime.now().subtract(const Duration(days: 30)))) {
      return false;
    }
  }

  final sehir = filters['sehir'] ?? '';
  if (sehir.isNotEmpty &&
      !record.places.any(
        (place) => place.toLowerCase().contains(sehir.toLowerCase()),
      )) {
    return false;
  }

  // Yaş/eğitim/KPSS süzgeçleri yalnızca alıntı kanıtlı çıkarılmış alanlarda
  // uygulanır; bilinmeyen değerli ilan bu etikette gösterilmez.
  final yas = int.tryParse(filters['yas'] ?? '');
  if (yas != null && (record.maxAge == null || record.maxAge! < yas)) {
    return false;
  }
  final egitim = filters['egitim'] ?? '';
  if (egitim.isNotEmpty && record.education != egitim) return false;
  final kpss = filters['kpss'] ?? '';
  if (kpss.isNotEmpty && record.kpss != kpss) return false;

  return true;
}

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
  });

  final String searchName;
  final String title;
  final String body;
  final String listingUrl;
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
      .where((record) => matchesFilters(record, search.filters))
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
  if (deadline == null) return null;
  final remaining = deadline.difference(now).inDays;
  if (remaining < 0 || remaining > daysBefore) return null;
  return PendingNotification(
    searchName: 'Son başvuru',
    title: remaining == 0 ? 'Bugün son gün' : 'Son $remaining gün',
    body: record.title,
    listingUrl: record.url,
  );
}
