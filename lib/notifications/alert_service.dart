import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:napp_core/napp_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:workmanager/workmanager.dart';

import '../data/listing_store.dart';
import '../data/search_alerts.dart';

const _channelId = 'kamubul_alerts';
const _backgroundTaskName = 'kamubulRefreshAlerts';

final FlutterLocalNotificationsPlugin _plugin =
    FlutterLocalNotificationsPlugin();
bool _initialized = false;

Future<void> _ensureInitialized() async {
  if (_initialized) return;
  await _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
    onDidReceiveNotificationResponse: (response) {
      // Bildirim dokunuşu ilanın resmî sayfasını dışarıda açar.
      final url = response.payload;
      if (url != null) {
        final uri = Uri.tryParse(url);
        if (uri != null && uri.scheme == 'https') {
          launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    },
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
    id: notification.listingUrl.hashCode & 0x7fffffff,
    title: notification.title,
    body: notification.body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'İlan uyarıları',
        channelDescription: 'Kayıtlı aramalarınıza uyan yeni kamu ilanları',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: const DarwinNotificationDetails(),
    ),
    payload: notification.listingUrl,
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
}

/// Kayıtlı aramalar + hatırlatıcılar için bir denetim turu; arka plan ve
/// ayarlardaki "şimdi denetle" aynı yolu kullanır. Dönen değer gönderim sayısı.
Future<int> runAlertCheckOnce() async {
  final store = ListingStore();
  final settings = await AlertSettings.load();
  final listings = await store.allListings();
  final searches = await store.savedSearches();
  var sent = 0;
  for (final search in searches) {
    final mode = alertModeOf(search.filters);
    final config = AlertConfig(
      now: DateTime.now(),
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
    for (final notification in decision.notifications) {
      await showPendingNotification(notification);
      sent++;
    }
    if (mode == SearchAlertMode.instant && decision.notifications.isNotEmpty) {
      await settings.addInstantSent(decision.notifications.length);
    }
    if (mode == SearchAlertMode.digest && decision.notifications.isNotEmpty) {
      await settings.saveDigestDay(search.id!, DateTime.now().day);
    }
    await settings.saveSeen(search.id!, decision.seenUrls);
  }
  for (final record in listings) {
    final reminder = deadlineReminder(
      record: record,
      alreadyReminded: settings.remindedUrls,
      now: DateTime.now(),
    );
    if (reminder == null) continue;
    await showPendingNotification(reminder);
    sent++;
    await settings.markReminded(record.url);
  }
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
