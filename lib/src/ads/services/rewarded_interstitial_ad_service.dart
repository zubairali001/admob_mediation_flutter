import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads_service.dart';
import '../core/ad_events.dart';
import '../core/full_screen_ad_service.dart';

/// Rewarded interstitials — shown at natural transitions without an
/// explicit opt-in button. Policy requires an intro screen telling the user
/// a reward-granting ad is coming, with a way to skip it; show that intro
/// before calling [showWithReward].
class RewardedInterstitialAdService
    extends FullScreenAdService<RewardedInterstitialAd> {
  RewardedInterstitialAdService._()
    : super(format: AdFormat.rewardedInterstitial);

  static final RewardedInterstitialAdService instance =
      RewardedInterstitialAdService._();

  OnUserEarnedRewardCallback? _pendingOnReward;

  @override
  Duration get minInterval =>
      AdsService.instance.config.rewardedInterstitialMinInterval;

  Future<bool> showWithReward({
    required OnUserEarnedRewardCallback onReward,
    VoidCallback? onDismissed,
  }) async {
    return show(
      onDismissed: onDismissed,
      onWillShow: () => _pendingOnReward = onReward,
      onFinished: () => _pendingOnReward = null,
    );
  }

  @override
  Future<void> loadPlatformAd() {
    return RewardedInterstitialAd.load(
      adUnitId: adUnitId!,
      request: AdsService.instance.config.requestFor(format),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: onAdLoaded,
        onAdFailedToLoad: onAdFailedToLoad,
      ),
    );
  }

  @override
  Future<void> showPlatformAd(RewardedInterstitialAd ad) async {
    ad.fullScreenContentCallback =
        buildFullScreenCallback<RewardedInterstitialAd>();
    await ad.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        emitReward(reward);
        final callback = _pendingOnReward;
        _pendingOnReward = null;
        if (callback != null) {
          invokeSafely(
            () => callback(ad, reward),
            'in the rewarded interstitial reward callback',
          );
        }
      },
    );
  }

  @override
  Future<void> disposePlatformAd(RewardedInterstitialAd ad) => ad.dispose();
}
