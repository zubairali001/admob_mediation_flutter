import 'package:flutter/foundation.dart';

/// Privacy choices supplied by the app's consent management flow.
@immutable
final class MediationConsent {
  const MediationConsent({
    required this.hasGdprConsent,
    required this.ccpaOptedOut,
  });

  /// Whether GDPR consent required by an explicit partner API was granted.
  final bool hasGdprConsent;

  /// Whether the user opted out under applicable US-state privacy laws.
  final bool ccpaOptedOut;
}

/// Resolves the latest privacy choices after UMP completes.
typedef MediationConsentProvider = Future<MediationConsent> Function();

/// Callback that forwards consent to a single mediation partner.
///
/// [hasGdprConsent] is the value returned by [MediationConsentProvider].
/// [ccpaOptedOut] is `true` when the user opted out of data sale under CCPA.
typedef ConsentHandler =
    Future<void> Function({
      required bool hasGdprConsent,
      required bool ccpaOptedOut,
    });

/// Forwards the user's consent choices to mediation partners that expose an
/// explicit privacy API.
///
/// Some adapters read standard consent strings written by the app's CMP, while
/// others expose explicit privacy setters. Follow the current integration guide
/// for every adapter you install. Register a handler only when its guide
/// requires an explicit call:
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
/// [sync] is called automatically during `AdMobMediation.initialize` and after
/// the privacy options form closes. Consent is supplied explicitly because
/// UMP doesn't expose one universal boolean that is valid for every partner.
abstract final class MediationConsentBridge {
  static final Map<String, ConsentHandler> _handlers =
      <String, ConsentHandler>{};

  /// Whether at least one explicit partner consent handler is registered.
  static bool get hasHandlers => _handlers.isNotEmpty;

  /// Register a consent handler for a mediation network.
  ///
  /// Call before [AdMobMediation.initialize] for each network that needs
  /// explicit consent forwarding.
  static void register(String networkName, ConsentHandler handler) {
    final name = networkName.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(
        networkName,
        'networkName',
        'Must not be empty.',
      );
    }
    _handlers[name] = handler;
  }

  /// Removes a previously registered handler.
  static void unregister(String networkName) =>
      _handlers.remove(networkName.trim());

  /// Pushes [consent] to every registered mediation partner.
  ///
  /// Failures are aggregated and thrown so ad initialization fails closed.
  static Future<void> sync(MediationConsent consent) async {
    if (_handlers.isEmpty) return;

    final failures = <String, Object>{};
    await Future.wait(
      _handlers.entries.map((entry) async {
        try {
          await entry.value(
            hasGdprConsent: consent.hasGdprConsent,
            ccpaOptedOut: consent.ccpaOptedOut,
          );
        } catch (error) {
          failures[entry.key] = error;
        }
      }),
    );

    if (failures.isNotEmpty) {
      throw MediationConsentException(failures);
    }
  }

  @visibleForTesting
  static void clearHandlers() => _handlers.clear();
}

/// Indicates that one or more partner privacy APIs rejected consent sync.
final class MediationConsentException implements Exception {
  const MediationConsentException(this.failures);

  /// Partner names mapped to their original errors.
  final Map<String, Object> failures;

  @override
  String toString() =>
      'Mediation consent sync failed: ${failures.keys.join(', ')}';
}
