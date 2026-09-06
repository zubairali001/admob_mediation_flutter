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
///  * **Show coordination** — a shared lock prevents full-screen ads from
///    stacking, plus a per-service [minInterval].
///  * **Event emission** for analytics via [AdEventBus].
abstract class FullScreenAdService<T extends AdWithoutView> {
  FullScreenAdService({
    required this.format,
    this.ttl = const Duration(hours: 1),
    bool autoPreload = true,
    bool Function()? canServeAds,
    DateTime Function()? now,
  }) : _preloadEnabled = autoPreload,
       _canServeAds = canServeAds ?? _defaultCanServeAds,
       _now = now ?? DateTime.now {
    AdsService.instance.status.addListener(_onAdsStatusChanged);
    AdsService.instance.adsEnabled.addListener(_onAdsStatusChanged);
    scheduleMicrotask(_onAdsStatusChanged);
  }

  final AdFormat format;

  /// How long a loaded ad stays valid before being discarded.
  final Duration ttl;

  /// Minimum time between two shows of *this* service. Override to read
  /// from [AdsService.instance.config] so it stays configurable per app.
  Duration get minInterval => Duration.zero;

  /// Shared across every full-screen service so ads never stack.
  static bool isAnyFullScreenAdShowing = false;

  /// Bind this to UI (e.g. enable a button) — true when an ad is ready.
  final ValueNotifier<bool> isAdReady = ValueNotifier<bool>(false);

  T? _ad;
  DateTime? _loadedAt;
  DateTime? _lastShownAt;
  bool _isLoading = false;
  Timer? _retryTimer;
  Timer? _expiryTimer;
  final RetryPolicy _retry = RetryPolicy();
  bool _preloadEnabled;
  bool _disposed = false;
  final bool Function() _canServeAds;
  final DateTime Function() _now;

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
    return _now().difference(_loadedAt!) < ttl;
  }

  /// Enables automatic loading and keeps the next ad warm after a show.
  void startPreloading() {
    if (_disposed || _preloadEnabled) return;
    _preloadEnabled = true;
    _onAdsStatusChanged();
  }

  /// Stops retries and releases any cached ad after demand ends.
  Future<void> stopPreloading() async {
    if (!_preloadEnabled) return;
    _preloadEnabled = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _retry.reset();
    await _discardCachedAd();
  }

  /// Loads an ad if none is cached and none is in flight. Safe to call often.
  Future<void> load() async {
    if (_disposed || !_preloadEnabled || !_canServeAds() || _isLoading) return;
    if (isAdAvailable || adUnitId == null) return;
    await _discardCachedAd();

    _isLoading = true;
    _emit(AdEventType.requested);
    try {
      await loadPlatformAd();
    } catch (error, stackTrace) {
      _handleLoadFailure(error, stackTrace: stackTrace);
    }
  }

  /// Shows the cached ad if available and allowed by frequency caps.
  ///
  /// Returns `true` if the ad was actually shown. When it returns `false`
  /// (not ready / capped), the next ad load is triggered automatically —
  /// callers should simply continue their flow.
  Future<bool> show({
    VoidCallback? onDismissed,
    VoidCallback? onWillShow,
    VoidCallback? onFinished,
  }) async {
    if (_disposed || !_canServeAds() || isAnyFullScreenAdShowing) return false;
    if (!_isIntervalElapsed) return false;
    if (!isAdAvailable) {
      unawaited(load());
      return false;
    }

    final ad = _ad!;
    _ad = null;
    _loadedAt = null;
    isAdReady.value = false;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _pendingOnDismissed = onDismissed;
    _pendingOnFinished = onFinished;
    onWillShow?.call();

    isAnyFullScreenAdShowing = true;
    final result = Completer<bool>();
    _pendingShowResult = result;
    try {
      await showPlatformAd(ad);
    } catch (error, stackTrace) {
      _emit(AdEventType.failedToShow, error: error);
      _completeShowResult(false);
      isAnyFullScreenAdShowing = false;
      try {
        await disposePlatformAd(ad);
      } catch (disposeError, disposeStackTrace) {
        _reportError(
          disposeError,
          disposeStackTrace,
          'while disposing a ${format.name} ad after a show failure',
        );
      }
      _finishShow(callDismissed: false);
      _reportError(error, stackTrace, 'while showing a ${format.name} ad');
    }
    return result.future;
  }

  @mustCallSuper
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    AdsService.instance.status.removeListener(_onAdsStatusChanged);
    AdsService.instance.adsEnabled.removeListener(_onAdsStatusChanged);
    _retryTimer?.cancel();
    _expiryTimer?.cancel();
    unawaited(_discardCachedAd());
    isAdReady.dispose();
  }

  // ------------------------------------------------------------------
  // Shared machinery for subclasses
  // ------------------------------------------------------------------

  VoidCallback? _pendingOnDismissed;
  VoidCallback? _pendingOnFinished;
  Completer<bool>? _pendingShowResult;

  @protected
  void onAdLoaded(T ad) {
    if (_disposed || !_preloadEnabled || !_canServeAds()) {
      _isLoading = false;
      unawaited(disposePlatformAd(ad));
      return;
    }
    _ad = ad;
    _loadedAt = _now();
    _isLoading = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retry.reset();
    isAdReady.value = true;
    _attachPaidEvent(ad);
    _emit(AdEventType.loaded, adapter: _adapterOf(ad));
    _expiryTimer?.cancel();
    _expiryTimer = Timer(ttl, _expireAndReload);
  }

  @protected
  void onAdFailedToLoad(LoadAdError error) {
    _handleLoadFailure(error);
  }

  /// Standard callback wiring shared by all full-screen formats.
  @protected
  FullScreenContentCallback<A> buildFullScreenCallback<A extends Ad>() {
    return FullScreenContentCallback<A>(
      onAdShowedFullScreenContent: (ad) {
        _lastShownAt = _now();
        _completeShowResult(true);
        _emit(AdEventType.shown, adapter: _adapterOf(ad));
      },
      onAdImpression: (ad) =>
          _emit(AdEventType.impression, adapter: _adapterOf(ad)),
      onAdClicked: (ad) => _emit(AdEventType.clicked),
      onAdFailedToShowFullScreenContent: (ad, error) {
        _emit(AdEventType.failedToShow, error: error);
        _completeShowResult(false);
        isAnyFullScreenAdShowing = false;
        unawaited(ad.dispose());
        _finishShow(callDismissed: false);
      },
      onAdDismissedFullScreenContent: (ad) {
        _completeShowResult(true);
        _emit(AdEventType.dismissed);
        isAnyFullScreenAdShowing = false;
        unawaited(ad.dispose());
        _finishShow(callDismissed: true);
      },
    );
  }

  @protected
  void emitReward(RewardItem reward) =>
      _emit(AdEventType.rewardEarned, reward: reward);

  /// Invokes an app callback without allowing it to break ad cleanup.
  @protected
  void invokeSafely(VoidCallback callback, String context) =>
      _invokeCallback(callback, context);

  // ------------------------------------------------------------------
  // Internals
  // ------------------------------------------------------------------

  void _onAdsStatusChanged() {
    if (!_canServeAds()) {
      _retryTimer?.cancel();
      _retryTimer = null;
      _expiryTimer?.cancel();
      _expiryTimer = null;
      unawaited(_discardCachedAd());
      return;
    }
    if (_preloadEnabled) unawaited(load());
  }

  void _finishShow({required bool callDismissed}) {
    final callback = _pendingOnDismissed;
    final finished = _pendingOnFinished;
    _pendingOnDismissed = null;
    _pendingOnFinished = null;
    _pendingShowResult = null;
    if (_preloadEnabled) unawaited(load());
    _invokeCallback(finished, 'while finishing a ${format.name} ad');
    if (callDismissed) {
      _invokeCallback(callback, 'in the ${format.name} dismissal callback');
    }
  }

  bool get _isIntervalElapsed {
    if (_lastShownAt == null || minInterval == Duration.zero) return true;
    return _now().difference(_lastShownAt!) >= minInterval;
  }

  void _handleLoadFailure(Object error, {StackTrace? stackTrace}) {
    if (!_isLoading) return;
    _isLoading = false;
    _emit(AdEventType.failedToLoad, error: error);
    if (_preloadEnabled && _canServeAds() && _retry.canRetry) {
      _retryTimer?.cancel();
      _retryTimer = Timer(_retry.nextDelay(), () => unawaited(load()));
    }
    if (stackTrace != null) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'admob_mediation_flutter',
          context: ErrorDescription('while loading a ${format.name} ad'),
        ),
      );
    }
  }

  void _completeShowResult(bool shown) {
    final result = _pendingShowResult;
    if (result != null && !result.isCompleted) result.complete(shown);
  }

  void _expireAndReload() {
    _expiryTimer = null;
    unawaited(_discardAndReload());
  }

  Future<void> _discardAndReload() async {
    try {
      await _discardCachedAd();
    } catch (error, stackTrace) {
      _reportError(
        error,
        stackTrace,
        'while disposing an expired ${format.name} ad',
      );
    }
    await load();
  }

  void _invokeCallback(VoidCallback? callback, String context) {
    if (callback == null) return;
    try {
      callback();
    } catch (error, stackTrace) {
      _reportError(error, stackTrace, context);
    }
  }

  void _reportError(Object error, StackTrace stackTrace, String context) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'admob_mediation_flutter',
        context: ErrorDescription(context),
      ),
    );
  }

  void _attachPaidEvent(T ad) {
    ad.onPaidEvent =
        (
          Ad paidAd,
          double valueMicros,
          PrecisionType precision,
          String currencyCode,
        ) {
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
    _expiryTimer?.cancel();
    _expiryTimer = null;
    final ad = _ad;
    _ad = null;
    _loadedAt = null;
    if (!_disposed) isAdReady.value = false;
    if (ad != null) await disposePlatformAd(ad);
  }

  static bool _defaultCanServeAds() => AdsService.instance.canServeAds;

  @visibleForTesting
  static void resetGlobalStateForTesting() {
    isAnyFullScreenAdShowing = false;
  }

  String? _adapterOf(Ad ad) => ad.responseInfo?.mediationAdapterClassName;

  void _emit(
    AdEventType type, {
    Object? error,
    RewardItem? reward,
    AdRevenue? revenue,
    String? adapter,
  }) {
    AdEventBus.instance.emit(
      AdEvent(
        format: format,
        type: type,
        error: error,
        reward: reward,
        revenue: revenue,
        mediationAdapter: adapter,
      ),
    );
  }
}
