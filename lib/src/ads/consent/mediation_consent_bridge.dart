import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Callback that forwards consent to a single mediation partner.
///
/// [hasGdprConsent] is `true` when the user is outside a GDPR region or has
/// granted Purpose 1 (storage/access) consent.
/// [ccpaOptedOut] is `true` when the user opted out of data sale under CCPA.
typedef ConsentHandler = Future<void> Function({
  required bool hasGdprConsent,
  required bool ccpaOptedOut,
});

/// Forwards the user's consent choices to mediation partners that expose an
/// explicit privacy API.
///
/// Networks that read the IAB TCF v2 string automatically (Meta, Mintegral,
/// Pangle, InMobi, Moloco) need no handler. Register handlers for networks
/// with explicit consent setters — typically Unity, AppLovin, ironSource,
/// Liftoff Monetize, and DT Exchange:
///
/// ```dart
/// import 'package:gma_mediation_unity/gma_mediation_unity.dart';
///
/// MediationConsentBridge.register('Unity', ({
///   required bool hasGdprConsent,
///   required bool ccpaOptedOut,
/// }) async {
///   final unity = GmaMediationUnity();
///   await unity.setGDPRConsent(hasGdprConsent);
///   await unity.setCCPAConsent(!ccpaOptedOut);
/// });
/// ```
///
/// [syncFromUmp] is called automatically during [AdMobMediation.initialize];
/// it reads the IAB TCF values UMP persisted and pushes them to every
/// registered handler.
abstract final class MediationConsentBridge {
  static final List<(String name, ConsentHandler handler)> _handlers = [];

  /// Register a consent handler for a mediation network.
  ///
  /// Call before [AdMobMediation.initialize] for each network that needs
  /// explicit consent forwarding.
  static void register(String networkName, ConsentHandler handler) {
    _handlers.add((networkName, handler));
  }

  /// Reads IAB TCF v2 values persisted by UMP and pushes them to all
  /// registered handlers. Called automatically during initialization.
  static Future<void> syncFromUmp() async {
    if (_handlers.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();

    // IABTCF_gdprApplies: 1 = user is in a GDPR region.
    final gdprApplies = prefs.getInt('IABTCF_gdprApplies') == 1;
    // IABTCF_PurposeConsents: binary string, char 0 = Purpose 1 (storage).
    final purposeConsents =
        prefs.getString('IABTCF_PurposeConsents') ?? '';
    final hasGdprConsent = !gdprApplies ||
        (purposeConsents.isNotEmpty && purposeConsents[0] == '1');

    // If you serve California users and collect an explicit "Do Not Sell"
    // choice (e.g. via the AdMob US states message), wire it through here.
    const ccpaOptedOut = false;

    await Future.wait([
      for (final (name, handler) in _handlers)
        _safely(
          name,
          () => handler(
            hasGdprConsent: hasGdprConsent,
            ccpaOptedOut: ccpaOptedOut,
          ),
        ),
    ]);
  }

  /// A partner SDK failure must never break the whole consent sync.
  static Future<void> _safely(
    String partner,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      debugPrint('[Ads][Consent] Failed to sync consent to $partner: $e');
    }
  }
}
