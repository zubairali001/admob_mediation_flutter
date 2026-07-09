import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads_service.dart';
import '../core/ad_events.dart';

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
    this.adUnitId,
    this.template = TemplateType.medium,
  });

  /// Overrides the native ad unit id from the app's `AdsConfig` for this
  /// instance (e.g. an image-only unit for the small template).
  final String? adUnitId;
  final TemplateType template;

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  NativeAd? _nativeAd;
  bool _isLoaded = false;
  bool _loadFailed = false;

  double get _height => widget.template == TemplateType.small ? 120 : 350;

  @override
  void initState() {
    super.initState();
    AdsService.instance.status.addListener(_maybeLoad);
  }

  @override
  void didChangeDependencies() {
    // First load happens here, not in initState: the template style reads
    // Theme.of(context), which is only legal once dependencies are set up.
    super.didChangeDependencies();
    _maybeLoad();
  }

  void _maybeLoad() {
    if (!mounted || !AdsService.instance.isReady || _nativeAd != null) return;
    final adUnitId = widget.adUnitId ??
        AdsService.instance.config.adUnitIdFor(AdFormat.native);
    if (adUnitId == null) return;

    _emit(AdEventType.requested);
    final colorScheme = Theme.of(context).colorScheme;
    _nativeAd = NativeAd(
      adUnitId: adUnitId,
      request: const AdRequest(),
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
          _emit(AdEventType.loaded,
              adapter: ad.responseInfo?.mediationAdapterClassName);
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          _emit(AdEventType.failedToLoad, error: error);
          ad.dispose();
          if (mounted) {
            setState(() {
              _nativeAd = null;
              _isLoaded = false;
              _loadFailed = true;
            });
          }
        },
        onAdImpression: (ad) => _emit(AdEventType.impression),
        onAdClicked: (ad) => _emit(AdEventType.clicked),
      ),
    )..load();
  }

  @override
  void dispose() {
    AdsService.instance.status.removeListener(_maybeLoad);
    _nativeAd?.dispose();
    super.dispose();
  }

  void _emit(AdEventType type, {Object? error, String? adapter}) {
    AdEventBus.instance.emit(AdEvent(
      format: AdFormat.native,
      type: type,
      error: error,
      mediationAdapter: adapter,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loadFailed) return const SizedBox.shrink();

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
