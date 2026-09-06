import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads_service.dart';
import '../core/ad_events.dart';
import '../core/retry_policy.dart';

/// Anchored adaptive banner — Google's recommended banner format. It sizes
/// itself to the device width and reserves the resolved height while loading.
///
/// Drop it at the bottom of a screen:
/// ```dart
/// bottomNavigationBar: const AdaptiveBannerAd(),
/// ```
///
/// Set [collapsible] to make it a collapsible banner (larger initial overlay
/// that collapses to a normal banner — must also be enabled per policy).
///
/// The ad unit id comes from the app's `AdsConfig`; pass [adUnitId] to
/// override it for this instance (e.g. a second banner placement).
class AdaptiveBannerAd extends StatefulWidget {
  const AdaptiveBannerAd({super.key, this.adUnitId, this.collapsible = false});

  final String? adUnitId;
  final bool collapsible;

  @override
  State<AdaptiveBannerAd> createState() => _AdaptiveBannerAdState();
}

class _AdaptiveBannerAdState extends State<AdaptiveBannerAd> {
  BannerAd? _bannerAd;
  AdSize? _adSize;
  bool _isLoaded = false;
  bool _loadFailed = false;
  bool _isLoading = false;
  Orientation? _loadedForOrientation;
  Timer? _retryTimer;
  final RetryPolicy _retry = RetryPolicy();
  int _loadGeneration = 0;
  final Set<Ad> _disposedAds = {};  // prevent double-dispose on race

  @override
  void initState() {
    super.initState();
    AdsService.instance.status.addListener(_onAvailabilityChanged);
    AdsService.instance.adsEnabled.addListener(_onAvailabilityChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.orientationOf(context);
    if (_loadedForOrientation != null && _loadedForOrientation != orientation) {
      _disposeAd();
    }
    _loadedForOrientation = orientation;
    _maybeLoad();
  }

  Future<void> _maybeLoad() async {
    if (!mounted || !AdsService.instance.canServeAds) return;
    if (_bannerAd != null || _isLoading) return;

    final adUnitId =
        widget.adUnitId ??
        AdsService.instance.config.adUnitIdFor(AdFormat.banner);
    if (adUnitId == null) return;

    _isLoading = true;
    final generation = ++_loadGeneration;
    final width = MediaQuery.sizeOf(context).width.truncate();
    AdSize? size;
    try {
      size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    } catch (error) {
      _handleLoadFailure(error, generation);
      return;
    }
    if (!_isCurrentLoad(generation)) {
      if (generation == _loadGeneration) _isLoading = false;
      return;
    }
    if (size == null) {
      _handleLoadFailure(
        StateError('Unable to resolve an adaptive banner size.'),
        generation,
      );
      return;
    }

    _emit(AdEventType.requested);
    final banner = BannerAd(
      adUnitId: adUnitId,
      size: size,
      request: AdsService.instance.config.requestFor(
        AdFormat.banner,
        extras: widget.collapsible
            ? const <String, String>{'collapsible': 'bottom'}
            : null,
      ),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!_isCurrentAd(ad, generation)) {
            if (_disposedAds.remove(ad)) return;  // already disposed
            unawaited(ad.dispose());
            return;
          }
          _emit(
            AdEventType.loaded,
            adapter: ad.responseInfo?.mediationAdapterClassName,
          );
          _isLoading = false;
          _retry.reset();
          setState(() {
            _isLoaded = true;
            _loadFailed = false;
          });
        },
        onAdFailedToLoad: (ad, error) {
          if (!_disposedAds.remove(ad)) unawaited(ad.dispose());
          if (!_isCurrentAd(ad, generation)) return;
          _emit(AdEventType.failedToLoad, error: error);
          _bannerAd = null;
          _isLoading = false;
          setState(() {
            _isLoaded = false;
            _loadFailed = true;
          });
          _scheduleRetry();
        },
        onAdImpression: (ad) => _emit(AdEventType.impression),
        onAdClicked: (ad) => _emit(AdEventType.clicked),
        onPaidEvent: (ad, valueMicros, precision, currencyCode) => _emit(
          AdEventType.paid,
          adapter: ad.responseInfo?.mediationAdapterClassName,
          revenue: AdRevenue(
            valueMicros: valueMicros,
            currencyCode: currencyCode,
            precision: precision,
          ),
        ),
      ),
    );

    if (!_isCurrentLoad(generation)) {
      unawaited(banner.dispose());
      return;
    }
    setState(() {
      _bannerAd = banner;
      _adSize = size;
    });
    try {
      await banner.load();
    } catch (error) {
      _handleLoadFailure(error, generation, ad: banner);
    }
  }

  void _disposeAd() {
    _loadGeneration++;
    _retryTimer?.cancel();
    _retryTimer = null;
    final ad = _bannerAd;
    _bannerAd = null;
    _adSize = null;
    _isLoaded = false;
    _isLoading = false;
    if (ad != null) {
      _disposedAds.add(ad);
      unawaited(ad.dispose());
    }
  }

  void _onAvailabilityChanged() {
    if (!AdsService.instance.canServeAds) {
      _disposeAd();
      if (mounted) setState(() => _loadFailed = false);
      return;
    }
    unawaited(_maybeLoad());
  }

  void _handleLoadFailure(Object error, int generation, {BannerAd? ad}) {
    if (ad != null) unawaited(ad.dispose());
    if (!_isCurrentLoad(generation)) return;
    _emit(AdEventType.failedToLoad, error: error);
    _bannerAd = null;
    _isLoading = false;
    if (mounted) setState(() => _loadFailed = true);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!mounted || !AdsService.instance.canServeAds || !_retry.canRetry) {
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = Timer(_retry.nextDelay(), () => unawaited(_maybeLoad()));
  }

  bool _isCurrentLoad(int generation) =>
      mounted &&
      AdsService.instance.canServeAds &&
      generation == _loadGeneration;

  bool _isCurrentAd(Ad ad, int generation) =>
      _isCurrentLoad(generation) && identical(ad, _bannerAd);

  @override
  void didUpdateWidget(covariant AdaptiveBannerAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adUnitId != widget.adUnitId ||
        oldWidget.collapsible != widget.collapsible) {
      _disposeAd();
      _retry.reset();
      unawaited(_maybeLoad());
    }
  }

  @override
  void dispose() {
    AdsService.instance.status.removeListener(_onAvailabilityChanged);
    AdsService.instance.adsEnabled.removeListener(_onAvailabilityChanged);
    _disposeAd();
    super.dispose();
  }

  void _emit(
    AdEventType type, {
    Object? error,
    AdRevenue? revenue,
    String? adapter,
  }) {
    AdEventBus.instance.emit(
      AdEvent(
        format: AdFormat.banner,
        type: type,
        error: error,
        revenue: revenue,
        mediationAdapter: adapter,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Collapse entirely on failure so the UI reclaims the space.
    if (_loadFailed || _adSize == null || _bannerAd == null) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      top: false,
      child: SizedBox(
        width: _adSize!.width.toDouble(),
        height: _adSize!.height.toDouble(),
        child: _isLoaded ? AdWidget(ad: _bannerAd!) : const SizedBox.shrink(),
      ),
    );
  }
}
