import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads_service.dart';
import '../core/ad_events.dart';
import '../core/full_screen_ad_service.dart';

/// Rewarded ads. The reward callback only fires when the user actually
/// earned it (watched enough of the ad) — grant the reward there and
/// nowhere else.
class RewardedAdService extends FullScreenAdService<RewardedAd> {
  RewardedAdService._() : super(format: AdFormat.rewarded);

  static final RewardedAdService instance = RewardedAdService._();

  OnUserEarnedRewardCallback? _pendingOnReward;

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
    return RewardedAd.load(
      adUnitId: adUnitId!,
      request: AdsService.instance.config.requestFor(format),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: onAdLoaded,
        onAdFailedToLoad: onAdFailedToLoad,
      ),
    );
  }

  @override
  Future<void> showPlatformAd(RewardedAd ad) async {
    ad.fullScreenContentCallback = buildFullScreenCallback<RewardedAd>();
    await ad.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        emitReward(reward);
        final callback = _pendingOnReward;
        _pendingOnReward = null;
        if (callback != null) {
          invokeSafely(
            () => callback(ad, reward),
            'in the rewarded ad reward callback',
          );
        }
      },
    );
  }

  @override
  Future<void> disposePlatformAd(RewardedAd ad) => ad.dispose();
}
