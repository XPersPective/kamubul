import 'package:flutter/material.dart';

import 'premium.dart';

/// Kurum adının baş harflerinden iki harfli monogram ("T.C. SAĞLIK
/// BAKANLIĞI - ..." → "SB"); harf yoksa kamu simgesi için "K".
String institutionInitials(String title) {
  final head = title.split(RegExp(r'\s[-–—]\s')).first;
  final letters = head
      .split(RegExp(r'[\s.]+'))
      .where(
        (word) =>
            word.isNotEmpty && RegExp(r'^\p{L}', unicode: true).hasMatch(word),
      )
      .where(
        (word) =>
            !const {'T', 'C', 'VE', 'İLE', 'TC'}.contains(word.toUpperCase()),
      )
      .map((word) => word.substring(0, 1).toUpperCase())
      .toList();
  if (letters.isEmpty) return 'K';
  return letters.take(2).join();
}

/// Kuruma göre kararlı bir mavi-yeşil-mor ton; renk yalnız ayrım içindir.
Color institutionTint(String title, Brightness brightness) {
  const hues = [212.0, 188.0, 160.0, 262.0, 330.0, 24.0, 44.0];
  final head = title.split(RegExp(r'\s[-–—]\s')).first;
  final hue =
      hues[head.runes.fold<int>(0, (a, b) => (a * 31 + b) & 0xffff) %
          hues.length];
  return HSLColor.fromAHSL(
    1,
    hue,
    brightness == Brightness.dark ? 0.55 : 0.6,
    brightness == Brightness.dark ? 0.62 : 0.34,
  ).toColor();
}

class InstitutionAvatar extends StatelessWidget {
  const InstitutionAvatar({super.key, required this.title, this.size = 46});

  final String title;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint = institutionTint(title, Theme.of(context).brightness);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Text(
          institutionInitials(title),
          style: TextStyle(
            color: tint,
            fontSize: size * 0.36,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

/// Son başvuru rozeti: renk aciliyeti, metin geri sayımı verir. Renk tek
/// başına anlam taşımaz; metin her zaman vardır.
class DeadlinePill extends StatelessWidget {
  const DeadlinePill({
    super.key,
    required this.text,
    required this.daysLeft,
    this.expired = false,
  });

  final String text;
  final int? daysLeft;
  final bool expired;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    final Color color;
    if (expired) {
      color = PremiumStatus.dropped(brightness);
    } else if (daysLeft == null) {
      color = scheme.onSurfaceVariant;
    } else if (daysLeft! <= 3) {
      color = PremiumStatus.dropped(brightness);
    } else if (daysLeft! <= 7) {
      color = PremiumStatus.held(brightness);
    } else {
      color = PremiumStatus.delivered(brightness);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(PremiumShape.chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, size: 15, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Başlık paneli: marka gradyanı üzerinde beyaz metin. İki temada da
/// zemin koyu mavi olduğundan kontrast sabittir.
class HeroPanel extends StatelessWidget {
  const HeroPanel({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.badge,
    this.error,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget? badge;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PremiumShape.barRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF123B5A), Color(0xFF0E2538)]
              : const [Color(0xFF1B6AA5), Color(0xFF123F66)],
        ),
        boxShadow: dark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x1A17659C),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: const TextStyle(
              color: Color(0xFFBFE0FA),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFFD3E6F6),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (badge != null) ...[const SizedBox(height: 10), badge!],
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: const TextStyle(color: Color(0xFFFFCDD2), fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

/// Hero içindeki yarı saydam bilgi rozeti (ör. deneme süresi).
class HeroBadge extends StatelessWidget {
  const HeroBadge({
    super.key,
    required this.icon,
    required this.text,
    this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: 0.16),
    borderRadius: BorderRadius.circular(PremiumShape.chipRadius),
    child: InkWell(
      borderRadius: BorderRadius.circular(PremiumShape.chipRadius),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: Colors.white),
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
        ),
      ),
    ),
  );
}

/// Ayarlar için başlıklı kart grubu.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            child: Text(
              title,
              style: TextStyle(
                color: scheme.primary,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.3,
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

/// İlan ayrıntısı alt çubuğu: üç ayrı renk, üç ayrı amaç.
/// Asistan (vurgu moru) • Başvuru (marka mavisi) • İlan (sade çerçeve).
class ListingActionBar extends StatelessWidget {
  const ListingActionBar({
    super.key,
    required this.onOpenListing,
    this.onApply,
    this.onAskAssistant,
    this.openLabel = 'İlanı aç',
    this.applyLabel = 'Başvuru sayfasını aç',
  });

  final VoidCallback onOpenListing;

  /// Başvuru bağlantısı yoksa null; o zaman ilan düğmesi ana düğme olur.
  final VoidCallback? onApply;
  final VoidCallback? onAskAssistant;
  final String openLabel;
  final String applyLabel;

  static const brand = Color(0xFF1B6AA5);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(PremiumShape.buttonRadius),
    );
    Widget label(String text) =>
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
    final primaryIsApply = onApply != null;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onAskAssistant != null) ...[
            FilledButton.icon(
              onPressed: onAskAssistant,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: label('Asistana sor: Bana uygun mu?'),
              style: FilledButton.styleFrom(
                backgroundColor: dark
                    ? const Color(0xFFB9ADFF)
                    : const Color(0xFF5B3FD9),
                foregroundColor: dark ? const Color(0xFF1E1240) : Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: shape,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: primaryIsApply
                    ? OutlinedButton.icon(
                        onPressed: onOpenListing,
                        icon: const Icon(Icons.article_outlined),
                        label: label(openLabel),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.onSurface,
                          side: BorderSide(color: scheme.outline),
                          minimumSize: const Size.fromHeight(52),
                          shape: shape,
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: onOpenListing,
                        icon: const Icon(Icons.open_in_new),
                        label: label(openLabel),
                        style: FilledButton.styleFrom(
                          backgroundColor: brand,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                          shape: shape,
                        ),
                      ),
              ),
              if (primaryIsApply) ...[
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: onApply,
                    icon: const Icon(Icons.open_in_new),
                    label: label(applyLabel),
                    style: FilledButton.styleFrom(
                      backgroundColor: brand,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: shape,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
