import 'dart:convert';

int _alertIdSeed = 0;

/// Bildirim türü; geçmişte kullanıcıya ne için uyarı geldiğini gösterir.
enum AlertKind {
  /// Kayıtlı aramaya uyan yeni ilan.
  instant,

  /// Kayıtlı aramanın günlük özeti.
  digest,

  /// Kaydedilen ilanın son başvuru hatırlatıcısı.
  reminder;

  static AlertKind parse(String? raw) => switch (raw) {
    'digest' => AlertKind.digest,
    'reminder' => AlertKind.reminder,
    _ => AlertKind.instant,
  };
}

/// Bildirimin kullanıcıya ulaşma durumu; dürüst geri bildirim için ayrılır.
enum AlertDelivery {
  /// FCM sunucusu kabul etti; cihaz teslimi bilinmiyor.
  accepted,

  /// Uygulama FCM mesajını aldı; sistem sunumu ayrıca en iyi çabadır.
  received,

  /// Sistem bildirimi olarak gönderildi.
  delivered,

  /// Sessiz saat ya da günlük tavan nedeniyle kuyruğa alındı.
  held,

  /// Kuyruk sınırı aşıldığı için hiç gönderilmedi.
  dropped;

  static AlertDelivery parse(String? raw) => switch (raw) {
    'accepted' => AlertDelivery.accepted,
    'received' => AlertDelivery.received,
    'delivered' => AlertDelivery.delivered,
    'dropped' => AlertDelivery.dropped,
    _ => AlertDelivery.held,
  };
}

/// Bildirim geçmişinin tek kaydı ve ertelenmiş kuyruğun elemanı.
class AlertRecord {
  AlertRecord({
    required this.id,
    required this.kind,
    required this.searchName,
    required this.title,
    required this.body,
    required this.listingUrl,
    required this.createdAt,
    this.delivery = AlertDelivery.held,
    this.deliveredAt,
  });

  /// Benzersiz kimlik üreten kurucu: mikro zaman damgası + süreç içi sayaç.
  factory AlertRecord.create({
    required AlertKind kind,
    required String searchName,
    required String title,
    required String body,
    required String listingUrl,
    DateTime? createdAt,
    AlertDelivery delivery = AlertDelivery.held,
    DateTime? deliveredAt,
  }) {
    final created = createdAt ?? DateTime.now();
    return AlertRecord(
      id: '${created.microsecondsSinceEpoch}-${_alertIdSeed++}',
      kind: kind,
      searchName: searchName,
      title: title,
      body: body,
      listingUrl: listingUrl,
      createdAt: created,
      delivery: delivery,
      deliveredAt: deliveredAt,
    );
  }

  final String id;
  final AlertKind kind;
  final String searchName;
  final String title;
  final String body;

  /// İlanın resmî bağlantısı; yalnızca https açılır.
  final String listingUrl;
  final DateTime createdAt;
  AlertDelivery delivery;
  DateTime? deliveredAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'searchName': searchName,
    'title': title,
    'body': body,
    'listingUrl': listingUrl,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'delivery': delivery.name,
    'deliveredAt': deliveredAt?.millisecondsSinceEpoch,
  };

  /// Bozuk alanlar tek kaydı düşürür; uygulama çökmez.
  static AlertRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final createdAt = raw['createdAt'];
    if (id is! String || createdAt is! int) return null;
    String text(Object? value) => value is String ? value : '';
    return AlertRecord(
      id: id,
      kind: AlertKind.parse(text(raw['kind'])),
      searchName: text(raw['searchName']),
      title: text(raw['title']),
      body: text(raw['body']),
      listingUrl: text(raw['listingUrl']),
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
      delivery: AlertDelivery.parse(text(raw['delivery'])),
      deliveredAt: raw['deliveredAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(raw['deliveredAt'] as int)
          : null,
    );
  }
}

/// Yeni kaydı geçmişin başına ekler; kayıt sayısı [limit] ile sınırlıdır.
List<AlertRecord> appendAlert(
  List<AlertRecord> history,
  AlertRecord record, {
  int limit = 200,
}) {
  final updated = [record, ...history.where((item) => item.id != record.id)];
  return updated.length > limit ? updated.sublist(0, limit) : updated;
}

/// Kaydı teslim edildi olarak işaretler; [id] yoksa geçmiş değişmez.
List<AlertRecord> markAlertDelivered(
  List<AlertRecord> history,
  String id,
  DateTime at,
) => [
  for (final item in history)
    if (item.id == id)
      (item
        ..delivery = AlertDelivery.delivered
        ..deliveredAt = at)
    else
      item,
];

/// Kayıtları hiç gönderilmemiş olarak işaretler (kuyruk taşması).
List<AlertRecord> markAlertDropped(
  List<AlertRecord> history,
  Iterable<String> ids,
) {
  final dropped = ids.toSet();
  return [
    for (final item in history)
      if (dropped.contains(item.id))
        (item..delivery = AlertDelivery.dropped)
      else
        item,
  ];
}

String encodeAlerts(List<AlertRecord> records) =>
    jsonEncode([for (final record in records) record.toJson()]);

/// Bozuk JSON boş geçmiş okunur; kayıt kaybı uygulamayı durdurmaz.
List<AlertRecord> decodeAlerts(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded.map(AlertRecord.fromJson).nonNulls.toList();
  } on FormatException {
    return [];
  }
}

/// Sessiz saat aralığı: [startHour] dahil, [endHour] hariç.
bool isQuietHour(DateTime now, int startHour, int endHour) {
  final hour = now.hour;
  return startHour > endHour
      ? hour >= startHour || hour < endHour
      : hour >= startHour && hour < endHour;
}

/// Kuyruktaki ertelenmiş bildirimlerden şimdi gönderilebilecekler (FIFO).
/// Sessiz saatte boş döner; değilse kalan günlük tavan kadar eleman alır.
List<AlertRecord> planQueueFlush({
  required List<AlertRecord> queue,
  required DateTime now,
  required int quietStartHour,
  required int quietEndHour,
  required int maxInstantPerDay,
  required int instantSentToday,
}) {
  if (isQuietHour(now, quietStartHour, quietEndHour)) return const [];
  final room = (maxInstantPerDay - instantSentToday).clamp(0, queue.length);
  return queue.take(room).toList();
}

/// Kuyruk sınırını uygular: taşan en eski kayıtların kimlikleri döner.
List<AlertRecord> trimQueue(List<AlertRecord> queue, {int limit = 50}) =>
    queue.length > limit ? queue.sublist(0, limit) : queue;

/// [trimQueue] ile düşen kayıtların kimlikleri.
List<String> trimmedQueueIds(List<AlertRecord> queue, {int limit = 50}) =>
    queue.length > limit
    ? [for (final item in queue.sublist(limit)) item.id]
    : const [];
