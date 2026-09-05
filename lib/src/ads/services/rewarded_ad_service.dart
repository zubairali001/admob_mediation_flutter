import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/ad_events.dart';
import '../core/full_screen_ad_service.dart';

/// Rewarded ads. The reward callback only fires when the user actually
/// earned it (watched enough of the ad) — grant the reward there and
/// nowhere else.
class RewardedAdService extends FullScreenAdService<RewardedAd> {
  RewardedAdService._() : super(format: AdFormat.rewarded, autoPreload: false);

  static final RewardedAdService instance = RewardedAdService._();

  OnUserEarnedRewardCallback? _pendingOnReward;
  int _preloadClients = 0;

  void acquirePreload() {
    _preloadClients++;
    if (_preloadClients == 1) startPreloading();
  }

  void releasePreload() {
    if (_preloadClients == 0) return;
    _preloadClients--;
    if (_preloadClients == 0) unawaited(stopPreloading());
  }

  Future<bool> showWithReward({
    required OnUserEarnedRewardCallback onReward,
    VoidCallback? onDismissed,
  }) async {
    _pendingOnReward = onReward;
    final shown = await show(onDismissed: onDismissed);
    if (!shown) {
      _pendingOnReward = null;
    }
    return shown;
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
  Future<void> showPlatformAd(RewardedAd ad) async {
    ad.fullScreenContentCallback = buildFullScreenCallback<RewardedAd>();
    await ad.show(
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
