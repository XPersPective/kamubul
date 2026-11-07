import 'dart:async';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/foundation.dart';

/// UMP must finish and allow requests before ATT and SDK initialization.
abstract final class ConsentManager {
  static final privacyOptionsRequired = ValueNotifier<bool>(false);
  static final _gate = AdConsentGate(
    update: () {
      final result = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () => result.complete(),
        (error) => result.completeError(StateError('consent_update')),
      );
      return result.future;
    },
    showForm: () async {
      FormError? failure;
      await ConsentForm.loadAndShowConsentFormIfRequired(
        (error) => failure = error,
      );
      if (failure != null) throw StateError('consent_form');
    },
    canRequest: () => ConsentInformation.instance.canRequestAds(),
    tracking: () async {
      if (Platform.isIOS &&
          await AppTrackingTransparency.trackingAuthorizationStatus ==
              TrackingStatus.notDetermined) {
        await AppTrackingTransparency.requestTrackingAuthorization();
      }
    },
    initializeSdk: () async => await MobileAds.instance.initialize(),
  );

  static Future<bool> initialize() async {
    final ready = await _gate.initialize();
    try {
      privacyOptionsRequired.value =
          await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } on Object {
      // Preserve the last known requirement when the SDK is unavailable.
    }
    return ready;
  }

  static Future<bool> canRequestAds() =>
      ConsentInformation.instance.canRequestAds();

  static Future<bool> showPrivacyOptions() async {
    if (await ConsentInformation.instance
            .getPrivacyOptionsRequirementStatus() !=
        PrivacyOptionsRequirementStatus.required) {
      return false;
    }
    FormError? failure;
    await ConsentForm.showPrivacyOptionsForm((error) => failure = error);
    if (failure != null) throw StateError('consent_options');
    return true;
  }
}

/// Injectable boundary for proving order, denial, timeout and concurrent calls.
class AdConsentGate {
  AdConsentGate({
    required this.update,
    required this.showForm,
    required this.canRequest,
    required this.tracking,
    required this.initializeSdk,
    this.timeout = const Duration(seconds: 30),
  });

  final Future<void> Function() update, showForm, tracking, initializeSdk;
  final Future<bool> Function() canRequest;
  final Duration timeout;
  bool _ready = false;
  Future<bool>? _pending;

  Future<bool> initialize() {
    if (_ready) return Future.value(true);
    return _pending ??= _run().whenComplete(() => _pending = null);
  }

  Future<bool> _run() async {
    try {
      await update().timeout(timeout);
      await showForm().timeout(timeout);
      if (!await canRequest().timeout(timeout)) return false;
      await tracking().timeout(timeout);
      await initializeSdk().timeout(timeout);
      return _ready = true;
    } on Object {
      return false;
    }
  }
}
