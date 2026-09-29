/// Sunucu tarafı bildirim planı: yeni ilanları bir cihazın etiketleriyle
/// eşleştirir; sessiz saat, günlük tavan, özet ve ertelenen kuyruk kurallarını
/// uygulama tarafındaki `decideAlerts` ile aynı saf mantıkla işler.
library;

import '../data/listing_models.dart';
import '../data/search_alerts.dart';
import '../remote/device_registration.dart';
import '../time/wall_clock.dart';
import 'alert_history.dart';

const int kMaxPushQueue = 50;

/// Cihaz başına sunucuda tutulan bildirim durumu.
class DevicePushState {
  const DevicePushState({
    this.sentDay,
    this.instantSentToday = 0,
    this.digestSentDay,
    this.queue = const [],
  });

  /// `instantSentToday` sayacının ait olduğu gün (`YYYY-MM-DD`, cihaz saati).
  final String? sentDay;
  final int instantSentToday;
  final int? digestSentDay;
  final List<PendingNotification> queue;

  Map<String, Object?> toJson() => {
    'sentDay': sentDay,
    'instantSentToday': instantSentToday,
    'digestSentDay': digestSentDay,
    'queue': [
      for (final item in queue)
        {
          'searchName': item.searchName,
          'title': item.title,
          'body': item.body,
          'url': item.listingUrl,
          'digest': item.digest,
        },
    ],
  };

  static DevicePushState fromJson(Object? raw) {
    if (raw is! Map) return const DevicePushState();
    final queue = <PendingNotification>[];
    final rawQueue = raw['queue'];
    if (rawQueue is List) {
      for (final item in rawQueue.take(kMaxPushQueue)) {
        if (item is! Map) continue;
        final title = item['title'];
        final body = item['body'];
        final url = item['url'];
        if (title is! String || body is! String || url is! String) continue;
        queue.add(
          PendingNotification(
            searchName: item['searchName'] is String
                ? item['searchName'] as String
                : '',
            title: title,
            body: body,
            listingUrl: url,
            digest: item['digest'] == true,
          ),
        );
      }
    }
    final sent = raw['instantSentToday'];
    final digestDay = raw['digestSentDay'];
    return DevicePushState(
      sentDay: raw['sentDay'] is String ? raw['sentDay'] as String : null,
      instantSentToday: sent is int && sent >= 0 ? sent : 0,
      digestSentDay: digestDay is int ? digestDay : null,
      queue: queue,
    );
  }
}

class PushPlan {
  const PushPlan({required this.toSend, required this.state});

  /// Şimdi gönderilecek bildirimler (kuyruktan boşalanlar önce).
  final List<PendingNotification> toSend;
  final DevicePushState state;
}

/// [newListings]: bu çalıştırmada kataloğa ilk kez giren ilanlar. Aynı ilan
/// yalnızca bir kez "yeni" olur; bu yüzden ayrıca görüldü kümesi tutulmaz.
PushPlan planDevicePush({
  required DeviceRegistration device,
  required List<ListingRecord> newListings,
  required DevicePushState state,
  required DateTime nowWall,
}) {
  final today = dayKey(nowWall);
  var instantSent = state.sentDay == today ? state.instantSentToday : 0;
  var digestDay = state.digestSentDay;
  final send = <PendingNotification>[];
  final held = <PendingNotification>[];

  if (newListings.isNotEmpty) {
    for (final search in device.searches) {
      final decision = decideAlerts(
        search: SavedSearch(
          id: null,
          name: search.name,
          filters: search.filters,
          createdAt: nowWall,
        ),
        listings: newListings,
        previouslySeen: const {},
        config: AlertConfig(
          now: nowWall,
          quietStartHour: device.quietStartHour,
          quietEndHour: device.quietEndHour,
          maxInstantPerDay: device.maxInstantPerDay,
          instantSentToday: instantSent,
          digestSentDay: digestDay,
        ),
      );
      send.addAll(decision.notifications);
      held.addAll(decision.held);
      instantSent += decision.notifications.where((n) => !n.digest).length;
      if ([...decision.notifications, ...decision.held].any((n) => n.digest)) {
        digestDay = nowWall.day;
      }
    }
  }

  var queue = [...state.queue, ...held];
  if (queue.length > kMaxPushQueue) queue = queue.sublist(0, kMaxPushQueue);
  final flushed = <PendingNotification>[];
  if (!isQuietHour(nowWall, device.quietStartHour, device.quietEndHour)) {
    var room = device.maxInstantPerDay - instantSent;
    final remaining = <PendingNotification>[];
    for (final item in queue) {
      if (item.digest) {
        flushed.add(item);
      } else if (room > 0) {
        flushed.add(item);
        room--;
        instantSent++;
      } else {
        remaining.add(item);
      }
    }
    queue = remaining;
  }

  return PushPlan(
    toSend: [...flushed, ...send],
    state: DevicePushState(
      sentDay: today,
      instantSentToday: instantSent,
      digestSentDay: digestDay,
      queue: queue,
    ),
  );
}
