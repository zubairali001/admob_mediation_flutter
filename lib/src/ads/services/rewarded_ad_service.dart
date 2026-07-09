import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

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
  }) {
    _pendingOnReward = onReward;
    return show(onDismissed: onDismissed);
  }

  @override
  Future<void> loadPlatformAd() {
    return RewardedAd.load(
      adUnitId: adUnitId!,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: onAdLoaded,
        onAdFailedToLoad: onAdFailedToLoad,
      ),
    );
  }

  @override
  Future<void> showPlatformAd(RewardedAd ad) {
    ad.fullScreenContentCallback = buildFullScreenCallback<RewardedAd>();
    return ad.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        emitReward(reward);
        _pendingOnReward?.call(ad, reward);
        _pendingOnReward = null;
      },
    );
  }

  @override
  Future<void> disposePlatformAd(RewardedAd ad) => ad.dispose();
}
