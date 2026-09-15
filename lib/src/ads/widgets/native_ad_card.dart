import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads_service.dart';
import '../core/ad_events.dart';
import '../core/retry_policy.dart';

/// Native ad rendered with Google's built-in templates — no platform-side
/// factory code needed. Use [TemplateType.small] inside lists and
/// [TemplateType.medium] for feed cards.
///
/// Note on video: the small template's media area is below the 120x120dp
/// minimum Google requires for video creatives (the debug-only "native ad
/// validator" overlay warns about this). Either serve the small template
/// from an ad unit with the Video media type disabled in the AdMob
/// dashboard, or use [TemplateType.medium] for video-eligible units.
class NativeAdCard extends StatefulWidget {
  const NativeAdCard({
    super.key,
    this.placement,
    this.adUnitId,
    this.template = TemplateType.medium,
  }) : assert(
         placement == null || adUnitId == null,
         'Specify either placement or adUnitId, not both.',
       );

  /// Overrides the native ad unit id from the app's `AdsConfig` for this
  /// instance (e.g. an image-only unit for the small template).
  final String? adUnitId;

  /// Key in the matching AdsConfig placement map. Omit to use the default ID.
  /// Cannot be combined with [adUnitId]. Both paths respect test-ad mode.
  final String? placement;
  final TemplateType template;

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard>
    with AutomaticKeepAliveClientMixin {
  NativeAd? _nativeAd;
  bool _isLoaded = false;
  bool _loadFailed = false;
  bool _isLoading = false;
  Timer? _retryTimer;
  final RetryPolicy _retry = RetryPolicy();
  int _loadGeneration = 0;
  final Expando<bool> _disposedAds = Expando<bool>();

  double get _height => widget.template == TemplateType.small ? 120 : 350;

  @override
  void initState() {
    super.initState();
    AdsService.instance.status.addListener(_onAvailabilityChanged);
    AdsService.instance.adsEnabled.addListener(_onAvailabilityChanged);
  }

  @override
  void didChangeDependencies() {
    // First load happens here, not in initState: the template style reads
    // Theme.of(context), which is only legal once dependencies are set up.
    super.didChangeDependencies();
    _maybeLoad();
  }

  void _maybeLoad() {
    if (!mounted || !AdsService.instance.canServeAds) return;
    if (_nativeAd != null || _isLoading) return;
    final adUnitId = AdsService.instance.config.adUnitIdFor(
      AdFormat.native,
      placement: widget.placement,
      adUnitId: widget.adUnitId,
    );
    if (adUnitId == null) return;

    _isLoading = true;
    final generation = ++_loadGeneration;
    _emit(AdEventType.requested);
    final colorScheme = Theme.of(context).colorScheme;
    _nativeAd = NativeAd(
      adUnitId: adUnitId,
      request: AdsService.instance.config.requestFor(AdFormat.native),
      nativeAdOptions: NativeAdOptions(
        // Videos start muted — required UX courtesy, and networks reward it.
        videoOptions: VideoOptions(startMuted: true),
        // Landscape media keeps template heights predictable.
        mediaAspectRatio: MediaAspectRatio.landscape,
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: widget.template,
        mainBackgroundColor: colorScheme.surface,
        cornerRadius: 12,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: colorScheme.onPrimary,
          backgroundColor: colorScheme.primary,
          style: NativeTemplateFontStyle.bold,
          size: 15,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: colorScheme.onSurface,
          style: NativeTemplateFontStyle.bold,
          size: 15,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: colorScheme.onSurfaceVariant,
          size: 13,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: colorScheme.onSurfaceVariant,
          size: 12,
        ),
      ),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!_isCurrentAd(ad, generation)) {
            _disposeOnce(ad);
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
          _disposeOnce(ad);
          if (!_isCurrentAd(ad, generation)) return;
          _emit(AdEventType.failedToLoad, error: error);
          _nativeAd = null;
          _isLoading = false;
          setState(() {
            _isLoaded = false;
            _loadFailed = true;
          });
          _scheduleRetry();
        },
        onAdImpression: (ad) {
          if (_isCurrentAd(ad, generation)) _emit(AdEventType.impression);
        },
        onAdClicked: (ad) {
          if (_isCurrentAd(ad, generation)) _emit(AdEventType.clicked);
        },
        onPaidEvent: (ad, valueMicros, precision, currencyCode) {
          if (!_isCurrentAd(ad, generation)) return;
          _emit(
            AdEventType.paid,
            adapter: ad.responseInfo?.mediationAdapterClassName,
            revenue: AdRevenue(
              valueMicros: valueMicros,
              currencyCode: currencyCode,
              precision: precision,
            ),
          );
        },
      ),
    );
    unawaited(
      _nativeAd!.load().catchError((Object error) {
        _handleLoadFailure(error, generation);
      }),
    );
  }

  void _onAvailabilityChanged() {
    if (!AdsService.instance.canServeAds) {
      _disposeAd();
      if (mounted) setState(() => _loadFailed = false);
      return;
    }
    _maybeLoad();
  }

  void _disposeOnce(Ad ad) {
    if (_disposedAds[ad] == true) return;
    _disposedAds[ad] = true;
    unawaited(ad.dispose());
  }

  void _disposeAd() {
    _loadGeneration++;
    _retryTimer?.cancel();
    _retryTimer = null;
    final ad = _nativeAd;
    _nativeAd = null;
    _isLoaded = false;
    _isLoading = false;
    if (ad != null) {
      _disposeOnce(ad);
    }
  }

  void _handleLoadFailure(Object error, int generation) {
    if (!_isCurrentLoad(generation)) return;
    final ad = _nativeAd;
    _nativeAd = null;
    _isLoading = false;
    if (ad != null) _disposeOnce(ad);
    _emit(AdEventType.failedToLoad, error: error);
    if (mounted) setState(() => _loadFailed = true);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!mounted || !AdsService.instance.canServeAds || !_retry.canRetry) {
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = Timer(_retry.nextDelay(), _maybeLoad);
  }

  bool _isCurrentLoad(int generation) =>
      mounted &&
      AdsService.instance.canServeAds &&
      generation == _loadGeneration;

  bool _isCurrentAd(Ad ad, int generation) =>
      _isCurrentLoad(generation) && identical(ad, _nativeAd);

  @override
  void didUpdateWidget(covariant NativeAdCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.placement != widget.placement ||
        oldWidget.adUnitId != widget.adUnitId ||
        oldWidget.template != widget.template) {
      _disposeAd();
      _retry.reset();
      _maybeLoad();
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
    String? adapter,
    AdRevenue? revenue,
  }) {
    AdEventBus.instance.emit(
      AdEvent(
        format: AdFormat.native,
        type: type,
        placement: widget.placement,
        adUnitId: AdsService.instance.config.adUnitIdFor(
          AdFormat.native,
          placement: widget.placement,
          adUnitId: widget.adUnitId,
        ),
        error: error,
        mediationAdapter: adapter,
        revenue: revenue,
      ),
    );
  }

  // Home's girl grid is an unbounded, index-cycling list: any card scrolled
  // past the sliver's cache extent is destroyed outright, not just hidden.
  // Without keep-alive, every scroll-away-and-back threw the in-flight or
  // already-loaded ad out and started a brand new load from zero — so a
  // native ad that takes any real time to load almost never survived long
  // enough for a user to actually see it, which is why the slot only ever
  // showed the "Ad" placeholder.
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    if (_loadFailed ||
        !AdsService.instance.canServeAds ||
        AdsService.instance.config.adUnitIdFor(
              AdFormat.native,
              placement: widget.placement,
              adUnitId: widget.adUnitId,
            ) ==
            null) {
      return const SizedBox.shrink();
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: 320,
        maxWidth: 400,
        minHeight: _height,
        maxHeight: _height,
      ),
      child: _isLoaded && _nativeAd != null
          ? AdWidget(ad: _nativeAd!)
          : _LoadingPlaceholder(height: _height),
    );
  }
}

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        'Ad',
        style: TextStyle(color: Theme.of(context).colorScheme.outline),
      ),
    );
  }
}
