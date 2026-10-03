import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/ui/premium.dart';
import 'package:napp_core/napp_core.dart';

/// PB-008 WCAG AA otomatik doğrulaması.
///
/// Metin çiftleri 4.5:1, arayüz öğeleri 3:1 alt sınırını geçmek zorunda;
/// durum rozetleri %12 kendi rengiyle kaplanmış zemin üzerinde ölçülür.
/// Marka rengi main.dart ile aynıdır; tema napp_core tokenlarından gelir.
void main() {
  const brand = Color(0xFF17659C);

  double contrast(Color fg, Color bg) {
    final l1 = fg.computeLuminance();
    final l2 = bg.computeLuminance();
    final hi = l1 > l2 ? l1 : l2;
    final lo = l1 > l2 ? l2 : l1;
    return (hi + 0.05) / (lo + 0.05);
  }

  // Rozet zemini: durum renginin %12 kaplaması sayfa zeminine binmiş hali.
  Color badgeBase(Color status, Color surface) =>
      Color.alphaBlend(status.withValues(alpha: 0.12), surface);

  final themes = [
    ('açık', premiumTheme(AppTheme.light(brandColor: brand))),
    ('koyu', premiumTheme(AppTheme.dark(brandColor: brand))),
  ];

  for (final (name, theme) in themes) {
    group('$name tema', () {
      final scheme = theme.colorScheme;

      test('metin çiftleri WCAG AA (4.5:1) geçer', () {
        final pairs = <(String, Color, Color)>[
          ('gövde metni', scheme.onSurface, scheme.surface),
          ('kart metni', scheme.onSurface, scheme.surfaceContainerLow),
          ('çip metni', scheme.onSurface, scheme.surfaceContainerHighest),
          ('ikincil metin', scheme.onSurfaceVariant, scheme.surface),
          ('birincil düğme', scheme.onPrimary, scheme.primary),
          ('ikincil düğme', scheme.onSecondary, scheme.secondary),
          ('hata metni', scheme.onError, scheme.error),
          ('birincil kap', scheme.onPrimaryContainer, scheme.primaryContainer),
          (
            'ikincil kap',
            scheme.onSecondaryContainer,
            scheme.secondaryContainer,
          ),
          ('hata kap', scheme.onErrorContainer, scheme.errorContainer),
          ('üçüncül kap', scheme.onTertiaryContainer, scheme.tertiaryContainer),
        ];
        for (final (label, fg, bg) in pairs) {
          expect(
            contrast(fg, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$name temada "$label" kontrastı AA eşiğinin altında',
          );
        }
      });

      test('arayüz öğeleri 3:1 geçer', () {
        for (final (label, fg, bg) in <(String, Color, Color)>[
          ('bağlantı/ikon', scheme.primary, scheme.surface),
          ('çerçeve', scheme.outline, scheme.surface),
          ('hata göstergesi', scheme.error, scheme.surface),
        ]) {
          expect(
            contrast(fg, bg),
            greaterThanOrEqualTo(3),
            reason: '$name temada "$label" kontrastı 3:1 altında',
          );
        }
      });

      test('teslimat durumu rozetleri AA (4.5:1) geçer', () {
        final brightness = theme.brightness;
        final statuses = <(String, Color)>[
          ('Gönderildi', PremiumStatus.delivered(brightness)),
          ('Beklemede', PremiumStatus.held(brightness)),
          ('Gönderilmedi', PremiumStatus.dropped(brightness)),
        ];
        for (final surface in [scheme.surface, scheme.surfaceContainerLow]) {
          for (final (label, status) in statuses) {
            expect(
              contrast(status, badgeBase(status, surface)),
              greaterThanOrEqualTo(4.5),
              reason: '$name temada "$label" rozeti %12 zemininde AA altında',
            );
          }
        }
      });
    });
  }
}
