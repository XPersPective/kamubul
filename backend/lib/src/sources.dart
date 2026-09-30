/// Resmî kaynak adaptörleri. Her adaptör dürüst bir [SourceStatus] üretir:
/// başarısızlık gizlenmez, önceki başarı zamanı korunur. Erişim engelleri
/// (WAF, oturum, coğrafya) engel olarak kaydedilir; aşılmaya çalışılmaz.
library;

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:kamubul_core/kamubul_core.dart';

class SourceOutcome {
  const SourceOutcome(this.status, [this.listings = const []]);

  final SourceStatus status;
  final List<ListingRecord> listings;
}

abstract class SourceAdapter {
  String get id;
  String get name;

  /// Ayrıştırıcısı olmayan kaynaklar yalnızca durum bildirir.
  bool get providesListings => true;

  Future<SourceOutcome> run(DateTime now, SourceStatus? previous);
}

String _describe(Object error) {
  final text = '$error';
  return text.length > 200 ? text.substring(0, 200) : text;
}

SourceOutcome _failed(
  SourceAdapter adapter,
  DateTime now,
  SourceStatus? previous,
  Object error,
) => SourceOutcome(
  SourceStatus(
    id: adapter.id,
    name: adapter.name,
    state: SourceState.failed,
    lastAttemptAt: now,
    lastSuccessAt: previous?.lastSuccessAt,
    listingCount: previous?.listingCount ?? 0,
    note: _describe(error),
  ),
);

class KariyerSource implements SourceAdapter {
  KariyerSource({Future<List<PublicListing>> Function()? loader})
    : _loader = loader ?? (() => loadKariyerListings());

  final Future<List<PublicListing>> Function() _loader;

  @override
  String get id => kKariyerSourceId;
  @override
  String get name => 'Kariyer Kapısı';
  @override
  bool get providesListings => true;

  @override
  Future<SourceOutcome> run(DateTime now, SourceStatus? previous) async {
    try {
      final items = await _loader();
      final records = [for (final item in items) kariyerRecord(item, now)];
      return SourceOutcome(
        SourceStatus(
          id: id,
          name: name,
          state: SourceState.ok,
          lastAttemptAt: now,
          lastSuccessAt: now,
          listingCount: records.length,
        ),
        records,
      );
    } on Exception catch (error) {
      return _failed(this, now, previous, error);
    }
  }
}

class SbbSource implements SourceAdapter {
  SbbSource({Future<List<SbbListing>> Function()? loader})
    : _loader = loader ?? (() => loadSbbListings());

  final Future<List<SbbListing>> Function() _loader;

  @override
  String get id => kSbbSourceId;
  @override
  String get name => 'Kamu İlanları (SBB)';
  @override
  bool get providesListings => true;

  @override
  Future<SourceOutcome> run(DateTime now, SourceStatus? previous) async {
    try {
      final items = await _loader();
      final records = [for (final item in items) sbbRecord(item, now)];
      return SourceOutcome(
        SourceStatus(
          id: id,
          name: name,
          state: SourceState.ok,
          lastAttemptAt: now,
          lastSuccessAt: now,
          listingCount: records.length,
        ),
        records,
      );
    } on Exception catch (error) {
      return _failed(this, now, previous, error);
    }
  }
}

/// Ayrıştırıcısı olmayan kaynağa günde birkaç kez TEK anonim GET atar ve
/// sonucu dürüstçe kaydeder (engel mi, erişilebilir mi). Oturum, CAPTCHA ya
/// da WAF aşılmaz; yalnızca herkese açık ana sayfa istenir.
class ProbeSource implements SourceAdapter {
  ProbeSource({
    required this.id,
    required this.name,
    required this.url,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  @override
  final String id;
  @override
  final String name;
  final Uri url;
  final Duration timeout;
  final http.Client _client;

  @override
  bool get providesListings => false;

  @override
  Future<SourceOutcome> run(DateTime now, SourceStatus? previous) async {
    SourceStatus status(SourceState state, String note) => SourceStatus(
      id: id,
      name: name,
      state: state,
      lastAttemptAt: now,
      lastSuccessAt: previous?.lastSuccessAt,
      note: note,
    );
    try {
      final response = await _client
          .get(url, headers: {'Accept': 'text/html'})
          .timeout(timeout);
      final body = response.body.length > 4000
          ? response.body.substring(0, 4000)
          : response.body;
      final rejected =
          response.statusCode == 403 ||
          response.statusCode == 401 ||
          body.contains('Request Rejected');
      if (rejected) {
        return SourceOutcome(
          status(
            SourceState.blocked,
            'HTTP ${response.statusCode}: erişim engeli (WAF/oturum); aşılmaz',
          ),
        );
      }
      if (response.statusCode == 200) {
        return SourceOutcome(
          SourceStatus(
            id: id,
            name: name,
            state: SourceState.disabled,
            lastAttemptAt: now,
            lastSuccessAt: now,
            note: 'Ana sayfa erişilebilir; ilan ayrıştırıcısı henüz yok',
          ),
        );
      }
      return SourceOutcome(
        status(
          SourceState.blocked,
          'HTTP ${response.statusCode}: liste uç noktası kullanılamıyor',
        ),
      );
    } on TimeoutException {
      return SourceOutcome(status(SourceState.failed, 'zaman aşımı'));
    } on Exception catch (error) {
      return SourceOutcome(status(SourceState.failed, _describe(error)));
    }
  }
}
