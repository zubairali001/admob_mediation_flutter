import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'core/ad_events.dart';

/// A pair of platform-specific ad unit ids for one ad format.
///
/// Leave a platform `null` if you don't serve that format there.
class AdUnitId {
  const AdUnitId({this.android, this.ios});

  final String? android;
  final String? ios;

  String? resolve() {
    if (Platform.isAndroid) return android;
    if (Platform.isIOS) return ios;
    return null;
  }
}

/// Everything the ads stack needs, passed once to
/// `AdMobMediation.initialize(config: ...)`.
///
/// ```dart
/// AdsConfig(
///   interstitial: AdUnitId(
///     android: 'ca-app-pub-xxx/aaa',
///     ios: 'ca-app-pub-xxx/bbb',
///   ),
///   banner: AdUnitId(android: 'ca-app-pub-xxx/ccc'),
///   testDeviceIds: ['YOUR-HASHED-DEVICE-ID'],
/// )
/// ```
class AdsConfig {
  const AdsConfig({
    this.appOpen = const AdUnitId(),
    this.banner = const AdUnitId(),
    this.interstitial = const AdUnitId(),
    this.rewarded = const AdUnitId(),
    this.rewardedInterstitial = const AdUnitId(),
    this.native = const AdUnitId(),
    bool? useTestAds,
    this.testDeviceIds = const <String>[],
    this.childDirected = false,
    this.maxAdContentRating,
    this.interstitialMinInterval = const Duration(seconds: 60),
    this.rewardedInterstitialMinInterval = const Duration(seconds: 60),
    this.autoShowAppOpenOnResume = true,
    this.debugGeography,
  }) : useTestAds = useTestAds ??
            (kDebugMode || const bool.fromEnvironment('FORCE_TEST_ADS'));

  /// Ad unit ids per format. Any format you don't configure simply won't
  /// serve (its service stays idle after the first failed lookup).
  final AdUnitId appOpen;
  final AdUnitId banner;
  final AdUnitId interstitial;
  final AdUnitId rewarded;
  final AdUnitId rewardedInterstitial;
  final AdUnitId native;

  /// When true, Google's public test ids replace all of the above.
  /// Defaults to true in debug builds (or with --dart-define=FORCE_TEST_ADS=true).
  final bool useTestAds;

  /// Hashed device ids (printed in the console on first run) that receive
  /// test ads even against production ad units.
  final List<String> testDeviceIds;

  /// COPPA flag — must match your AdMob app settings.
  final bool childDirected;

  /// One of the [MaxAdContentRating] constants (G, PG, T, MA).
  final String? maxAdContentRating;

  /// Frequency caps for the full-screen formats.
  final Duration interstitialMinInterval;
  final Duration rewardedInterstitialMinInterval;

  /// Show an app open ad automatically when the app returns to foreground.
  final bool autoShowAppOpenOnResume;

  /// Set to [DebugGeography.debugGeographyEea] to test the GDPR consent
  /// form from anywhere. Ignored in release builds.
  final DebugGeography? debugGeography;

  /// Resolves the ad unit id to request for [format], falling back to
  /// Google's test ids when [useTestAds] is on. Returns null when the
  /// format isn't configured for the current platform.
  String? adUnitIdFor(AdFormat format) {
    if (useTestAds) return _googleTestId(format);
    final id = switch (format) {
      AdFormat.appOpen => appOpen,
      AdFormat.banner => banner,
      AdFormat.interstitial => interstitial,
      AdFormat.rewarded => rewarded,
      AdFormat.rewardedInterstitial => rewardedInterstitial,
      AdFormat.native => native,
    }
        .resolve();
    assert(
      id != null,
      'No ${format.name} ad unit id configured for this platform. '
      'Pass one in AdsConfig or enable useTestAds.',
    );
    return id;
  }

  static String _googleTestId(AdFormat format) {
    final android = Platform.isAndroid;
    return switch (format) {
      AdFormat.appOpen => android
          ? 'ca-app-pub-3940256099942544/9257395921'
          : 'ca-app-pub-3940256099942544/5575463023',
      AdFormat.banner => android
          ? 'ca-app-pub-3940256099942544/9214589741'
          : 'ca-app-pub-3940256099942544/2435281174',
      AdFormat.interstitial => android
          ? 'ca-app-pub-3940256099942544/1033173712'
          : 'ca-app-pub-3940256099942544/4411468910',
      AdFormat.rewarded => android
          ? 'ca-app-pub-3940256099942544/5224354917'
          : 'ca-app-pub-3940256099942544/1712485313',
      AdFormat.rewardedInterstitial => android
          ? 'ca-app-pub-3940256099942544/5354046379'
          : 'ca-app-pub-3940256099942544/6978759866',
      AdFormat.native => android
          ? 'ca-app-pub-3940256099942544/2247696110'
          : 'ca-app-pub-3940256099942544/3986624511',
    };
  }
}
