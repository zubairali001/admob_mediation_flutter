/// Public API of the admob_mediation_flutter package.
///
/// ```dart
/// import 'package:admob_mediation_flutter/admob_mediation_flutter.dart';
/// ```
///
/// Main entry point: [AdMobMediation]. Configuration: [AdsConfig] / [AdUnitId].
/// Widgets: [AdaptiveBannerAd], [NativeAdCard]. Analytics: [AdEvent].
library;

export 'admob_mediation.dart';
export 'ads_config.dart';
export 'ads_service.dart' show AdsStatus;
export 'consent/mediation_consent_bridge.dart'
    show
        ConsentHandler,
        MediationConsent,
        MediationConsentException,
        MediationConsentProvider;
export 'core/ad_events.dart' show AdEvent, AdEventType, AdFormat, AdRevenue;
export 'widgets/adaptive_banner_ad.dart';
export 'widgets/native_ad_card.dart';
