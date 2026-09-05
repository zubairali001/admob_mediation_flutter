import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads_service.dart';
import '../core/ad_events.dart';
import '../core/full_screen_ad_service.dart';

/// Interstitial ads with pre-loading and a configurable frequency cap
/// (see `AdsConfig.interstitialMinInterval`).
class InterstitialAdService extends FullScreenAdService<InterstitialAd> {
  InterstitialAdService._() : super(format: AdFormat.interstitial);

  static final InterstitialAdService instance = InterstitialAdService._();

  @override
  Duration get minInterval =>
      AdsService.instance.config.interstitialMinInterval;

  @override
  Future<void> loadPlatformAd() {
    return InterstitialAd.load(
      adUnitId: adUnitId!,
      request: AdsService.instance.config.requestFor(format),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: onAdLoaded,
        onAdFailedToLoad: onAdFailedToLoad,
      ),
    );
  }

  @override
  Future<void> showPlatformAd(InterstitialAd ad) {
    ad.fullScreenContentCallback = buildFullScreenCallback<InterstitialAd>();
    return ad.show();
  }

  @override
  Future<void> disposePlatformAd(InterstitialAd ad) => ad.dispose();
}
