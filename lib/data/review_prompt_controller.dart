import 'dart:async';

import 'package:napp_core/napp_core.dart';

/// Builds the direct review URI for the platform storefront.
///
/// iOS uses `?action=write-review` so App Store opens directly to the review
/// composer. Android opens the Google Play app details page.
Uri storeReviewUri(AppIdentity identity, {required bool isIos}) {
  if (isIos) {
    final id = identity.appStoreId;
    if (id == null || id.isEmpty) {
      throw ArgumentError(
        'App Store yorum bağlantısı için AppIdentity.appStoreId gerekli',
      );
    }
    return Uri.parse('https://apps.apple.com/app/id$id?action=write-review');
  }
  return Uri.parse(
    'https://play.google.com/store/apps/details?id=${identity.packageName}',
  );
}

/// Manages graceful, store-policy-compliant review invitations after meaningful
/// positive moments (such as KamuBul Asistan answers, saved listings/searches).
///
/// Never gates features, never filters by sentiment, permanently stops once the
/// user indicates they reviewed or returns after spending enough time in the
/// storefront, and cools down cleanly on deferral.
class ReviewPromptController {
  ReviewPromptController({
    required this.store,
    this.actionsForFirstPrompt = 3,
    this.additionalActionsForRetry = 3,
    this.deferCooldown = const Duration(days: 5),
    this.quickBounceCooldown = const Duration(days: 7),
    this.minStoreVisitForCompletion = const Duration(seconds: 6),
    this.maxPrompts = 4,
  });

  static const _completedKey = 'kamubul.review.completed';
  static const _firstSeenKey = 'kamubul.review.firstSeen';
  static const _actionsKey = 'kamubul.review.actions';
  static const _lastPromptActionsKey = 'kamubul.review.lastPromptActions';
  static const _lastPromptAtKey = 'kamubul.review.lastPromptAt';
  static const _cooldownUntilKey = 'kamubul.review.cooldownUntil';
  static const _promptCountKey = 'kamubul.review.promptCount';
  static const _storeOpenedAtKey = 'kamubul.review.storeOpenedAt';

  final SettingsStore store;
  final int actionsForFirstPrompt;
  final int additionalActionsForRetry;
  final Duration deferCooldown;
  final Duration quickBounceCooldown;
  final Duration minStoreVisitForCompletion;
  final int maxPrompts;

  bool get isCompleted => store.getBool(_completedKey) ?? false;
  int get actions => store.getInt(_actionsKey) ?? 0;
  int get promptCount => store.getInt(_promptCountKey) ?? 0;

  void markFirstSeen(DateTime now) {
    if (store.getInt(_firstSeenKey) == null) {
      store.setInt(_firstSeenKey, now.millisecondsSinceEpoch);
    }
  }

  void recordPositiveAction({int weight = 1}) {
    if (weight <= 0 || isCompleted) return;
    store.setInt(_actionsKey, actions + weight);
  }

  /// Returns whether a graceful in-app review invitation should be shown now.
  bool shouldShowPrompt(DateTime now) {
    if (isCompleted) return false;
    if (promptCount >= maxPrompts) return false;
    if (store.getInt(_storeOpenedAtKey) != null) return false;

    final cooldownUntilMs = store.getInt(_cooldownUntilKey);
    if (cooldownUntilMs != null) {
      final until = DateTime.fromMillisecondsSinceEpoch(cooldownUntilMs);
      if (now.isBefore(until)) return false;
    }

    if (promptCount == 0) {
      return actions >= actionsForFirstPrompt;
    }
    final lastActions = store.getInt(_lastPromptActionsKey) ?? 0;
    return actions - lastActions >= additionalActionsForRetry;
  }

  /// User dismissed or chose "Daha sonra".
  void markDeferred(DateTime now) {
    if (isCompleted) return;
    store.setInt(_promptCountKey, promptCount + 1);
    store.setInt(_lastPromptAtKey, now.millisecondsSinceEpoch);
    store.setInt(_lastPromptActionsKey, actions);
    store.setInt(
      _cooldownUntilKey,
      now.add(deferCooldown).millisecondsSinceEpoch,
    );
    unawaited(store.flush().catchError((Object _) {}));
  }

  /// User tapped the storefront review button (either from the prompt sheet or
  /// from Settings). We record the departure time and verify on resume.
  void markStoreOpened(DateTime now, {required bool fromPrompt}) {
    if (fromPrompt) {
      store.setInt(_promptCountKey, promptCount + 1);
      store.setInt(_lastPromptAtKey, now.millisecondsSinceEpoch);
      store.setInt(_lastPromptActionsKey, actions);
    }
    store.setInt(_storeOpenedAtKey, now.millisecondsSinceEpoch);
    unawaited(store.flush().catchError((Object _) {}));
  }

  /// Called when the app returns to the foreground. If the user spent at least
  /// [minStoreVisitForCompletion] in the store page, marks review completed
  /// permanently and returns `true` so the UI can show a thank-you notice.
  bool onAppResumed(DateTime now) {
    final openedMs = store.getInt(_storeOpenedAtKey);
    if (openedMs == null) return false;
    store.remove(_storeOpenedAtKey);

    final elapsed = now.difference(
      DateTime.fromMillisecondsSinceEpoch(openedMs),
    );
    if (elapsed >= minStoreVisitForCompletion) {
      markCompleted();
      return true;
    }

    // User bounced back immediately: respect their time and cool down.
    store.setInt(
      _cooldownUntilKey,
      now.add(quickBounceCooldown).millisecondsSinceEpoch,
    );
    unawaited(store.flush().catchError((Object _) {}));
    return false;
  }

  /// User confirmed they already reviewed or returned from a genuine store visit.
  void markCompleted() {
    store.setBool(_completedKey, true);
    store.remove(_storeOpenedAtKey);
    unawaited(store.flush().catchError((Object _) {}));
  }
}
