import 'package:flutter/material.dart';

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
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

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
/// kayma; Material motion sistemasının 250ms ileri profili.
PageRouteBuilder<T> sharedAxisRoute<T>(Widget page) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 250),
  reverseTransitionDuration: const Duration(milliseconds: 200),
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
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
  final endOfDay = DateTime(
    deadline.year,
    deadline.month,
    deadline.day,
    23,
    59,
  );
  final days = endOfDay.difference(now).inDays;
  if (days < 0) return 'Süre doldu';
  if (days == 0) return 'Bugün son gün';
  if (days == 1) return 'Son 1 gün';
  return 'Son $days gün';
}
