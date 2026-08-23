import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_config.dart';
import 'ads_service.dart';
import 'consent/consent_service.dart';
import 'core/ad_events.dart';
import 'services/app_open_ad_service.dart';
import 'services/interstitial_ad_service.dart';
import 'services/rewarded_ad_service.dart';
import 'services/rewarded_interstitial_ad_service.dart';

/// The single public entry point of the ads stack — use this like a package.
///
/// ```dart
/// // 1. Initialize once (non-blocking; runs consent + SDK boot):
/// AdMobMediation.initialize(
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
  /// Full-screen services subscribe immediately and pre-load their first ad
  /// the moment the SDK is ready.
  static Future<void> initialize({AdsConfig config = const AdsConfig()}) {
    final future = AdsService.instance.initialize(config: config);
    // Touch the singletons so they subscribe to the ready signal.
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

  /// Every ad event (loaded/shown/clicked/revenue/...) from every format.
  /// Attach your analytics here, once.
  static Stream<AdEvent> get events => AdEventBus.instance.stream;

  // ------------------------------------------------------------------
  // Interstitial
  // ------------------------------------------------------------------

  /// Shows the pre-loaded interstitial. Returns `false` (and pre-loads the
  /// next one) when no ad is ready or the frequency cap blocks it — just
  /// continue your flow in that case.
  static Future<bool> showInterstitial({VoidCallback? onDismissed}) =>
      InterstitialAdService.instance.show(onDismissed: onDismissed);

  /// Explicit pre-load; normally unnecessary (the service self-loads).
  static Future<void> loadInterstitial() =>
      InterstitialAdService.instance.load();

  static ValueListenable<bool> get isInterstitialReady =>
      InterstitialAdService.instance.isAdReady;

  // ------------------------------------------------------------------
  // Rewarded
  // ------------------------------------------------------------------

  /// Shows the pre-loaded rewarded ad. [onReward] fires only when the user
  /// actually earned the reward — grant it there and nowhere else.
  static Future<bool> showRewarded({
    required void Function(RewardItem reward) onReward,
    VoidCallback? onDismissed,
  }) => RewardedAdService.instance.showWithReward(
    onReward: (_, reward) => onReward(reward),
    onDismissed: onDismissed,
  );

  static Future<void> loadRewarded() => RewardedAdService.instance.load();

  static ValueListenable<bool> get isRewardedReady =>
      RewardedAdService.instance.isAdReady;

  // ------------------------------------------------------------------
  // Rewarded interstitial
  // ------------------------------------------------------------------

  static Future<bool> showRewardedInterstitial({
    required void Function(RewardItem reward) onReward,
    VoidCallback? onDismissed,
  }) => RewardedInterstitialAdService.instance.showWithReward(
    onReward: (_, reward) => onReward(reward),
    onDismissed: onDismissed,
  );

  static Future<void> loadRewardedInterstitial() =>
      RewardedInterstitialAdService.instance.load();

  static ValueListenable<bool> get isRewardedInterstitialReady =>
      RewardedInterstitialAdService.instance.isAdReady;

  // ------------------------------------------------------------------
  // App open
  // ------------------------------------------------------------------

  /// Manually show an app open ad (e.g. on cold start after a splash).
  /// With `AdsConfig.autoShowAppOpenOnResume` (default true) one also shows
  /// automatically whenever the app returns to the foreground.
  static Future<bool> showAppOpen() => AppOpenAdService.instance.show();

  static Future<void> loadAppOpen() => AppOpenAdService.instance.load();

  static ValueListenable<bool> get isAppOpenReady =>
      AppOpenAdService.instance.isAdReady;

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

  // ------------------------------------------------------------------
  // Consent / privacy
  // ------------------------------------------------------------------

  /// Whether your settings screen must offer a "Privacy options" entry.
  static Future<bool> isPrivacyOptionsRequired() =>
      ConsentService.instance.isPrivacyOptionsRequired();

  /// Re-opens the consent form so the user can change their choices.
  static Future<void> showPrivacyOptionsForm() =>
      ConsentService.instance.showPrivacyOptionsForm();

  // ------------------------------------------------------------------
  // Utilities
  // ------------------------------------------------------------------

  /// Google's on-device mediation debugging overlay.
  static void openAdInspector() => AdsService.instance.openAdInspector();

  static Future<void> setAppMuted(bool muted) =>
      AdsService.instance.setAppMuted(muted);

  static Future<void> setAppVolume(double volume) =>
      AdsService.instance.setAppVolume(volume);
}
