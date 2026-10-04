import 'package:flutter/material.dart';
import 'package:napp_core/napp_core.dart';
import 'package:napp_pro/napp_pro.dart';

import 'premium.dart';

/// KamuBul Pro sayfası: ortak PaywallPage ile aynı sözleşme (mağazadan gelen
/// fiyat, tek ödeme, geri yükleme, dürüst dil), premium sunumla.
class ProPage extends StatefulWidget {
  const ProPage({
    super.key,
    required this.identity,
    required this.controller,
    required this.repository,
    required this.trialDays,
  });

  final AppIdentity identity;
  final ProController controller;
  final PurchaseRepository repository;

  /// Kalan reklamsız deneme günü; 0 = deneme bitti.
  final int trialDays;

  @override
  State<ProPage> createState() => _ProPageState();
}

class _ProPageState extends State<ProPage> {
  late Future<StoreProduct?> _product = widget.repository.queryProduct();

  Future<void> _buy(StoreProduct product) async {
    final l10n = NappLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.repository.buy(product);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.t('paywall.error'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.identity.appName} Pro')),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _hero(scheme),
            const SizedBox(height: 18),
            _benefit(
              Icons.block_rounded,
              'Reklamsız ilan takibi',
              'Abonelik süresince banner ve tam ekran reklamlar kapanır.',
            ),
            _benefit(
              Icons.auto_awesome_outlined,
              'Asistan’a daha çok soru',
              'KamuBul Asistan yapay zekâ kullanır ve her sorunun bir maliyeti '
                  'vardır. Pro ile günde 100 soru (ücretsiz: 30).',
            ),
            _benefit(
              Icons.payments_outlined,
              'Aylık, cüzi ücret',
              'Her ay otomatik yenilenir; Google Play > Abonelikler’den '
                  'istediğiniz an iptal edersiniz, dönem sonuna kadar Pro sürer. '
                  'Yeni telefonda geri yüklenir.',
            ),
            _benefit(
              Icons.lock_outline_rounded,
              'Her şey hesapsız ve cihazınızda',
              'Pro ilan sayısını veya özellikleri kısıtlamaz; ücretsiz sürümle '
                  'aynı resmî kaynaklar ve filtreler gelir.',
            ),
            const SizedBox(height: 18),
            if (widget.controller.isPro) _thanks(scheme) else _buyArea(scheme),
          ],
        ),
      ),
    );
  }

  Widget _hero(ColorScheme scheme) {
    final text = widget.controller.isPro
        ? 'Pro etkin. Teşekkürler!'
        : widget.trialDays > 0
        ? (widget.trialDays == 1
              ? 'Reklamsız deneme: son gün'
              : 'Reklamsız deneme: ${widget.trialDays} gün kaldı')
        : 'Reklamsız deneme bitti';
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PremiumShape.barRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [Color(0xFF1B6AA5), Color(0xFF123F66)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  widget.identity.iconAsset ?? 'assets/brand/kamubul_icon.png',
                  width: 52,
                  height: 52,
                  errorBuilder: (_, _, _) => const SizedBox(width: 52),
                ),
              ),
              const SizedBox(width: 14),
              const Text(
                'KamuBul',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(PremiumShape.chipRadius),
                ),
                child: const Text(
                  'PRO',
                  style: TextStyle(
                    color: Color(0xFF123F66),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Kamu ilanlarını reklamsız takip edin.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          HeroLine(text: text),
          if (!widget.controller.isPro && widget.trialDays > 0)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Deneme bitince küçük banner ve seyrek tam ekran reklamlar '
                'başlar. Pro abonelik süresince bunları kaldırır.',
                style: TextStyle(
                  color: Color(0xFFD3E6F6),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _benefit(IconData icon, String title, String body) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _brandAccent(context).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: _brandAccent(context)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _thanks(ColorScheme scheme) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Icon(Icons.verified_rounded, color: scheme.primary, size: 32),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Pro etkin. Reklamlar kapalı; teşekkür ederiz.'),
          ),
        ],
      ),
    ),
  );

  Widget _buyArea(ColorScheme scheme) {
    final l10n = NappLocalizations.of(context);
    return FutureBuilder<StoreProduct?>(
      future: _product,
      builder: (context, snapshot) {
        final product = snapshot.data;
        final loading = snapshot.connectionState != ConnectionState.done;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.controller.tempProUntil != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(l10n.t('paywall.pending')),
              ),
            if (widget.controller.lastError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l10n.t('paywall.error'),
                  style: TextStyle(color: scheme.error),
                ),
              ),
            if (product != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${product.price} / ay',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            if (product != null)
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'Otomatik yenilenir · İstediğiniz an iptal',
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1B6AA5),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF1B6AA5)
                    .withValues(alpha: 0.45),
                disabledForegroundColor: Colors.white70,
                minimumSize: const Size.fromHeight(56),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onPressed: product == null ? null : () => _buy(product),
              child: Text(
                product != null
                    ? 'Aylık aboneliği başlat'
                    : l10n.t(
                        loading
                            ? 'paywall.priceLoading'
                            : 'paywall.unavailable',
                      ),
              ),
            ),
            if (!loading && product == null)
              TextButton(
                onPressed: () => setState(() {
                  _product = widget.repository.queryProduct();
                }),
                child: Text(l10n.commonRetry),
              ),
            TextButton(
              onPressed: widget.repository.restore,
              child: Text(l10n.t('paywall.restore')),
            ),
          ],
        );
      },
    );
  }
}

/// Hero içi küçük durum satırı (yarı saydam hap).
class HeroLine extends StatelessWidget {
  const HeroLine({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(PremiumShape.chipRadius),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.verified_outlined, size: 17, color: Colors.white),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Pro sayfası marka vurgusu: açık temada koyu, koyu temada açık mavi;
/// iki temada da aynı marka tonundan türetilir.
Color _brandAccent(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF7DB8EA)
    : const Color(0xFF1B6AA5);
