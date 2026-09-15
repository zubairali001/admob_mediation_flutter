import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_config.dart';
import 'ads_service.dart';
import 'consent/consent_service.dart';
import 'consent/mediation_consent_bridge.dart';
import 'core/ad_events.dart';
import 'core/full_screen_ad_service.dart';
import 'services/app_open_ad_service.dart';
import 'services/interstitial_ad_service.dart';
import 'services/rewarded_ad_service.dart';
import 'services/rewarded_interstitial_ad_service.dart';

/// The single public entry point of the ads stack — use this like a package.
///
/// ```dart
/// // 1. Initialize once before requesting ads:
/// await AdMobMediation.initialize(
///   config: AdsConfig(
///     interstitial: AdUnitId(android: 'ca-app-pub-x/a', ios: 'ca-app-pub-x/b'),
///     rewarded: AdUnitId(android: 'ca-app-pub-x/c'),
///     appOpen: AdUnitId(android: 'ca-app-pub-x/d'),
///   ),
/// );
///
/// // 2. Show ads anywhere:
/// AdMobMediation.showInterstitial(onDismissed: goNext);
/// AdMobMediation.showRewarded(onReward: (r) => wallet.add(r.amount.toInt()));
///
/// // 3. Banner / native are widgets:
/// //    AdaptiveBannerAd(), NativeAdCard()
/// ```
abstract final class AdMobMediation {
  // ------------------------------------------------------------------
  // Initialization
  // ------------------------------------------------------------------

  /// Initializes the whole stack: UMP consent flow → partner consent sync →
  /// request configuration → Mobile Ads SDK + all mediation adapters.
  ///
  /// Safe to call multiple times (subsequent calls await the first run).
  /// Default full-screen units preload when ready. Named placements start
  /// preloading only when accessed through load, show, or readiness APIs.
  static Future<void> initialize({AdsConfig config = const AdsConfig()}) {
    final future = AdsService.instance.initialize(config: config);
    InterstitialAdService.instance;
    RewardedAdService.instance;
    RewardedInterstitialAdService.instance;
    AppOpenAdService.instance.listenToAppForeground();
    return future;
  }

  /// Retry after a failed/disabled init (e.g. consent granted later).
  static Future<void> reinitialize() => AdsService.instance.reinitialize();

  /// Current lifecycle state — bind UI to it if needed.
  static ValueListenable<AdsStatus> get status => AdsService.instance.status;

  static bool get isReady => AdsService.instance.isReady;

  /// Whether ads are allowed to load and show at runtime.
  static ValueListenable<bool> get adsEnabled => AdsService.instance.adsEnabled;

  /// Every ad event (loaded/shown/clicked/revenue/...) from every format.
  /// Attach your analytics here, once.
  static Stream<AdEvent> get events => AdEventBus.instance.stream;

  // ------------------------------------------------------------------
  // Interstitial
  // ------------------------------------------------------------------

  /// Shows the pre-loaded interstitial. Returns `false` (and pre-loads the
  /// next one) when no ad is ready or the frequency cap blocks it — just
  /// continue your flow in that case.
  static Future<bool> showInterstitial({
    String? placement,
    VoidCallback? onDismissed,
  }) => _serviceFor(
    AdFormat.interstitial,
    placement,
  ).show(onDismissed: onDismissed);

  /// Explicit pre-load; normally unnecessary (the service self-loads).
  static Future<void> loadInterstitial({String? placement}) =>
      _serviceFor(AdFormat.interstitial, placement).load();

  static ValueListenable<bool> get isInterstitialReady =>
      isAdReady(AdFormat.interstitial);

  // ------------------------------------------------------------------
  // Rewarded
  // ------------------------------------------------------------------

  /// Shows the pre-loaded rewarded ad. [onReward] fires only when the user
  /// actually earned the reward — grant it there and nowhere else.
  static Future<bool> showRewarded({
    String? placement,
    required void Function(RewardItem reward) onReward,
    VoidCallback? onDismissed,
  }) => (_serviceFor(AdFormat.rewarded, placement) as RewardedAdService)
      .showWithReward(
        onReward: (_, reward) => onReward(reward),
        onDismissed: onDismissed,
      );

  /// Preloads the selected placement; default rewarded ads also load at startup.
  static Future<void> loadRewarded({String? placement}) =>
      _serviceFor(AdFormat.rewarded, placement).load();

  static ValueListenable<bool> get isRewardedReady =>
      isAdReady(AdFormat.rewarded);

  // ------------------------------------------------------------------
  // Rewarded interstitial
  // ------------------------------------------------------------------

  static Future<bool> showRewardedInterstitial({
    String? placement,
    required void Function(RewardItem reward) onReward,
    VoidCallback? onDismissed,
  }) =>
      (_serviceFor(AdFormat.rewardedInterstitial, placement)
              as RewardedInterstitialAdService)
          .showWithReward(
            onReward: (_, reward) => onReward(reward),
            onDismissed: onDismissed,
          );

  /// Preloads the selected placement; the default unit also loads at startup.
  static Future<void> loadRewardedInterstitial({String? placement}) =>
      _serviceFor(AdFormat.rewardedInterstitial, placement).load();

  static ValueListenable<bool> get isRewardedInterstitialReady =>
      isAdReady(AdFormat.rewardedInterstitial);

  // ------------------------------------------------------------------
  // App open
  // ------------------------------------------------------------------

  /// Manually show an app open ad (e.g. on cold start after a splash).
  /// With `AdsConfig.autoShowAppOpenOnResume` (default true) one also shows
  /// automatically whenever the app returns to the foreground.
  static Future<bool> showAppOpen({
    String? placement,
    VoidCallback? onDismissed,
  }) => _serviceFor(AdFormat.appOpen, placement).show(onDismissed: onDismissed);

  static Future<void> loadAppOpen({String? placement}) =>
      _serviceFor(AdFormat.appOpen, placement).load();

  static ValueListenable<bool> get isAppOpenReady =>
      isAdReady(AdFormat.appOpen);

  /// Suppress the next automatic app-open ad (call before opening payment
  /// sheets, external sign-in, image pickers...).
  static void skipNextAppOpen() =>
      AppOpenAdService.instance.showOnNextForeground = false;

  /// Runtime on/off switch for the automatic app-open-on-foreground ad.
  /// Starts from `AdsConfig.autoShowAppOpenOnResume`; set it to `false` to
  /// stop auto-shows for the rest of the session (e.g. after the user buys
  /// "remove ads"), `true` to re-enable.
  static bool get appOpenAutoShowEnabled =>
      AppOpenAdService.instance.autoShowEnabled;
  static set appOpenAutoShowEnabled(bool enabled) =>
      AppOpenAdService.instance.autoShowEnabled = enabled;

  /// Readiness for a full-screen placement. First access starts preloading.
  /// Omit [placement] to observe the existing default unit.
  static ValueListenable<bool> isAdReady(
    AdFormat format, {
    String? placement,
  }) => _serviceFor(format, placement).isAdReady;

  /// Stops a full-screen placement's retries and releases its cached ad.
  /// Existing readiness listeners remain valid. A subsequent load, show, or
  /// readiness lookup starts preloading again. Banner/native widgets are
  /// released by removing them from the widget tree.
  static Future<void> stopPreloading(AdFormat format, {String? placement}) {
    _validateFullScreenPlacement(format, placement);
    final service = placement == null
        ? _defaultService(format)
        : _placements[(format, placement)];
    return service?.stopPreloading() ?? Future<void>.value();
  }

  static final Map<(AdFormat, String), FullScreenAdService<AdWithoutView>>
  _placements = {};

  static FullScreenAdService<AdWithoutView> _serviceFor(
    AdFormat format,
    String? placement,
  ) {
    _validateFullScreenPlacement(format, placement);
    final service = placement == null
        ? _defaultService(format)
        : _placements.putIfAbsent(
            (format, placement),
            () => switch (format) {
              AdFormat.interstitial => InterstitialAdService.forPlacement(
                placement,
              ),
              AdFormat.rewarded => RewardedAdService.forPlacement(placement),
              AdFormat.rewardedInterstitial =>
                RewardedInterstitialAdService.forPlacement(placement),
              AdFormat.appOpen => AppOpenAdService.forPlacement(placement),
              _ => throw ArgumentError.value(format, 'format'),
            },
          );
    service.startPreloading();
    return service;
  }

  static void _validateFullScreenPlacement(AdFormat format, String? placement) {
    if (format == AdFormat.banner || format == AdFormat.native) {
      throw ArgumentError.value(
        format,
        'format',
        'Use the ad widget for this format.',
      );
    }
    AdsService.instance.config.adUnitIdFor(format, placement: placement);
  }

  static FullScreenAdService<AdWithoutView> _defaultService(AdFormat format) =>
      switch (format) {
        AdFormat.interstitial => InterstitialAdService.instance,
        AdFormat.rewarded => RewardedAdService.instance,
        AdFormat.rewardedInterstitial => RewardedInterstitialAdService.instance,
        AdFormat.appOpen => AppOpenAdService.instance,
        _ => throw ArgumentError.value(format, 'format'),
      };

  // ------------------------------------------------------------------
  // Mediation consent
  // ------------------------------------------------------------------

  /// Register a consent handler for a mediation network that needs explicit
  /// consent forwarding. Call before [initialize].
  ///
  /// Follow the current privacy guide for each installed adapter. Some read
  /// standard consent strings automatically; others require this explicit hook.
  static void registerConsentHandler(
    String networkName,
    ConsentHandler handler,
  ) => MediationConsentBridge.register(networkName, handler);

  /// Removes a registered explicit partner consent handler.
  static void unregisterConsentHandler(String networkName) =>
      MediationConsentBridge.unregister(networkName);

  // ------------------------------------------------------------------
  // Consent / privacy
  // ------------------------------------------------------------------

  /// Whether your settings screen must offer a "Privacy options" entry.
  static Future<bool> isPrivacyOptionsRequired() =>
      ConsentService.instance.isPrivacyOptionsRequired();

  /// Re-opens the consent form so the user can change their choices.
  static Future<void> showPrivacyOptionsForm() async {
    await ConsentService.instance.showPrivacyOptionsForm();
    await AdsService.instance.refreshConsent();
  }

  // ------------------------------------------------------------------
  // Utilities
  // ------------------------------------------------------------------

  /// Google's on-device mediation debugging overlay.
  static void openAdInspector() => AdsService.instance.openAdInspector();

  static Future<void> setAppMuted(bool muted) =>
      AdsService.instance.setAppMuted(muted);

  static Future<void> setAppVolume(double volume) =>
      AdsService.instance.setAppVolume(volume);

  /// Runtime master switch for subscriptions, account changes, and testing.
  ///
  /// Setting this to false prevents shows, cancels retries, and disposes cached
  /// ads. Re-enabling resumes preloading for configured formats.
  static void setAdsEnabled(bool enabled) =>
      AdsService.instance.setAdsEnabled(enabled);
}
