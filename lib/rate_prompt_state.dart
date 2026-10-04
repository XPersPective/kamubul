import 'package:napp_core/napp_core.dart';

/// Puan istemi politikasının yerel kaydı (ORTAK 3.5: seyrek, kota dostu,
/// olumlu andan sonra — asla bir işin ortasında).
void restoreRatePrompt(RatePromptPolicy policy, SettingsStore store) {
  final firstMs = store.getInt('kamubul.rate.firstSeen');
  final prompts = store.getStringList('kamubul.rate.prompts') ?? const [];
  policy.restore(
    firstSeen: firstMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(firstMs),
    promptedAt: [
      for (final raw in prompts)
        if (int.tryParse(raw) case final ms?)
          DateTime.fromMillisecondsSinceEpoch(ms),
    ],
    positiveMoments: store.getInt('kamubul.rate.positive') ?? 0,
  );
}

void saveRatePrompt(RatePromptPolicy policy, SettingsStore store) {
  final snapshot = policy.snapshot();
  final firstSeen = snapshot.firstSeen;
  if (firstSeen != null) {
    store.setInt('kamubul.rate.firstSeen', firstSeen.millisecondsSinceEpoch);
  }
  store.setStringList('kamubul.rate.prompts', [
    for (final time in snapshot.promptedAt)
      time.millisecondsSinceEpoch.toString(),
  ]);
  store.setInt('kamubul.rate.positive', snapshot.positiveMoments);
}
