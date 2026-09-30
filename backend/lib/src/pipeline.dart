/// Tek seferlik çalışma: kaynakları çek → birleştir → ayrıntı + (varsa) yapay
/// zekâ zenginleştirme → anlık görüntüyü yayınla → cihazlara bildirim planla
/// ve gönder. Çökme dayanıklılığı: bildirim bekleyen ilanlar anlık görüntü
/// yazılmadan ÖNCE duruma kaydedilir; iş yarıda kalırsa bir sonraki çalışma
/// bu ilanları tekrar bildirir (bildirim kaybı yerine az tekrar tercih edilir).
library;

import 'dart:async';

import 'package:kamubul_core/kamubul_core.dart';

import 'push.dart';
import 'sources.dart';
import 'storage.dart';

/// Bir cihaz kaydı bu kadar süredir güncellenmediyse silinir (uygulama her
/// açılışta kaydı tazeler; jeton ölmüş ya da uygulama kaldırılmıştır).
const Duration kStaleDeviceAfter = Duration(days: 120);

class PipelineDeps {
  PipelineDeps({
    required this.storage,
    required this.sources,
    required this.push,
    required this.detailLoader,
    this.enricher,
    this.detailFetchLimit = 60,
    this.requestDelay = const Duration(milliseconds: 400),
    DateTime Function()? clock,
    void Function(String)? log,
    Future<void> Function(Duration)? delay,
  }) : clock = clock ?? DateTime.now,
       log = log ?? ((_) {}),
       delay = delay ?? ((d) => Future<void>.delayed(d));

  final Storage storage;
  final List<SourceAdapter> sources;
  final PushSender push;
  final Future<KariyerDetail> Function(Uri) detailLoader;
  final AiEnricher? enricher;
  final int detailFetchLimit;
  final Duration requestDelay;

  /// UTC "şimdi"; test için değiştirilebilir.
  final DateTime Function() clock;
  final void Function(String) log;
  final Future<void> Function(Duration) delay;
}

class RunReport {
  int added = 0;
  int total = 0;
  int sourcesOk = 0;
  int sourcesFailed = 0;
  int detailFetched = 0;
  int detailFailed = 0;
  int aiEnriched = 0;
  int aiSkipped = 0;
  int pushSent = 0;
  int pushRequeued = 0;
  int devicesSeen = 0;
  int devicesRemoved = 0;
  int deviceErrors = 0;

  Map<String, Object?> toJson() => {
    'added': added,
    'total': total,
    'sourcesOk': sourcesOk,
    'sourcesFailed': sourcesFailed,
    'detailFetched': detailFetched,
    'detailFailed': detailFailed,
    'aiEnriched': aiEnriched,
    'aiSkipped': aiSkipped,
    'pushSent': pushSent,
    'pushRequeued': pushRequeued,
    'devicesSeen': devicesSeen,
    'devicesRemoved': devicesRemoved,
    'deviceErrors': deviceErrors,
  };
}

Future<RunReport> runPipeline(PipelineDeps deps) async {
  final report = RunReport();
  final nowUtc = deps.clock();
  final now = wallClock(nowUtc);

  // ---- önceki durum
  var previousListings = <ListingRecord>[];
  var previousStatuses = <String, SourceStatus>{};
  final rawSnapshot = await deps.storage.readSnapshot();
  if (rawSnapshot != null) {
    try {
      final previous = CatalogueSnapshot.decode(rawSnapshot);
      previousListings = previous.listings;
      previousStatuses = {for (final s in previous.sources) s.id: s};
    } on SnapshotFormatException catch (error) {
      deps.log('önceki anlık görüntü okunamadı: ${error.message}');
    }
  }
  final state = await deps.storage.readState() ?? <String, Object?>{};
  final detailed = <String>{...?_strings(state['detailed'])};
  final aiRetry = _counts(state['aiRetry']);
  final detailFails = _counts(state['detailFails']);
  final pendingPush = <String>{...?_strings(state['pendingPush'])};

  // ---- kaynaklar
  final statuses = <SourceStatus>[];
  final incoming = <ListingRecord>[];
  for (final adapter in deps.sources) {
    final outcome = await adapter.run(now, previousStatuses[adapter.id]);
    statuses.add(outcome.status);
    if (adapter.providesListings) {
      if (outcome.status.state == SourceState.ok) {
        report.sourcesOk++;
        incoming.addAll(outcome.listings);
      } else {
        report.sourcesFailed++;
      }
    }
    deps.log(
      'kaynak ${adapter.id}: ${outcome.status.state.name} '
      '(${outcome.listings.length} kayıt)',
    );
  }
  for (final old in previousStatuses.values) {
    if (statuses.every((s) => s.id != old.id)) statuses.add(old);
  }

  // ---- birleştirme
  final merge = mergeCatalogue(
    previous: previousListings,
    incoming: incoming,
    now: now,
  );
  final byUrl = {for (final record in merge.listings) record.url: record};
  report.added = merge.added.length;
  pendingPush.addAll(merge.added.map((r) => r.url));

  // ---- ayrıntı + zenginleştirme (yalnızca Kariyer; SBB ayrıntısı PDF'tir)
  final addedUrls = {for (final r in merge.added) r.url};
  final candidates =
      byUrl.values
          .where(
            (r) =>
                r.sourceId == kKariyerSourceId &&
                (!detailed.contains(r.url) || aiRetry.containsKey(r.url)),
          )
          .toList()
        ..sort((a, b) {
          final byAdded =
              (addedUrls.contains(b.url) ? 1 : 0) -
              (addedUrls.contains(a.url) ? 1 : 0);
          return byAdded != 0
              ? byAdded
              : (b.publishedAt ?? b.fetchedAt).compareTo(
                  a.publishedAt ?? a.fetchedAt,
                );
        });
  for (final candidate in candidates.take(deps.detailFetchLimit)) {
    await deps.delay(deps.requestDelay);
    try {
      final detail = await deps.detailLoader(Uri.parse(candidate.url));
      report.detailFetched++;
      final text = [
        detail.body,
        for (final position in detail.positions) position.conditions,
      ].join('\n');
      var conditions = extractConditions(text);
      var summary = candidate.summary;
      final enricher = deps.enricher;
      if (enricher != null) {
        final result = await enricher.enrich(
          title: candidate.title,
          text: text,
        );
        if (result.status == AiStatus.ok) {
          report.aiEnriched++;
          conditions = mergeConditions(conditions, result.enrichment);
          final bullets = result.enrichment!.summary
              .map((b) => b.text)
              .toList();
          if (bullets.isNotEmpty) summary = bullets;
          aiRetry.remove(candidate.url);
        } else if (result.status == AiStatus.failed ||
            result.status == AiStatus.budgetExhausted) {
          final attempts = (aiRetry[candidate.url] ?? 0) + 1;
          if (attempts < 3) {
            aiRetry[candidate.url] = attempts;
          } else {
            aiRetry.remove(candidate.url);
          }
          report.aiSkipped++;
        } else {
          aiRetry.remove(candidate.url);
          report.aiSkipped++;
        }
      }
      var record = candidate.copyWith(
        deadline: detail.deadline,
        quota: detail.quota > 0 ? detail.quota : null,
        places: detail.places.isNotEmpty ? detail.places : null,
        summary: summary,
      );
      record = applyConditionFields(record, conditions);
      byUrl[candidate.url] = record;
      detailed.add(candidate.url);
      detailFails.remove(candidate.url);
    } on Exception catch (error) {
      report.detailFailed++;
      final fails = (detailFails[candidate.url] ?? 0) + 1;
      if (fails >= 3) {
        // Kalıcı okunamayan ilan sonsuza dek yeniden denenmez.
        detailed.add(candidate.url);
        detailFails.remove(candidate.url);
      } else {
        detailFails[candidate.url] = fails;
      }
      deps.log('ayrıntı okunamadı ${candidate.url}: $error');
    }
  }
  final finalListings = [
    for (final record in merge.listings) byUrl[record.url] ?? record,
  ];
  report.total = finalListings.length;
  detailed.removeWhere((url) => !byUrl.containsKey(url));

  // ---- bekleyen push'u ve durumu yaz, sonra anlık görüntüyü yayınla
  pendingPush.removeWhere((url) => !byUrl.containsKey(url));
  Future<void> saveState() => deps.storage.writeState({
    'detailed': detailed.toList(),
    'aiRetry': aiRetry,
    'detailFails': detailFails,
    'pendingPush': pendingPush.toList(),
  });
  await saveState();
  await deps.storage.writeSnapshot(
    CatalogueSnapshot(
      generatedAt: now,
      sources: statuses,
      listings: finalListings,
    ).encode(),
  );

  // ---- bildirim
  final newListings = [for (final url in pendingPush) ?byUrl[url]];
  await _notify(deps, newListings, report);
  pendingPush.clear();
  await saveState();
  deps.log('çalışma bitti: ${report.toJson()}');
  return report;
}

Iterable<String>? _strings(Object? raw) =>
    raw is List ? raw.whereType<String>() : null;

Map<String, int> _counts(Object? raw) => raw is Map
    ? {
        for (final entry in raw.entries)
          if (entry.key is String && entry.value is int)
            entry.key as String: entry.value as int,
      }
    : <String, int>{};

Future<void> _notify(
  PipelineDeps deps,
  List<ListingRecord> newListings,
  RunReport report,
) async {
  const concurrency = 25;
  final batch = <DeviceRecord>[];
  Future<void> flush() async {
    if (batch.isEmpty) return;
    final current = List<DeviceRecord>.of(batch);
    batch.clear();
    await Future.wait(
      current.map((d) => _notifyDevice(deps, d, newListings, report)),
    );
  }

  await for (final device in deps.storage.devices()) {
    report.devicesSeen++;
    if (nowIsStale(deps.clock(), device)) {
      try {
        await deps.storage.deleteDevice(device.id);
        report.devicesRemoved++;
      } on Exception {
        report.deviceErrors++;
      }
      continue;
    }
    // Yeni ilan yok ve kuyruk boşsa bu cihazda yapılacak iş yoktur.
    if (newListings.isEmpty && device.state.queue.isEmpty) continue;
    batch.add(device);
    if (batch.length >= concurrency) await flush();
  }
  await flush();
}

bool nowIsStale(DateTime nowUtc, DeviceRecord device) =>
    nowUtc.difference(device.updatedAt.toUtc()) > kStaleDeviceAfter;

Future<void> _notifyDevice(
  PipelineDeps deps,
  DeviceRecord device,
  List<ListingRecord> newListings,
  RunReport report,
) async {
  try {
    final nowWall = wallClock(
      deps.clock(),
      utcOffsetMinutes: device.registration.utcOffsetMinutes,
    );
    final plan = planDevicePush(
      device: device.registration,
      newListings: newListings,
      state: device.state,
      nowWall: nowWall,
    );
    var state = plan.state;
    final requeue = <PendingNotification>[];
    var instantSent = state.instantSentToday;
    for (final item in plan.toSend) {
      final outcome = await deps.push.send(
        PushMessage(
          token: device.registration.fcmToken,
          title: item.title,
          body: item.body,
          url: item.listingUrl,
          digest: item.digest,
        ),
      );
      switch (outcome) {
        case PushOutcome.sent:
          report.pushSent++;
        case PushOutcome.invalidToken:
          await deps.storage.deleteDevice(device.id);
          report.devicesRemoved++;
          return;
        case PushOutcome.failed:
          // Geçici hata: bildirim kuyruğa döner, sayaçtan düşer.
          requeue.add(item);
          if (!item.digest && instantSent > 0) instantSent--;
          report.pushRequeued++;
      }
    }
    if (requeue.isNotEmpty || instantSent != state.instantSentToday) {
      state = DevicePushState(
        sentDay: state.sentDay,
        instantSentToday: instantSent,
        digestSentDay: state.digestSentDay,
        queue: [...requeue, ...state.queue].take(kMaxPushQueue).toList(),
      );
    }
    final updated = device.copyWith(state: state);
    if (updated.encode() != device.encode()) {
      await deps.storage.putDevice(updated);
    }
  } on Exception catch (error) {
    report.deviceErrors++;
    deps.log('cihaz ${device.id} işlenemedi: ${error.runtimeType}');
  }
}
