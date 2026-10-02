import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:napp_core/napp_core.dart';
import 'package:workmanager/workmanager.dart';

import '../data/catalogue_refresh.dart';
import '../data/listing_store.dart';
import '../data/search_alerts.dart';
import 'alert_history.dart';

const _channelId = 'kamubul_alerts';
const _backgroundTaskName = 'kamubulRefreshAlerts';

final FlutterLocalNotificationsPlugin _plugin =
    FlutterLocalNotificationsPlugin();
bool _initialized = false;

/// Bildirim dokunuşu hedefi: eski URL veya stable listingId taşıyan JSON.
///
/// Ana ekran stable kimliği API'den okur; eski URL payload'ları yerel yolu
/// kullanır. Soğuk açılışta [consumeLaunchAlertTap] aynı hedefi korur.
final ValueNotifier<String?> alertTapUrl = ValueNotifier<String?>(null);

void _setAlertTap(String? payload) {
  final target = decodeAlertTap(payload);
  if (target != null) {
    alertTapUrl.value = alertTapPayload(
      target.url,
      listingId: target.listingId,
      revision: target.revision,
    );
  }
}

/// Sunucu bildirimine (FCM) dokunulduğunda aynı yol kullanılır.
void openAlertUrl(String url) => _setAlertTap(url);

Future<void> _ensureInitialized() async {
  if (_initialized) return;
  await _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
    onDidReceiveNotificationResponse: (response) =>
        _setAlertTap(response.payload),
  );
  await _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          'İlan uyarıları',
          description: 'Kayıtlı aramalarınıza uyan yeni kamu ilanları',
          importance: Importance.defaultImportance,
        ),
      );
  _initialized = true;
}

/// Uygulama bir bildirim dokunuşuyla açıldıysa bekleyen URL'yi [alertTapUrl]
/// yazar; kendi simgesinden açılışta hiçbir şey yapmaz.
///
/// En iyi çabadır: bildirim altyapısı bu ortamda yoksa sessizce geçilir,
/// açılış akışı asla bundan etkilenmez.
Future<void> consumeLaunchAlertTap() async {
  try {
    await _ensureInitialized();
    if (alertTapUrl.value != null) return;
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) {
      _setAlertTap(details?.notificationResponse?.payload);
    }
  } catch (_) {
    // Bildirim eklentisi yoksa dokunuş köprüsü kullanılamaz; uygulama açılır.
  }
}

/// Bildirim izni: önce değer açıklaması (primer), sonra sistem penceresi.
Future<bool> requestAlertPermission(BuildContext context) async {
  await _ensureInitialized();
  if (!context.mounted) return false;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('İlan bildirimleri'),
      content: const Text(
        'Kayıtlı aramalarınıza uyan yeni ilanları ve kaydettiğiniz ilanların '
        'son başvuru hatırlatıcısını bildirimle öğrenin. Sessiz saatlerde '
        'bildirim gönderilmez; istediğiniz an kapatabilirsiniz.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Şimdi değil'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Aç'),
        ),
      ],
    ),
  );
  if (accepted != true) return false;
  if (!context.mounted) return false;
  return await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission() ??
      false;
}

Future<void> showPendingNotification(PendingNotification notification) async {
  await _ensureInitialized();
  await _plugin.show(
    id: notification.presentationId,
    title: notification.title,
    body: notification.body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'İlan uyarıları',
        channelDescription: 'Kayıtlı aramalarınıza uyan yeni kamu ilanları',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        tag: notification.eventId,
      ),
      iOS: const DarwinNotificationDetails(),
    ),
    payload: notification.tapPayload,
  );
}

/// Görülen URL'ler, sayaçlar ve hatırlatılanlar için ayar sarmalayıcı.
class AlertSettings {
  AlertSettings(this.store);

  final SettingsStore store;

  static Future<AlertSettings> load() async =>
      AlertSettings(await SettingsStore.load());

  static const _seenPrefix = 'kamubul.alerts.seen.';
  static const _digestPrefix = 'kamubul.alerts.digestDay.';

  Set<String> seenFor(int searchId) =>
      (store.getStringList('$_seenPrefix$searchId') ?? <String>[]).toSet();

  Future<void> saveSeen(int searchId, Set<String> urls) async {
    store.setStringList('$_seenPrefix$searchId', urls.toList());
  }

  int? digestDayFor(int searchId) => store.getInt('$_digestPrefix$searchId');

  Future<void> saveDigestDay(int searchId, int day) async {
    store.setInt('$_digestPrefix$searchId', day);
  }

  int get instantSentToday =>
      store.getInt('kamubul.alerts.instantDay') == DateTime.now().day
      ? (store.getInt('kamubul.alerts.instantCount') ?? 0)
      : 0;

  Future<void> addInstantSent(int count) async {
    store.setInt('kamubul.alerts.instantDay', DateTime.now().day);
    store.setInt('kamubul.alerts.instantCount', instantSentToday + count);
  }

  Set<String> get remindedUrls =>
      (store.getStringList('kamubul.alerts.reminded') ?? <String>[]).toSet();

  Future<void> markReminded(String url) async {
    store.setStringList('kamubul.alerts.reminded', [...remindedUrls, url]);
  }

  static const _historyKey = 'kamubul.alerts.history';
  static const _queueKey = 'kamubul.alerts.queue';

  /// Bildirim geçmişi (en yeni başta). Yalnızca bu cihazda tutulur.
  List<AlertRecord> history() => decodeAlerts(store.getString(_historyKey));

  Future<void> _saveHistory(List<AlertRecord> records) async {
    store.setString(_historyKey, encodeAlerts(records));
    await store.flush();
  }

  Future<void> appendHistory(AlertRecord record) async {
    await _saveHistory(appendAlert(history(), record));
  }

  /// Kaydı teslim edildi olarak işler; geçmiş temizlenmişse teslim kaydı
  /// eklenir ki bildirim kaybolmasın.
  Future<void> markHistoryDelivered(AlertRecord record, DateTime at) async {
    final current = history();
    final updated = current.any((item) => item.id == record.id)
        ? markAlertDelivered(current, record.id, at)
        : appendAlert(
            current,
            record
              ..delivery = AlertDelivery.delivered
              ..deliveredAt = at,
          );
    await _saveHistory(updated);
  }

  /// Geçmişi siler (C-021: kullanıcı verisini istediği an silebilir).
  Future<void> clearHistory() async {
    await _saveHistory(const []);
  }

  /// Sessiz saat/tavan nedeniyle ertelenmiş bildirimlerin kuyruğu.
  List<AlertRecord> pendingQueue() => decodeAlerts(store.getString(_queueKey));

  /// Kuyruğu yazar; sınırı aşan en eski kayıtlar "gönderilmedi" işaretlenir.
  Future<void> savePendingQueue(List<AlertRecord> queue) async {
    final dropped = trimmedQueueIds(queue);
    if (dropped.isNotEmpty) {
      await _saveHistory(markAlertDropped(history(), dropped));
    }
    store.setString(_queueKey, encodeAlerts(trimQueue(queue)));
    await store.flush();
  }
}

/// Kayıtlı aramalar + hatırlatıcılar için bir denetim turu; arka plan ve
/// ayarlardaki "şimdi denetle" aynı yolu kullanır. Dönen değer gönderim sayısı.
Future<int> runAlertCheckOnce() async {
  final store = ListingStore();
  final settings = await AlertSettings.load();
  final now = DateTime.now();
  var sent = 0;

  // Arka plan denetimi önce resmî kaynakları yeniler; yalnızca eski yerel
  // kayıtları taramak yeni ilan bildirimi üretemez.
  await refreshCatalogue(store, at: now);

  // Ertelenmiş bildirimler: sessiz saat dışındaki ilk denetimde günlük tavan
  // kadar gönderilir; kalanlar kuyrukta bekler, kaybolmaz.
  final queue = settings.pendingQueue();
  final flushing = planQueueFlush(
    queue: queue,
    now: now,
    quietStartHour: 22,
    quietEndHour: 8,
    maxInstantPerDay: 6,
    instantSentToday: settings.instantSentToday,
  );
  for (final record in flushing) {
    await showPendingNotification(
      PendingNotification(
        searchName: record.searchName,
        title: record.title,
        body: record.body,
        listingUrl: record.listingUrl,
        listingId: record.listingId,
        listingRevision: record.listingRevision,
      ),
    );
    await settings.markHistoryDelivered(record, now);
    sent++;
  }
  final queued = [...queue.skip(flushing.length)];
  if (flushing.isNotEmpty) await settings.addInstantSent(flushing.length);

  final searches = await store.savedSearches();
  // Denetim başına en fazla beş farklı şehir sorgulanır; daha fazlası için
  // sıralı tur işaretçisi ve kaynak başına kalıcı kota eklenmeli.
  final cities = searches
      .map((search) => search.filters['sehir']?.trim() ?? '')
      .where((city) => city.isNotEmpty)
      .toSet()
      .take(5);
  for (final city in cities) {
    try {
      await refreshKariyerCity(store, city);
    } on Exception {
      // Çevrimdışı durumda önceden doğrulanmış yerlerle devam edilir.
    }
  }
  final listings = await store.allListings();
  for (final search in searches) {
    final mode = alertModeOf(search.filters);
    final config = AlertConfig(
      now: now,
      quietStartHour: 22,
      quietEndHour: 8,
      maxInstantPerDay: 6,
      instantSentToday: settings.instantSentToday,
      digestSentDay: settings.digestDayFor(search.id!),
    );
    final decision = decideAlerts(
      search: search,
      listings: listings,
      previouslySeen: settings.seenFor(search.id!),
      config: config,
    );
    final kind = mode == SearchAlertMode.digest
        ? AlertKind.digest
        : AlertKind.instant;
    for (final notification in decision.notifications) {
      await showPendingNotification(notification);
      await settings.appendHistory(
        AlertRecord.create(
          kind: kind,
          searchName: notification.searchName,
          title: notification.title,
          body: notification.body,
          listingUrl: notification.listingUrl,
          createdAt: now,
          delivery: AlertDelivery.delivered,
          deliveredAt: now,
        ),
      );
      sent++;
    }
    for (final notification in decision.held) {
      final record = AlertRecord.create(
        kind: kind,
        searchName: notification.searchName,
        title: notification.title,
        body: notification.body,
        listingUrl: notification.listingUrl,
        createdAt: now,
      );
      queued.add(record);
      await settings.appendHistory(record);
    }
    if (mode == SearchAlertMode.instant && decision.notifications.isNotEmpty) {
      await settings.addInstantSent(decision.notifications.length);
    }
    if (mode == SearchAlertMode.digest && decision.notifications.isNotEmpty) {
      await settings.saveDigestDay(search.id!, now.day);
    }
    await settings.saveSeen(search.id!, decision.seenUrls);
  }
  for (final record in listings) {
    final reminder = deadlineReminder(
      record: record,
      alreadyReminded: settings.remindedUrls,
      now: now,
    );
    if (reminder == null) continue;
    await showPendingNotification(reminder);
    await settings.appendHistory(
      AlertRecord.create(
        kind: AlertKind.reminder,
        searchName: reminder.searchName,
        title: reminder.title,
        body: reminder.body,
        listingUrl: reminder.listingUrl,
        createdAt: now,
        delivery: AlertDelivery.delivered,
        deliveredAt: now,
      ),
    );
    sent++;
    await settings.markReminded(record.url);
  }
  await settings.savePendingQueue(queued);
  await store.close();
  return sent;
}

/// Ayarlar ekranındaki "şimdi denetle" eylemi.
Future<int> runAlertCheckNow() => runAlertCheckOnce();

/// Uygulama açılışında pil dostu arka plan denetimi (günde ~2 kez).
Future<void> registerBackgroundAlerts() async {
  if (kIsWeb) return;
  try {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      _backgroundTaskName,
      _backgroundTaskName,
      frequency: const Duration(hours: 12),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  } on Exception {
    // Arka plan zamanlaması platforma/işletim sistemine göre yok sayılabilir;
    // elle yenileme ve ayarlardaki denetim her zaman çalışır.
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await runAlertCheckOnce();
    return true;
  });
}
