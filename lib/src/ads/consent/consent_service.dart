import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Wraps Google's User Messaging Platform (UMP) SDK.
///
/// Handles GDPR / US-state privacy messages that you configure in the AdMob
/// dashboard under **Privacy & messaging**. Must run before the Mobile Ads
/// SDK is initialized so that the very first ad request is already
/// consent-aware.
class ConsentService {
  ConsentService._();

  static final ConsentService instance = ConsentService._();

  /// Requests up-to-date consent info and shows the consent form when
  /// required (first launch in EEA/UK, or when the message was updated).
  ///
  /// Returns `true` when ads can be requested (with either personalized or
  /// limited ads, depending on the user's choices).
  ///
  /// [debugGeography] lets you test the EEA flow from anywhere, and
  /// [testDeviceHashedIds] are the hashed device ids UMP logs on first run.
  /// Both are ignored in release builds.
  Future<bool> gatherConsent({
    DebugGeography? debugGeography,
    List<String> testDeviceHashedIds = const <String>[],
    bool? underAgeOfConsent,
  }) async {
    final params = ConsentRequestParameters(
      tagForUnderAgeOfConsent: underAgeOfConsent,
      consentDebugSettings: kDebugMode && debugGeography != null
          ? ConsentDebugSettings(
              debugGeography: debugGeography,
              testIdentifiers: testDeviceHashedIds,
            )
          : null,
    );

    final completer = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () {
        // Consent info updated: show the form only if the geography requires
        // it and the user hasn't already answered.
        ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
          if (error != null) {
            debugPrint(
              '[Ads][Consent] Form error ${error.errorCode}: ${error.message}',
            );
          }
          completer.complete();
        });
      },
      (FormError error) {
        // Network failure etc. Don't block the app: canRequestAds() below
        // falls back to the consent status cached from a previous session.
        debugPrint(
          '[Ads][Consent] Update error ${error.errorCode}: ${error.message}',
        );
        completer.complete();
      },
    );

    await completer.future;
    return ConsentInformation.instance.canRequestAds();
  }

  /// Whether a "Privacy options" entry point (re-open the consent form) must
  /// be offered in your settings screen. Required for EEA/UK users.
  Future<bool> isPrivacyOptionsRequired() async {
    final status = await ConsentInformation.instance
        .getPrivacyOptionsRequirementStatus();
    return status == PrivacyOptionsRequirementStatus.required;
  }

  /// Whether UMP currently permits the app to request ads.
  Future<bool> canRequestAds() => ConsentInformation.instance.canRequestAds();

  /// Re-opens the consent form so the user can change their choices.
  Future<void> showPrivacyOptionsForm() async {
    final completer = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((FormError? error) {
      if (error != null) {
        debugPrint('[Ads][Consent] Privacy options error: ${error.message}');
        completer.completeError(error);
        return;
      }
      completer.complete();
    });
    return completer.future;
  }

  /// Debug-only: wipe consent state so the form shows again on next launch.
  Future<void> resetForTesting() async {
    if (!kDebugMode) {
      throw StateError('resetForTesting is only available in debug builds.');
    }
    ConsentInformation.instance.reset();
  }
}
