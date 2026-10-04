import 'dart:convert';

import 'package:kamubul_core/kamubul_core.dart';

import 'listing_store.dart';
import 'remote_sync.dart';

const cataloguePruneAfter = Duration(days: 45);

/// Geçişte kaynak son başarısı bu eşiği geçtiyse eski yol devrede kalır.
const remoteSnapshotMaxAge = Duration(hours: 36);

class CatalogueRefreshResult {
  const CatalogueRefreshResult(
    this.checkedAt,
    this.failedSources, {
    this.sourceStatuses = const [],
    this.remoteLastSuccess,
    this.remoteFailed = false,
  });

  final DateTime checkedAt;
  final List<String> failedSources;

  /// Sunucunun bildirdiği kaynak durumları (uzak katalog kapalı ya da
  /// daha önce hiç okunamadıysa boş; hata halinde son başarılı kayıttan). Kaynaklar ekranı engel/erişim notlarını buradan gösterir.
  final List<SourceStatus> sourceStatuses;
  final DateTime? remoteLastSuccess;
  final bool remoteFailed;
}

/// Seçilen şehri resmî Kariyer Kapısı liste süzgeciyle doğrular.
Future<int> refreshKariyerCity(ListingStore store, String city) async {
  final canonical = canonicalCity(city);
  if (canonical == null) throw const FormatException('Geçersiz şehir adı');
  final items = await loadKariyerCityListings(canonical);
  await store.addVerifiedCity(
    canonical,
    items.map((item) => item.url.toString()),
  );
  return items.length;
}

/// Ekran, elle denetim ve arka plan görevi aynı yenileme yolunu kullanır.
///
/// Önce v2 metadata ve kalıcı cursor sonrası fark okunur (yapılandırılmışsa). Sunucu bir kaynağı
/// sağlayamıyorsa (engel, hata, bayat anlık görüntü) YALNIZCA o kaynak eski
/// gömülü yoldan cihazdan çekilir; sunucuya hiç ulaşılamazsa hepsi. Bir
/// kaynak bozulduğunda diğerleri ve mevcut yerel kayıtlar korunur.
Future<CatalogueRefreshResult> refreshCatalogue(
  ListingStore store, {
  Future<List<PublicListing>> Function()? kariyer,
  Future<List<SbbListing>> Function()? sbb,
  Future<List<IlanGovListing>> Function()? ilanGov,
  Future<List<IskurListing>> Function()? iskur,
  RemoteCatalogueClient? remote,
  DateTime? at,
}) async {
  final now = at ?? DateTime.now();
  final incoming = <ListingRecord>[];
  final failed = <String>[];
  var needKariyer = true;
  var needSbb = true;
  var statuses = const <SourceStatus>[];
  DateTime? remoteLastSuccess;
  var remoteFailed = false;

  final ownedClient = remote == null;
  final client = remote ?? defaultRemoteClient();
  if (client != null) {
    try {
      final generation = await store.bindRemoteOrigin(catalogueOrigin(client));
      final cached = await store.remoteMetadata(expectedGeneration: generation);
      remoteLastSuccess = cached.lastSuccess;
      if (cached.metadata != null) {
        try {
          statuses = CatalogueMetadata.decode(jsonDecode(cached.metadata!))
              .sources;
        } on FormatException {
          /* Keep listings even if cached metadata is corrupt. */
        }
      }
      final metadata = await syncRemoteV2Catalogue(
        store: store,
        client: client,
        now: now,
      );
      statuses = metadata.sources;
      remoteLastSuccess = now;
      bool available(String id) {
        final wireId = id == kSbbSourceId ? 'sbb' : id;
        final source =
            statuses.where((s) => s.id == wireId).firstOrNull ??
            statuses.where((s) => s.id == id).firstOrNull;
        final success = source?.lastSuccessAt;
        return source?.state == SourceState.ok &&
            success != null &&
            !success.isAfter(now) &&
            now.difference(success) <= remoteSnapshotMaxAge;
      }

      // Sunucu Kariyer Kapısı ayrıntı API'sine erişemiyor (Cloudflare 522);
      // yalnız RSS başlığı gelir. Son tarih/kontenjan/kurum için telefon
      // resmî dizini her zaman kendisi okur.
      needKariyer = true;
      needSbb = !available(kSbbSourceId);
    } on Exception {
      remoteFailed = true;
      // Sunucu ya da ağ yok: gömülü çekim tüm kaynakları kapsar.
    } finally {
      if (ownedClient) client.close();
    }
  }

  if (needKariyer) {
    try {
      final items = await (kariyer ?? loadKariyerListings)();
      incoming.addAll([for (final item in items) kariyerRecord(item, now)]);
    } on Exception {
      failed.add('Kariyer Kapısı');
    }
  }
  if (needSbb) {
    try {
      final items = await (sbb ?? loadSbbListings)();
      incoming.addAll([for (final item in items) sbbRecord(item, now)]);
    } on Exception {
      failed.add('Kamu İlanları (SBB)');
    }
  }
  // ilan.gov.tr (belediye, üniversite, Resmî Gazete personel ilanları)
  // sunucuda yok; telefon resmî API'den okur.
  try {
    final items = await (ilanGov ?? loadIlanGovListings)();
    incoming.addAll([for (final item in items) ilanGovRecord(item, now)]);
  } on Exception {
    failed.add('ilan.gov.tr');
  }
  // İŞKUR: yalnız kamu işyeri ilanları (özel sektör kapsam dışı).
  try {
    final items = await (iskur ?? loadIskurListings)();
    incoming.addAll([for (final item in items) iskurRecord(item, now)]);
  } on Exception {
    failed.add('İŞKUR');
  }
  if (incoming.isNotEmpty) {
    try {
      await store.mergeFeed(
        incoming,
        pruneBefore: now.subtract(cataloguePruneAfter),
      );
    } on Exception {
      failed.add('Yerel katalog');
    }
  }
  return CatalogueRefreshResult(
    now,
    failed,
    sourceStatuses: statuses,
    remoteLastSuccess: remoteLastSuccess,
    remoteFailed: remoteFailed,
  );
}
