import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:kamubul/main.dart' as app;
import 'package:napp_ads/napp_ads.dart';
import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';

/// PB-008 girdi yanıtı ölçümü: dokunuş gönderiminden, dokunuşa yanıt veren
/// ilk karenin ekrana çizilmesine (raster bitişi) kadar geçen gerçek süre.
/// En yavaş derleme (debug) ile ölçülür; release bunun altındadır.
class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw const SocketException('test: ağ kapalı');
}

class _FakeStore implements StoreAdapter {
  @override
  Future<List<StoreProduct>> queryProducts(Set<String> productIds) async =>
      const [];

  @override
  Future<void> buy(StoreProduct product) async {}

  @override
  Future<void> restore() async {}

  @override
  Stream<List<StorePurchaseUpdate>> get updates => const Stream.empty();
}

/// Bir ölçümün parçaları: dokunuştan kare kurulumuna, karenin raster
/// süresi ve motorun zamanlama raporuna kadar geçen duvar süreleri.
class TapLatency {
  const TapLatency({
    required this.tapToBuildMs,
    required this.rasterMs,
    required this.reportLagMs,
  });

  final double tapToBuildMs;
  final double rasterMs;
  final double reportLagMs;

  /// Kullanıcının gördüğü yanıt: ilk karenin kurulumu + ekrana çizilmesi.
  double get visibleResponseMs => tapToBuildMs + rasterMs;

  @override
  String toString() =>
      'kurulum ${tapToBuildMs.toStringAsFixed(1)}ms + raster '
      '${rasterMs.toStringAsFixed(1)}ms (yanıt '
      '${visibleResponseMs.toStringAsFixed(1)}ms, rapor gecikmesi '
      '${reportLagMs.toStringAsFixed(1)}ms)';
}

/// Dokunuş gönderiminden ilk yanıt karesinin raster bitişine kadar ölçülen
/// gerçek süre; motor raporundaki zaman damgalarından hesaplanır, raporun
/// gecikmesi sonuca girmez.
Future<TapLatency> tapToFirstFrameMs(WidgetTester tester, Finder finder) async {
  // Önceki karelerin raporu ölçüme karışmasın: önce sakinleş.
  await Future<void>.delayed(const Duration(milliseconds: 150));
  final timings = <FrameTiming>[];
  void onTimings(List<FrameTiming> batch) => timings.addAll(batch);

  WidgetsBinding.instance.addTimingsCallback(onTimings);
  final stopwatch = Stopwatch()..start();
  await tester.tap(finder);
  await tester.pump();
  final tapToBuildMs = stopwatch.elapsedMicroseconds / 1000.0;
  while (timings.isEmpty) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  stopwatch.stop();
  WidgetsBinding.instance.removeTimingsCallback(onTimings);
  final timing = timings.first;
  return TapLatency(
    tapToBuildMs: tapToBuildMs,
    rasterMs: timing.rasterDuration.inMicroseconds / 1000.0,
    reportLagMs: stopwatch.elapsedMicroseconds / 1000.0 - tapToBuildMs,
  );
}

/// Örneklerin medyanı; tek ani sıçramanın sonucu bozmaması için.
double median(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('girdi yanıtı her hedefte 100ms altında', (tester) async {
    HttpOverrides.global = _NoNetwork();
    final settings = SettingsStore();
    // Doğrudan ana ekran: onboarding akışı ölçümün parçası değil.
    settings.setInt('kamubul.onboarded', 1);
    final theme = ThemeModeController(store: settings)..load();
    final policy = AdPolicy();
    final purchase = PurchaseRepository(
      adapter: _FakeStore(),
      productId: 'kamubul_pro_lifetime',
    );
    final pro = ProController(store: settings, repository: purchase)..load();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    await ListingStore().mergeFeed(
      [
        ListingRecord(
          url: 'https://kariyerkapisi.gov.tr/ilan/olcu-$stamp',
          sourceId: 'kariyerkapisi',
          title: 'ÖLÇÜM KURUMU - Sözleşmeli Personel Alım İlanı ($stamp)',
          category: 'Sözleşmeli Personel',
          publishedAt: DateTime.now(),
          fetchedAt: DateTime.now(),
          deadline: DateTime.now().add(const Duration(days: 3)),
          quota: 5,
          places: const ['ANKARA'],
        ),
      ],
      // Cihaz veritabanındaki eski deneme kayıtları listeyi kaydırmasın:
      // kaydedilmemiş eskiler budanır; bu kayıt taze olduğu için kalır.
      pruneBefore: DateTime.now().subtract(const Duration(seconds: 5)),
    );

    await tester.pumpWidget(
      app.KamuBulApp(
        identity: AppIdentity(
          appName: 'KamuBul',
          packageName: 'com.crazypenguin.kamubul',
          sourceUrl: 'https://kariyerkapisi.gov.tr',
          privacyPolicyUrl: 'https://kariyerkapisi.gov.tr/gizlilik',
          contactEmail: 'test@example.com',
          iconAsset: 'assets/brand/kamubul_icon.png',
          brandColor: const Color(0xFF17659C),
        ),
        store: settings,
        theme: theme,
        pro: pro,
        purchase: purchase,
        policy: policy,
        banner: BannerAdController(policy: policy),
        rewarded: RewardedAdManager(policy: policy),
        saveAdState: () {},
      ),
    );

    // Yerel katalog yüklenene dek bekle (süre sınırı sonsuz döngüye karşı).
    final listingTitle = find.text(
      'ÖLÇÜM KURUMU - Sözleşmeli Personel Alım İlanı ($stamp)',
    );
    var waited = 0;
    while (listingTitle.evaluate().isEmpty && waited < 30000) {
      await tester.pump(const Duration(milliseconds: 50));
      waited += 50;
    }
    if (listingTitle.evaluate().isEmpty) {
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '?')
          .toList();
      final rows = await ListingStore().allListings();
      // ignore: avoid_print
      print('TANI görünür metinler: $texts');
      // ignore: avoid_print
      print('TANI DB kayıtları: ${rows.map((r) => r.title).toList()}');
    }
    expect(listingTitle, findsOneWidget, reason: 'yerel katalog yüklenemedi');

    final results = <String, List<TapLatency>>{};
    void record(String target, TapLatency latency) =>
        results[target] = [...results[target] ?? [], latency];

    for (var round = 0; round < 3; round++) {
      // Süzgeç çipi: yalnızca setState ile anında geri bildirim.
      final chip = find.byType(ChoiceChip).first;
      expect(chip, findsWidgets);
      await tester.ensureVisible(chip);
      await tester.pump(const Duration(milliseconds: 200));
      record('süzgeç çipi', await tapToFirstFrameMs(tester, chip));
      // Sekme değişimi: yeni sayfa gövdesi ilk karede kurulur.
      final settingsTab = find.text('Ayarlar');
      expect(settingsTab, findsWidgets);
      record(
        'Ayarlar sekmesi',
        await tapToFirstFrameMs(tester, settingsTab),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('İlanlar'));
      await tester.pump(const Duration(milliseconds: 300));
      // Liste → ayrıntı: geçişin ilk karesi (yay geçişi başlar).
      final inspect = find
          .widgetWithText(FilledButton, 'İlanı incele')
          .first;
      expect(inspect, findsWidgets);
      await tester.ensureVisible(inspect);
      await tester.pump(const Duration(milliseconds: 200));
      record('ilan ayrıntısı', await tapToFirstFrameMs(tester, inspect));
      await tester.pump(const Duration(milliseconds: 300));
      // Geri: standart olmayan başlık çubuklarına karşı üç yol.
      final back = find.byType(BackButton);
      if (back.evaluate().isNotEmpty) {
        await tester.tap(back.first);
      } else if (find.byTooltip('Geri').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Geri'));
      } else {
        tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .pop();
      }
      await tester.pump(const Duration(milliseconds: 300));
    }

    for (final entry in results.entries) {
      final samples = entry.value;
      // ignore: avoid_print
      print('ÖLÇÜM ${entry.key}:');
      for (final sample in samples) {
        // ignore: avoid_print
        print('  - $sample');
      }
      final visibleMedian = median(
        samples.map((s) => s.visibleResponseMs).toList(),
      );
      // ignore: avoid_print
      print('  → görünen yanıt medyanı ${visibleMedian.toStringAsFixed(1)}ms');
      expect(
        visibleMedian,
        lessThan(100),
        reason: '${entry.key} görünen yanıtı 100ms altında olmalı',
      );
    }
  });
}
