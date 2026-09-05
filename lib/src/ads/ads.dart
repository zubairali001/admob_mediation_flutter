/// Public API of the admob_mediation_flutter package.
///
/// ```dart
/// import 'package:admob_mediation_flutter/admob_mediation_flutter.dart';
/// ```
///
/// Main entry point: [AdMobMediation]. Configuration: [AdsConfig] / [AdUnitId].
/// Widgets: [AdaptiveBannerAd], [NativeAdCard]. Analytics: [AdEventBus].
library;

export 'admob_mediation.dart';
export 'ads_config.dart';
export 'ads_service.dart' show AdsStatus;
export 'consent/mediation_consent_bridge.dart';
export 'core/ad_events.dart';
export 'widgets/adaptive_banner_ad.dart';
export 'widgets/native_ad_card.dart';
