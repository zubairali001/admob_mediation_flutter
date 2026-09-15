import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'consent/mediation_consent_bridge.dart';
import 'core/ad_events.dart';

/// A pair of platform-specific ad unit ids for one ad format.
///
/// Leave a platform `null` if you don't serve that format there.
@immutable
final class AdUnitId {
  const AdUnitId({this.android, this.ios});

  final String? android;
  final String? ios;

  /// Resolves the identifier for the active Flutter target platform.
  String? resolve() {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS => ios,
      _ => null,
    };
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
@immutable
final class AdsConfig {
  const AdsConfig({
    this.appOpen = const AdUnitId(),
    this.banner = const AdUnitId(),
    this.interstitial = const AdUnitId(),
    this.rewarded = const AdUnitId(),
    this.rewardedInterstitial = const AdUnitId(),
    this.native = const AdUnitId(),
    this.appOpenPlacements = const <String, AdUnitId>{},
    this.bannerPlacements = const <String, AdUnitId>{},
    this.interstitialPlacements = const <String, AdUnitId>{},
    this.rewardedPlacements = const <String, AdUnitId>{},
    this.rewardedInterstitialPlacements = const <String, AdUnitId>{},
    this.nativePlacements = const <String, AdUnitId>{},
    bool? useTestAds,
    this.testDeviceIds = const <String>[],
    this.ageRestrictedTreatment = AgeRestrictedTreatment.unspecified,
    this.underAgeOfConsent,
    this.maxAdContentRating,
    this.adRequest = const AdRequest(),
    this.interstitialMinInterval = const Duration(seconds: 60),
    this.rewardedInterstitialMinInterval = const Duration(seconds: 60),
    this.autoShowAppOpenOnResume = true,
    this.debugGeography,
    this.mediationConsentProvider,
  }) : useTestAds =
           useTestAds ??
           (kDebugMode || const bool.fromEnvironment('FORCE_TEST_ADS'));

  /// Ad unit ids per format. Any format you don't configure simply won't
  /// serve (its service stays idle after the first failed lookup).
  final AdUnitId appOpen;
  final AdUnitId banner;
  final AdUnitId interstitial;
  final AdUnitId rewarded;
  final AdUnitId rewardedInterstitial;
  final AdUnitId native;

  /// Named ad units per format. Keys identify locations in your app.
  /// Treat these maps as immutable after initialization. Named full-screen
  /// placements preload only when first accessed, not all at startup.
  final Map<String, AdUnitId> appOpenPlacements;
  final Map<String, AdUnitId> bannerPlacements;
  final Map<String, AdUnitId> interstitialPlacements;
  final Map<String, AdUnitId> rewardedPlacements;
  final Map<String, AdUnitId> rewardedInterstitialPlacements;
  final Map<String, AdUnitId> nativePlacements;

  /// When true, Google's public test id replaces each configured format.
  /// Defaults to true in debug builds (or with --dart-define=FORCE_TEST_ADS=true).
  final bool useTestAds;

  /// Hashed device ids (printed in the console on first run) that receive
  /// test ads even against production ad units.
  final List<String> testDeviceIds;

  /// Age treatment applied to every Google Mobile Ads request.
  final AgeRestrictedTreatment ageRestrictedTreatment;

  /// UMP under-age-of-consent signal. Leave null when it isn't known.
  final bool? underAgeOfConsent;

  /// One of the [MaxAdContentRating] constants (G, PG, T, MA).
  final String? maxAdContentRating;

  /// Base request copied for each format.
  ///
  /// Use this for keywords, content URLs, non-personalized ads, mediation
  /// extras, or the `rdp` extra required by your US-state privacy design.
  final AdRequest adRequest;

  /// Frequency caps for the full-screen formats.
  final Duration interstitialMinInterval;
  final Duration rewardedInterstitialMinInterval;

  /// Show an app open ad automatically when the app returns to foreground.
  final bool autoShowAppOpenOnResume;

  /// Set to [DebugGeography.debugGeographyEea] to test the GDPR consent
  /// form from anywhere. Ignored in release builds.
  final DebugGeography? debugGeography;

  /// Required when explicit partner consent handlers are registered.
  ///
  /// This callback must return the current choices from your CMP after the
  /// UMP flow has completed.
  final MediationConsentProvider? mediationConsentProvider;

  /// Resolves the ad unit id to request for [format], falling back to
  /// Google's test ids when [useTestAds] is on. Returns null when the
  /// format isn't configured for the current platform. Named lookups never
  /// fall back to the default; unknown/blank names throw [ArgumentError].
  /// [placement] and a direct [adUnitId] override are mutually exclusive.
  String? adUnitIdFor(AdFormat format, {String? placement, String? adUnitId}) {
    if (placement != null && adUnitId != null) {
      throw ArgumentError('Specify either placement or adUnitId, not both.');
    }
    final unit = placement != null
        ? _placementFor(format, placement)
        : switch (format) {
            AdFormat.appOpen => appOpen,
            AdFormat.banner => banner,
            AdFormat.interstitial => interstitial,
            AdFormat.rewarded => rewarded,
            AdFormat.rewardedInterstitial => rewardedInterstitial,
            AdFormat.native => native,
          };
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return null;
    }
    final configuredId = (adUnitId ?? unit.resolve())?.trim();
    if (configuredId == null || configuredId.isEmpty) return null;
    return useTestAds ? _googleTestId(format) : configuredId;
  }

  /// Registered placements for [format].
  Map<String, AdUnitId> placementsFor(AdFormat format) => switch (format) {
    AdFormat.appOpen => appOpenPlacements,
    AdFormat.banner => bannerPlacements,
    AdFormat.interstitial => interstitialPlacements,
    AdFormat.rewarded => rewardedPlacements,
    AdFormat.rewardedInterstitial => rewardedInterstitialPlacements,
    AdFormat.native => nativePlacements,
  };

  AdUnitId _placementFor(AdFormat format, String placement) {
    final unit = placementsFor(format)[placement];
    if (placement.trim().isEmpty || unit == null) {
      throw ArgumentError.value(
        placement,
        'placement',
        'No ${format.name} ad unit is registered for this placement.',
      );
    }
    return unit;
  }

  /// Takes an immutable snapshot for the initialized service.
  @internal
  AdsConfig snapshot() {
    for (final format in AdFormat.values) {
      for (final name in placementsFor(format).keys) {
        if (name.isEmpty || name.trim() != name) {
          throw ArgumentError.value(
            name,
            '${format.name}Placements',
            'Placement names must be nonempty with no surrounding whitespace.',
          );
        }
      }
    }
    return AdsConfig(
      appOpen: appOpen,
      banner: banner,
      interstitial: interstitial,
      rewarded: rewarded,
      rewardedInterstitial: rewardedInterstitial,
      native: native,
      useTestAds: useTestAds,
      ageRestrictedTreatment: ageRestrictedTreatment,
      underAgeOfConsent: underAgeOfConsent,
      maxAdContentRating: maxAdContentRating,
      adRequest: adRequest,
      interstitialMinInterval: interstitialMinInterval,
      rewardedInterstitialMinInterval: rewardedInterstitialMinInterval,
      autoShowAppOpenOnResume: autoShowAppOpenOnResume,
      debugGeography: debugGeography,
      mediationConsentProvider: mediationConsentProvider,
      appOpenPlacements: Map.unmodifiable(appOpenPlacements),
      bannerPlacements: Map.unmodifiable(bannerPlacements),
      interstitialPlacements: Map.unmodifiable(interstitialPlacements),
      rewardedPlacements: Map.unmodifiable(rewardedPlacements),
      rewardedInterstitialPlacements: Map.unmodifiable(
        rewardedInterstitialPlacements,
      ),
      nativePlacements: Map.unmodifiable(nativePlacements),
      testDeviceIds: List.unmodifiable(testDeviceIds),
    );
  }

  /// Builds the request for [format], optionally merging adapter [extras].
  AdRequest requestFor(AdFormat format, {Map<String, String>? extras}) {
    final base = adRequest;
    return AdRequest(
      keywords: base.keywords,
      contentUrl: base.contentUrl,
      neighboringContentUrls: base.neighboringContentUrls,
      nonPersonalizedAds: base.nonPersonalizedAds,
      httpTimeoutMillis: base.httpTimeoutMillis,
      extras: <String, String>{...?base.extras, ...?extras},
      mediationExtras: base.mediationExtras,
    );
  }

  static String _googleTestId(AdFormat format) {
    final android = defaultTargetPlatform == TargetPlatform.android;
    return switch (format) {
      AdFormat.appOpen =>
        android
            ? 'ca-app-pub-3940256099942544/9257395921'
            : 'ca-app-pub-3940256099942544/5575463023',
      AdFormat.banner =>
        android
            ? 'ca-app-pub-3940256099942544/9214589741'
            : 'ca-app-pub-3940256099942544/2435281174',
      AdFormat.interstitial =>
        android
            ? 'ca-app-pub-3940256099942544/1033173712'
            : 'ca-app-pub-3940256099942544/4411468910',
      AdFormat.rewarded =>
        android
            ? 'ca-app-pub-3940256099942544/5224354917'
            : 'ca-app-pub-3940256099942544/1712485313',
      AdFormat.rewardedInterstitial =>
        android
            ? 'ca-app-pub-3940256099942544/5354046379'
            : 'ca-app-pub-3940256099942544/6978759866',
      AdFormat.native =>
        android
            ? 'ca-app-pub-3940256099942544/2247696110'
            : 'ca-app-pub-3940256099942544/3986624511',
    };
  }
}
