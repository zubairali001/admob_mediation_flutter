import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_config.dart';
import 'consent/consent_service.dart';
import 'consent/mediation_consent_bridge.dart';

/// Global initialization state of the ads stack.
enum AdsStatus {
  /// [AdsService.initialize] has not been called yet.
  idle,

  /// Consent flow and SDK initialization in progress.
  initializing,

  /// SDK initialized — services may load ads.
  ready,

  /// Consent denied / unavailable: no ad may be requested this session.
  disabled,
}

/// Orchestrates the whole ads stack exactly once per app launch:
///
///  1. Gathers consent via UMP ([ConsentService]).
///  2. Forwards consent to mediation partners ([MediationConsentBridge]).
///  3. Applies the global [RequestConfiguration].
///  4. Initializes the Google Mobile Ads SDK (which in turn initializes
///     every bundled mediation adapter).
///
/// Individual ad services never talk to `MobileAds` directly — they observe
/// [status] and start working only when it flips to [AdsStatus.ready]. That
/// keeps startup non-blocking and guarantees no ad request ever fires before
/// consent is resolved.
class AdsService {
  AdsService._();

  static final AdsService instance = AdsService._();

  final ValueNotifier<AdsStatus> status = ValueNotifier<AdsStatus>(AdsStatus.idle);

  bool get isReady => status.value == AdsStatus.ready;

  AdsConfig _config = const AdsConfig();

  /// The configuration passed to [initialize]. Defaults (test ads) apply
  /// until then.
  AdsConfig get config => _config;

  Future<void>? _initialization;

  /// Idempotent: concurrent/repeated calls await the same future.
  Future<void> initialize({AdsConfig config = const AdsConfig()}) {
    if (_initialization == null) _config = config;
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    status.value = AdsStatus.initializing;

    try {
      // 1. Consent first — nothing may hit the network with an ad request
      //    until UMP says we can.
      final canRequestAds = await ConsentService.instance.gatherConsent(
        debugGeography: _config.debugGeography,
        testDeviceHashedIds: _config.testDeviceIds,
      );
      if (!canRequestAds) {
        debugPrint('[Ads] Consent unavailable — ads disabled for this session.');
        status.value = AdsStatus.disabled;
        return;
      }

      // 2. Mirror consent to mediation partners before their SDKs boot.
      await MediationConsentBridge.syncFromUmp();

      // 3. Global request configuration.
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          testDeviceIds: _config.testDeviceIds,
          maxAdContentRating: _config.maxAdContentRating,
          tagForChildDirectedTreatment: _config.childDirected
              ? TagForChildDirectedTreatment.yes
              : TagForChildDirectedTreatment.unspecified,
          tagForUnderAgeOfConsent: TagForUnderAgeOfConsent.unspecified,
        ),
      );

      // 4. Boot the SDK + every mediation adapter.
      final initStatus = await MobileAds.instance.initialize();
      _logAdapterStatuses(initStatus);

      status.value = AdsStatus.ready;
    } catch (e, s) {
      debugPrint('[Ads] Initialization failed: $e\n$s');
      status.value = AdsStatus.disabled;
    }
  }

  /// Retry after a failed/disabled initialization (e.g. user granted consent
  /// later through the privacy options form).
  Future<void> reinitialize() {
    if (isReady || status.value == AdsStatus.initializing) {
      return _initialization ?? Future.value();
    }
    _initialization = null;
    return initialize(config: _config);
  }

  /// Opens Google's Ad Inspector overlay — the single best tool to verify
  /// your mediation waterfall on a real device.
  void openAdInspector() {
    MobileAds.instance.openAdInspector((error) {
      if (error != null) {
        debugPrint('[Ads] Ad inspector error: ${error.message}');
      }
    });
  }

  /// Mute/unmute all ads app-wide (e.g. while the user plays music).
  Future<void> setAppMuted(bool muted) => MobileAds.instance.setAppMuted(muted);

  /// 0.0 – 1.0. Reported to networks so video ads respect app volume.
  Future<void> setAppVolume(double volume) => MobileAds.instance.setAppVolume(volume);

  void _logAdapterStatuses(InitializationStatus initStatus) {
    initStatus.adapterStatuses.forEach((adapter, adapterStatus) {
      debugPrint(
        '[Ads] Adapter $adapter: ${adapterStatus.state.name}'
        ' (${adapterStatus.description})',
      );
    });
  }
}
