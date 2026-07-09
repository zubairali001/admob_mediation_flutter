import 'package:flutter/foundation.dart';
import 'package:gma_mediation_applovin/gma_mediation_applovin.dart';
import 'package:gma_mediation_dtexchange/gma_mediation_dtexchange.dart';
import 'package:gma_mediation_ironsource/gma_mediation_ironsource.dart';
import 'package:gma_mediation_liftoffmonetize/gma_mediation_liftoffmonetize.dart';
import 'package:gma_mediation_unity/gma_mediation_unity.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Forwards the user's consent choices to mediation partners that expose a
/// manual privacy API.
///
/// Modern partner SDKs (and all TCF-certified ones: Meta, Mintegral, Pangle,
/// InMobi read the IAB TCF string written by UMP automatically), but Unity,
/// AppLovin, ironSource, Liftoff and DT Exchange still offer explicit
/// setters — forwarding keeps fill rates healthy on older SDK behaviors and
/// covers CCPA/LGPD signals the TCF string doesn't carry.
///
/// Call [syncFromUmp] right after the UMP consent flow completes and before
/// `MobileAds.instance.initialize()`.
class MediationConsentBridge {
  MediationConsentBridge._();

  /// Reads the IAB TCF v2 values UMP persisted in platform preferences
  /// (SharedPreferences / NSUserDefaults) and pushes them to the partners.
  static Future<void> syncFromUmp() async {
    final prefs = await SharedPreferences.getInstance();

    // IABTCF_gdprApplies: 1 = user is in a GDPR region.
    final gdprApplies = prefs.getInt('IABTCF_gdprApplies') == 1;
    // IABTCF_PurposeConsents: binary string, char 0 = Purpose 1 (storage).
    final purposeConsents = prefs.getString('IABTCF_PurposeConsents') ?? '';
    final hasGdprConsent =
        !gdprApplies || (purposeConsents.isNotEmpty && purposeConsents[0] == '1');

    // If you serve California users and collect an explicit "Do Not Sell"
    // choice (e.g. via the AdMob US states message), wire it through here.
    const ccpaOptedOut = false;

    await applyConsent(hasGdprConsent: hasGdprConsent, ccpaOptedOut: ccpaOptedOut);
  }

  /// Pushes explicit consent flags to every partner with a privacy API.
  static Future<void> applyConsent({
    required bool hasGdprConsent,
    required bool ccpaOptedOut,
  }) async {
    // "1YNN" / "1YYN": IAB US privacy string (version, notice given,
    // opted out of sale, LSPA).
    final usPrivacyString = ccpaOptedOut ? '1YYN' : '1YNN';

    await Future.wait<void>([
      _safely('Unity', () async {
        final unity = GmaMediationUnity();
        await unity.setGDPRConsent(hasGdprConsent);
        await unity.setCCPAConsent(!ccpaOptedOut);
      }),
      _safely('AppLovin', () async {
        final appLovin = GmaMediationApplovin();
        await appLovin.setHasUserConsent(hasGdprConsent);
        await appLovin.setDoNotSell(ccpaOptedOut);
      }),
      _safely('ironSource', () async {
        final ironSource = GmaMediationIronsource();
        await ironSource.setConsent(hasGdprConsent);
        await ironSource.setDoNotSell(ccpaOptedOut);
      }),
      _safely('Liftoff Monetize', () async {
        final liftoff = GmaMediationLiftoffmonetize();
        await liftoff.setGDPRStatus(hasGdprConsent, null);
        await liftoff.setCCPAStatus(!ccpaOptedOut);
      }),
      _safely('DT Exchange', () async {
        final dtExchange = GmaMediationDTExchange();
        await dtExchange.setUSPrivacyString(usPrivacyString);
        // DT Exchange treats LGPD (Brazil) separately; we mirror GDPR consent.
        await dtExchange.setLgpdConsent(hasGdprConsent);
      }),
    ]);
  }

  /// A partner SDK failure must never break the whole consent sync.
  static Future<void> _safely(String partner, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('[Ads][Consent] Failed to sync consent to $partner: $e');
    }
  }
}
