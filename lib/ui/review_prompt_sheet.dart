import 'package:flutter/material.dart';

import 'premium.dart';

enum ReviewPromptChoice { rateNow, alreadyReviewed, later }

/// Graceful, store-policy-compliant Turkish review invitation sheet.
///
/// Always dismissible, never gates any feature, and never pre-filters users
/// based on sentiment.
Future<ReviewPromptChoice?> showReviewPromptSheet(BuildContext context) {
  return showModalBottomSheet<ReviewPromptChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => const _ReviewPromptSheetBody(),
  );
}

class _ReviewPromptSheetBody extends StatelessWidget {
  const _ReviewPromptSheetBody();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final starColor = dark ? const Color(0xFFFFCA28) : const Color(0xFFE09F1F);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: starColor.withValues(alpha: dark ? 0.16 : 0.12),
                  borderRadius: BorderRadius.circular(PremiumShape.chipRadius),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 5; i++)
                      Padding(
                        padding: EdgeInsets.only(right: i == 4 ? 0 : 4),
                        child: Icon(
                          Icons.star_rounded,
                          size: 24,
                          color: starColor,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'KamuBul işinize yarıyor mu?',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Mağazada bırakacağınız kısa bir puan ve yorum, KamuBul’un daha '
              'fazla kamu adayı tarafından keşfedilmesine ve ücretsiz kalmasına '
              'büyük destek olur.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(ReviewPromptChoice.rateNow),
              icon: const Icon(Icons.rate_review_outlined),
              label: const Text('Mağazada puan ver ve yorum yaz'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1B6AA5),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    PremiumShape.buttonRadius,
                  ),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(ReviewPromptChoice.alreadyReviewed),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  child: const Text('Zaten yorum yaptım'),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(ReviewPromptChoice.later),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  child: const Text('Daha sonra'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
