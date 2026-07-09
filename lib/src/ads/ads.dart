/// Public entry point for the ads stack. Import this one file:
///
/// ```dart
/// import 'package:admob_mediation_flutter/src/ads/ads.dart';
/// ```
///
/// Main API: [AdMobMediation] (functions per format), [AdsConfig]
/// (initialization parameters), `AdaptiveBannerAd` / `NativeAdCard` widgets,
/// and [AdEventBus] for analytics.
library;

export 'admob_mediation.dart';
export 'ads_config.dart';
export 'ads_service.dart';
export 'consent/consent_service.dart';
export 'consent/mediation_consent_bridge.dart';
export 'core/ad_events.dart';
export 'core/full_screen_ad_service.dart';
export 'services/app_open_ad_service.dart';
export 'services/interstitial_ad_service.dart';
export 'services/rewarded_ad_service.dart';
export 'services/rewarded_interstitial_ad_service.dart';
export 'widgets/adaptive_banner_ad.dart';
export 'widgets/native_ad_card.dart';
