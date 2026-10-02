import '../notifications/alert_history.dart';

/// Accepted-only server page; cursor and cached records must be saved together.
class NotificationHistoryPage {
  const NotificationHistoryPage(
    this.watermark,
    this.appliedThrough,
    this.hasMore,
    this.records,
  );
  final int watermark;
  final int appliedThrough;
  final bool hasMore;
  final List<AlertRecord> records;

  static NotificationHistoryPage decode(
    Object? raw, {
    required int after,
    int? expectedWatermark,
  }) {
    if (raw is! Map || raw['schemaVersion'] != 2) {
      throw const FormatException('notification history schema');
    }
    final watermark = raw['watermark'],
        applied = raw['appliedThrough'],
        more = raw['hasMore'],
        items = raw['items'];
    if (watermark is! int ||
        watermark < after ||
        watermark > 9007199254740991 ||
        applied is! int ||
        applied < after ||
        applied > watermark ||
        more is! bool ||
        more != (applied < watermark) ||
        items is! List ||
        items.length > 50 ||
        (expectedWatermark != null && watermark != expectedWatermark) ||
        raw['next'] != (more ? '$applied' : null)) {
      throw const FormatException('notification history cursor');
    }
    final records = <AlertRecord>[], ids = <String>{};
    var previous = after;
    for (final row in items) {
      if (row is! Map) throw const FormatException('notification history item');
      final seq = row['seq'],
          id = row['eventId'],
          delivery = row['deliveryId'],
          title = row['title'],
          url = row['url'],
          date = row['acceptedAt'],
          mode = row['mode'],
          count = row['digestCount'];
      final uri = url is String ? Uri.tryParse(url) : null;
      if (seq is! int ||
          seq <= previous ||
          seq > applied ||
          id is! String ||
          !RegExp(r'^[a-f\d]{64}$').hasMatch(id) ||
          !ids.add(id) ||
          delivery is! String ||
          !RegExp(r'^[a-f\d]{64}$').hasMatch(delivery) ||
          row['state'] != 'accepted' ||
          title is! String ||
          title.trim().isEmpty ||
          title.length > 300 ||
          url is! String ||
          url.length > 2048 ||
          uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          date is! String ||
          date.length > 40 ||
          !date.endsWith('Z') ||
          DateTime.tryParse(date) == null ||
          !['instant', 'digest'].contains(mode) ||
          (mode == 'digest' && (count is! int || count < 1 || count > 10))) {
        throw const FormatException('notification history identity');
      }
      final listingId = row['id'];
      if (listingId != null &&
          (listingId is! String ||
              listingId.isEmpty ||
              listingId.length > 200)) {
        throw const FormatException('notification listing identity');
      }
      records.add(
        AlertRecord(
          id: id,
          kind: mode == 'digest' ? AlertKind.digest : AlertKind.instant,
          searchName: '',
          title: title,
          body: mode == 'digest'
              ? 'Günlük özet • $count ilan'
              : 'Sunucu bildirimi',
          listingUrl: url,
          listingId: listingId as String?,
          createdAt: DateTime.parse(date).toLocal(),
          delivery: AlertDelivery.accepted,
        ),
      );
      previous = seq;
    }
    if ((items.isEmpty && more) || (items.isNotEmpty && previous != applied)) {
      throw const FormatException('notification history progress');
    }
    return NotificationHistoryPage(
      watermark,
      applied,
      more,
      List.unmodifiable(records),
    );
  }
}
