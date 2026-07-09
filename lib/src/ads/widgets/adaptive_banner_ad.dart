import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads_service.dart';
import '../core/ad_events.dart';

/// Anchored adaptive banner — Google's recommended banner format. It sizes
/// itself to the device width and reserves its final height immediately so
/// content never jumps when the ad arrives.
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
  Orientation? _loadedForOrientation;

  @override
  void initState() {
    super.initState();
    AdsService.instance.status.addListener(_maybeLoad);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.orientationOf(context);
    if (_loadedForOrientation != null && _loadedForOrientation != orientation) {
      // Reload with the size that fits the new orientation.
      _disposeAd();
    }
    _loadedForOrientation = orientation;
    _maybeLoad();
  }

  Future<void> _maybeLoad() async {
    if (!mounted || !AdsService.instance.isReady) return;
    if (_bannerAd != null) return;

    final adUnitId = widget.adUnitId ??
        AdsService.instance.config.adUnitIdFor(AdFormat.banner);
    if (adUnitId == null) return;

    final width = MediaQuery.sizeOf(context).width.truncate();
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (!mounted || size == null) return;

    _emit(AdEventType.requested);
    final banner = BannerAd(
      adUnitId: adUnitId,
      size: size,
      request: widget.collapsible
          ? const AdRequest(extras: {'collapsible': 'bottom'})
          : const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          _emit(AdEventType.loaded,
              adapter: ad.responseInfo?.mediationAdapterClassName);
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _isLoaded = true;
            _loadFailed = false;
          });
        },
        onAdFailedToLoad: (ad, error) {
          _emit(AdEventType.failedToLoad, error: error);
          ad.dispose();
          if (mounted) {
            setState(() {
              _bannerAd = null;
              _isLoaded = false;
              _loadFailed = true;
            });
          }
        },
        onAdImpression: (ad) => _emit(AdEventType.impression),
        onAdClicked: (ad) => _emit(AdEventType.clicked),
      ),
    );

    setState(() {
      _bannerAd = banner;
      _adSize = size;
    });
    await banner.load();
  }

  void _disposeAd() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _isLoaded = false;
  }

  @override
  void dispose() {
    AdsService.instance.status.removeListener(_maybeLoad);
    _disposeAd();
    super.dispose();
  }

  void _emit(AdEventType type,
      {Object? error, AdRevenue? revenue, String? adapter}) {
    AdEventBus.instance.emit(AdEvent(
      format: AdFormat.banner,
      type: type,
      error: error,
      revenue: revenue,
      mediationAdapter: adapter,
    ));
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
