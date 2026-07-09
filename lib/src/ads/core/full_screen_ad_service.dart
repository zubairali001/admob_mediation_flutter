import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads_service.dart';
import 'ad_events.dart';
import 'retry_policy.dart';

/// Base class for all full-screen ad services (app open, interstitial,
/// rewarded, rewarded interstitial).
///
/// Provides the shared machinery so each concrete service is only ~40 lines:
///
///  * **Lazy subscription** — services do nothing until [AdsService] reports
///    [AdsStatus.ready], then pre-load automatically.
///  * **Single cached ad + auto pre-load** — after every show/failure the
///    next ad is loaded immediately so one is always warm.
///  * **Exponential backoff** on no-fill via [RetryPolicy].
///  * **TTL expiry** — cached ads are dropped after [ttl] (AdMob ads go
///    stale after ~1 hour, app open ads after 4).
///  * **Global frequency capping** — a shared timestamp prevents two
///    full-screen ads from stacking, plus a per-service [minInterval].
///  * **Event emission** for analytics via [AdEventBus].
abstract class FullScreenAdService<T extends AdWithoutView> {
  FullScreenAdService({
    required this.format,
    this.ttl = const Duration(hours: 1),
  }) {
    AdsService.instance.status.addListener(_onAdsStatusChanged);
    _onAdsStatusChanged();
  }

  final AdFormat format;

  /// How long a loaded ad stays valid before being discarded.
  final Duration ttl;

  /// Minimum time between two shows of *this* service. Override to read
  /// from [AdsService.instance.config] so it stays configurable per app.
  Duration get minInterval => Duration.zero;

  /// Shared across every full-screen service so ads never show back-to-back.
  static DateTime? lastFullScreenShownAt;
  static bool isAnyFullScreenAdShowing = false;

  /// Bind this to UI (e.g. enable a button) — true when an ad is ready.
  final ValueNotifier<bool> isAdReady = ValueNotifier<bool>(false);

  T? _ad;
  DateTime? _loadedAt;
  DateTime? _lastShownAt;
  bool _isLoading = false;
  Timer? _retryTimer;
  final RetryPolicy _retry = RetryPolicy();

  // ------------------------------------------------------------------
  // Subclass contract
  // ------------------------------------------------------------------

  /// Resolved from the app's [AdsConfig]; null when the format isn't
  /// configured for this platform (the service then stays idle).
  String? get adUnitId => AdsService.instance.config.adUnitIdFor(format);

  /// Kick off the platform load call; report back through
  /// [onAdLoaded] / [onAdFailedToLoad].
  @protected
  Future<void> loadPlatformAd();

  /// Set `ad.fullScreenContentCallback = buildFullScreenCallback(...)` and
  /// invoke the type-specific `ad.show(...)`.
  @protected
  Future<void> showPlatformAd(T ad);

  @protected
  Future<void> disposePlatformAd(T ad);

  // ------------------------------------------------------------------
  // Public API
  // ------------------------------------------------------------------

  bool get isAdAvailable {
    if (_ad == null || _loadedAt == null) return false;
    return DateTime.now().difference(_loadedAt!) < ttl;
  }

  /// Loads an ad if none is cached and none is in flight. Safe to call often.
  Future<void> load() async {
    if (!AdsService.instance.isReady || _isLoading) return;
    if (isAdAvailable || adUnitId == null) return;
    await _discardCachedAd();

    _isLoading = true;
    _emit(AdEventType.requested);
    await loadPlatformAd();
  }

  /// Shows the cached ad if available and allowed by frequency caps.
  ///
  /// Returns `true` if the ad was actually shown. When it returns `false`
  /// (not ready / capped), the next ad load is triggered automatically —
  /// callers should simply continue their flow.
  Future<bool> show({VoidCallback? onDismissed}) async {
    if (isAnyFullScreenAdShowing) return false;
    if (!_isIntervalElapsed) return false;
    if (!isAdAvailable) {
      unawaited(load());
      return false;
    }

    final ad = _ad!;
    _ad = null;
    isAdReady.value = false;
    _pendingOnDismissed = onDismissed;

    isAnyFullScreenAdShowing = true;
    await showPlatformAd(ad);
    return true;
  }

  @mustCallSuper
  void dispose() {
    AdsService.instance.status.removeListener(_onAdsStatusChanged);
    _retryTimer?.cancel();
    _discardCachedAd();
    isAdReady.dispose();
  }

  // ------------------------------------------------------------------
  // Shared machinery for subclasses
  // ------------------------------------------------------------------

  VoidCallback? _pendingOnDismissed;

  @protected
  void onAdLoaded(T ad) {
    _ad = ad;
    _loadedAt = DateTime.now();
    _isLoading = false;
    _retry.reset();
    isAdReady.value = true;
    _attachPaidEvent(ad);
    _emit(AdEventType.loaded, adapter: _adapterOf(ad));
  }

  @protected
  void onAdFailedToLoad(LoadAdError error) {
    _isLoading = false;
    _emit(AdEventType.failedToLoad, error: error);
    if (_retry.canRetry) {
      _retryTimer?.cancel();
      _retryTimer = Timer(_retry.nextDelay(), load);
    }
  }

  /// Standard callback wiring shared by all full-screen formats.
  @protected
  FullScreenContentCallback<A> buildFullScreenCallback<A extends Ad>() {
    return FullScreenContentCallback<A>(
      onAdShowedFullScreenContent: (ad) {
        _lastShownAt = DateTime.now();
        lastFullScreenShownAt = _lastShownAt;
        _emit(AdEventType.shown, adapter: _adapterOf(ad));
      },
      onAdImpression: (ad) => _emit(AdEventType.impression, adapter: _adapterOf(ad)),
      onAdClicked: (ad) => _emit(AdEventType.clicked),
      onAdFailedToShowFullScreenContent: (ad, error) {
        _emit(AdEventType.failedToShow, error: error);
        isAnyFullScreenAdShowing = false;
        ad.dispose();
        _finishShow();
      },
      onAdDismissedFullScreenContent: (ad) {
        _emit(AdEventType.dismissed);
        isAnyFullScreenAdShowing = false;
        ad.dispose();
        _finishShow();
      },
    );
  }

  @protected
  void emitReward(RewardItem reward) =>
      _emit(AdEventType.rewardEarned, reward: reward);

  // ------------------------------------------------------------------
  // Internals
  // ------------------------------------------------------------------

  void _onAdsStatusChanged() {
    // Warm up as soon as the SDK is ready — this is the "subscribe and work
    // when needed" hook: no service issues a single call before this fires.
    if (AdsService.instance.isReady) load();
  }

  void _finishShow() {
    final callback = _pendingOnDismissed;
    _pendingOnDismissed = null;
    callback?.call();
    unawaited(load()); // Pre-load the next one right away.
  }

  bool get _isIntervalElapsed {
    if (_lastShownAt == null || minInterval == Duration.zero) return true;
    return DateTime.now().difference(_lastShownAt!) >= minInterval;
  }

  void _attachPaidEvent(T ad) {
    ad.onPaidEvent = (Ad paidAd, double valueMicros, PrecisionType precision, String currencyCode) {
      _emit(
        AdEventType.paid,
        revenue: AdRevenue(
          valueMicros: valueMicros,
          currencyCode: currencyCode,
          precision: precision,
        ),
        adapter: _adapterOf(paidAd),
      );
    };
  }

  Future<void> _discardCachedAd() async {
    final ad = _ad;
    _ad = null;
    _loadedAt = null;
    isAdReady.value = false;
    if (ad != null) await disposePlatformAd(ad);
  }

  String? _adapterOf(Ad ad) => ad.responseInfo?.mediationAdapterClassName;

  void _emit(
    AdEventType type, {
    Object? error,
    RewardItem? reward,
    AdRevenue? revenue,
    String? adapter,
  }) {
    AdEventBus.instance.emit(AdEvent(
      format: format,
      type: type,
      error: error,
      reward: reward,
      revenue: revenue,
      mediationAdapter: adapter,
    ));
  }
}
