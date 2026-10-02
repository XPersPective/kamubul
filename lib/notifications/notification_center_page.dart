import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/premium.dart';
import 'alert_history.dart';
import 'alert_service.dart';
import 'push_setup.dart';

/// Bildirim geçmişi: gönderilen, bekleyen ve gönderilmeyen tüm uyarılar.
///
/// Yerel uyarılar ve anonim aboneliğin sunucu geçmişi cache'ten gösterilir.
/// Sunucu kabulü cihaz teslimi olarak etiketlenmez; temizleme yerel görünümü siler.
class NotificationCenterPage extends StatefulWidget {
  const NotificationCenterPage({super.key});

  @override
  State<NotificationCenterPage> createState() => _NotificationCenterPageState();
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  List<AlertRecord> _history = [];
  bool _loading = true;
  bool _historyFailed = false;
  List<AlertRecord> _localHistory = [];
  StreamSubscription<void>? _historyChanges;

  @override
  void initState() {
    super.initState();
    _historyChanges = pushRegistrar?.onHistoryChanged.listen((_) {
      if (mounted && !_loading) {
        setState(() => _history = _cachedHistory());
      }
    });
    _load();
  }

  List<AlertRecord> _cachedHistory() =>
      [..._localHistory, ...?pushRegistrar?.notificationHistory]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  void dispose() {
    _historyChanges?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await AlertSettings.load();
    if (!mounted) return;
    setState(() {
      _localHistory = settings.history();
      _history = _cachedHistory();
      _loading = false;
    });
    final registrar = pushRegistrar;
    if (registrar != null && registrar.enabled) {
      final success = await registrar.syncHistory();
      if (mounted) {
        setState(() {
          _historyFailed = !success;
          _history = _cachedHistory();
        });
      }
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bildirim geçmişi silinsin mi?'),
        content: const Text(
          'Bu cihazdaki tüm bildirim kayıtları silinir. Kayıtlı '
          'aramalarınız ve süzgeçleriniz etkilenmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final settings = await AlertSettings.load();
    await settings.clearHistory();
    _localHistory = [];
    await pushRegistrar?.clearNotificationHistory();
    if (!mounted) return;
    setState(() => _history = const []);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Bildirim geçmişi silindi.')));
  }

  Future<void> _open(AlertRecord record) async {
    if (record.listingId != null && decodeAlertTap(record.tapPayload) != null) {
      Navigator.of(context).pop();
      openAlertUrl(record.tapPayload);
      return;
    }
    // Yalnızca https bağlantıları dışarıda açılır (C-020).
    final uri = Uri.tryParse(record.listingUrl);
    if (uri == null || uri.scheme != 'https') return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirimler'),
        bottom: _historyFailed
            ? const PreferredSize(
                preferredSize: Size.fromHeight(64),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Sunucu geçmişi yenilenemedi. Yerel kayıtlar gösteriliyor.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
            : null,
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              tooltip: 'Geçmişi temizle',
              onPressed: _clear,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
          ? const _EmptyHistory()
          : ListView(
              children: [
                for (final entry in _dayGroups(_history)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      entry.key,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  for (final record in entry.value) _tile(record),
                ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _tile(AlertRecord record) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          switch (record.kind) {
            AlertKind.instant => Icons.notifications_none,
            AlertKind.digest => Icons.view_agenda_outlined,
            AlertKind.reminder => Icons.schedule,
          },
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(record.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(record.body, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _timeLabel(record.createdAt),
                style: theme.textTheme.labelSmall,
              ),
              _Badge(record: record),
            ],
          ),
        ],
      ),
      trailing: record.listingUrl.startsWith('https')
          ? const Icon(Icons.open_in_new, size: 18)
          : null,
      onTap: record.listingUrl.startsWith('https') ? () => _open(record) : null,
    );
  }

  /// Kayıtları takvim gününe göre (en yeni önce) gruplar.
  List<MapEntry<String, List<AlertRecord>>> _dayGroups(
    List<AlertRecord> records,
  ) {
    final groups = <String, List<AlertRecord>>{};
    for (final record in records) {
      (groups[_dayLabel(record.createdAt)] ??= []).add(record);
    }
    return groups.entries.toList();
  }

  String _dayLabel(DateTime time) {
    final now = DateTime.now();
    final day = DateTime(time.year, time.month, time.day);
    final today = DateTime(now.year, now.month, now.day);
    final difference = today.difference(day).inDays;
    if (difference == 0) return 'Bugün';
    if (difference == 1) return 'Dün';
    return '${time.day} ${_monthName(time.month)} ${time.year}';
  }

  String _timeLabel(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  String _monthName(int month) => const [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ][month - 1];
}

class _Badge extends StatelessWidget {
  const _Badge({required this.record});

  final AlertRecord record;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final (label, color) = switch (record.delivery) {
      AlertDelivery.accepted => (
        'Servise iletildi',
        PremiumStatus.held(brightness),
      ),
      AlertDelivery.received => ('Alındı', PremiumStatus.delivered(brightness)),
      AlertDelivery.delivered => (
        'Gönderildi',
        PremiumStatus.delivered(brightness),
      ),
      AlertDelivery.held => ('Beklemede', PremiumStatus.held(brightness)),
      AlertDelivery.dropped => (
        'Gönderilmedi',
        PremiumStatus.dropped(brightness),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(PremiumShape.chipRadius),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('Henüz bildirim yok', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Kayıtlı aramalarınıza uyan yeni ilanlar ve son başvuru '
              'hatırlatıcıları burada görünür. Sessiz saatlerde (22:00-08:00) '
              'bulunan ilanlar kaybolmaz, beklemeye alınır.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
