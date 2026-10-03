import 'package:flutter/material.dart';

/// KamuBul görsel katmanı; ortak kitin davranışlarını ve marka rengini korur.
ThemeData premiumTheme(ThemeData base) {
  final dark = base.brightness == Brightness.dark;
  final colors = base.colorScheme.copyWith(
    surface: Color(dark ? 0xFF0B1520 : 0xFFF6F8FB),
    surfaceContainerLow: Color(dark ? 0xFF132330 : 0xFFFFFFFF),
    surfaceContainerHighest: Color(dark ? 0xFF203242 : 0xFFE8EEF5),
    onSurface: Color(dark ? 0xFFEAF0F6 : 0xFF172638),
    onSurfaceVariant: Color(dark ? 0xFFB5C4D3 : 0xFF506176),
    primaryContainer: Color(dark ? 0xFF173C53 : 0xFF18394B),
    onPrimaryContainer: const Color(0xFFEAF5FF),
  );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(PremiumShape.cardRadius),
    side: BorderSide(color: colors.outlineVariant),
  );
  return base.copyWith(
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    textTheme: base.textTheme
        .copyWith(
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            height: 1.2,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.5),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
        )
        .apply(bodyColor: colors.onSurface, displayColor: colors.onSurface),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: colors.onSurface,
      elevation: 0,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: colors.onSurface,
        fontSize: 21,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
    ),
    cardTheme: base.cardTheme.copyWith(
      color: colors.surfaceContainerLow,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: shape,
      margin: const EdgeInsets.symmetric(vertical: 6),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: colors.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colors.outline),
      ),
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      backgroundColor: colors.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colors.primaryContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? colors.onPrimaryContainer
              : colors.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: colors.onSurfaceVariant,
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
    ),
  );
}

/// PB-008 premium şekil tokenları: kart, çip, düğme ve sayfa altı yarıçapları.
abstract final class PremiumShape {
  static const cardRadius = 22.0;
  static const chipRadius = 999.0;
  static const buttonRadius = 16.0;
  static const barRadius = 24.0;
}

/// PB-008 premium hareket tokenları: yay (spring) hissi veren eğri ve
/// süreler; geçişlerde tek kaynaktan yönetilir.
abstract final class PremiumMotion {
  /// 250ms ileri profili: hafif overshoot'lu yay hissi.
  static const springCurve = Curves.easeOutBack;

  /// Geri dönüşte overshoot yok; sakin iniş.
  static const settleCurve = Curves.easeOutCubic;

  static const springDuration = Duration(milliseconds: 250);
  static const settleDuration = Duration(milliseconds: 200);
  static const shimmerDuration = Duration(milliseconds: 1200);
}

/// PB-008 teslimat durumu renkleri: ekranlar sabit renk yazmaz, durum
/// renkleri tek kaynaktan gelir. Her tema kendi varyantını kullanır; her
/// varyant %12 kendi zeminine karşı WCAG AA (4.5:1) kontrastını geçer —
/// tek sabit renk koyu temada eşiğin altına düşüyordu.
abstract final class PremiumStatus {
  static Color delivered(Brightness brightness) => switch (brightness) {
    Brightness.light => const Color(0xFF1B5E20),
    Brightness.dark => const Color(0xFF81C784),
  };

  static Color held(Brightness brightness) => switch (brightness) {
    Brightness.light => const Color(0xFFA62E00),
    Brightness.dark => const Color(0xFFFFB74D),
  };

  static Color dropped(Brightness brightness) => switch (brightness) {
    Brightness.light => const Color(0xFFB71C1C),
    Brightness.dark => const Color(0xFFEF9A9A),
  };
}

/// PB-008 premium UI yardımcıları: iskelet yükleyiciler, paylaşılan eksen
/// geçişi ve geri sayım rozeti.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, required this.width, this.height = 14});

  final double width;
  final double height;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: PremiumMotion.shimmerDuration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0.5;
    } else {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.35,
        end: 0.85,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}

/// Liste yüklenirken kart biçiminde iskelet; düz spinner yerine düzeni korur.
Widget listingSkeletons() => Column(
  children: [
    for (var i = 0; i < 4; i++)
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 120),
                const SizedBox(height: 10),
                SkeletonBox(width: double.infinity, height: 18),
                const SizedBox(height: 8),
                SkeletonBox(width: 220),
                const SizedBox(height: 14),
                SkeletonBox(width: 160, height: 36),
              ],
            ),
          ),
        ),
      ),
  ],
);

/// Liste → ayrıntı için paylaşılan eksen (ileri) geçişi: kısa fade + yukarı
/// kayma; Material motion sistemasının 250ms ileri profili, yay tokenıyla.
PageRouteBuilder<T> sharedAxisRoute<T>(Widget page) => PageRouteBuilder<T>(
  transitionDuration: PremiumMotion.springDuration,
  reverseTransitionDuration: PremiumMotion.settleDuration,
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: PremiumMotion.springCurve,
      reverseCurve: PremiumMotion.settleCurve,
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  },
);

/// Son başvuruya kalan günü kısa etiketle döndürür; null = tarih yok.
String? countdownLabel(DateTime? deadline, DateTime now) {
  if (deadline == null) return null;
  if (!deadline.isAfter(now)) return 'Süre doldu';
  final end = deadline.toLocal(), today = now.toLocal();
  final days = DateTime.utc(
    end.year,
    end.month,
    end.day,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  if (days == 0) return 'Bugün son gün';
  if (days == 1) return 'Son 1 gün';
  return 'Son $days gün';
}
