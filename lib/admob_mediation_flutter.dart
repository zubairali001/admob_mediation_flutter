/// Production-ready AdMob mediation for Flutter.
///
/// ```dart
/// import 'package:admob_mediation_flutter/admob_mediation_flutter.dart';
/// ```
///
/// Start with [AdMobMediation.initialize], show ads with
/// [AdMobMediation.showInterstitial] / [AdMobMediation.showRewarded] /
/// etc., and drop [AdaptiveBannerAd] or [NativeAdCard] widgets into your
/// tree. Wire analytics once via [AdMobMediation.events].
library;

export 'src/ads/ads.dart';

// Re-export types from google_mobile_ads that appear in this package's API
// so users need only one import for common usage.
export 'package:google_mobile_ads/google_mobile_ads.dart'
    show RewardItem, TemplateType, DebugGeography;
