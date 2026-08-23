import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads_service.dart';
import '../core/ad_events.dart';
import '../core/full_screen_ad_service.dart';

/// App open ads. When `AdsConfig.autoShowAppOpenOnResume` is true (default),
/// one shows automatically whenever the app returns to the foreground.
///
/// Set [showOnNextForeground] to `false` around flows that background the
/// app intentionally (payments, sign-in redirects, image picking...) so
/// users aren't greeted with an ad when they come back.
class AppOpenAdService extends FullScreenAdService<AppOpenAd> {
  AppOpenAdService._()
    : super(
        format: AdFormat.appOpen,
        // Per AdMob docs app open ads expire after 4 hours.
        ttl: const Duration(hours: 4),
      );

  static final AppOpenAdService instance = AppOpenAdService._();

  /// Escape hatch for flows that intentionally leave the app.
  bool showOnNextForeground = true;

  bool? _autoShowOverride;

  /// Runtime on/off switch for the automatic show-on-foreground behavior.
  /// Starts from `AdsConfig.autoShowAppOpenOnResume`; setting it overrides
  /// the config for the rest of the session (e.g. disable for premium users
  /// right after a purchase).
  bool get autoShowEnabled =>
      _autoShowOverride ?? AdsService.instance.config.autoShowAppOpenOnResume;
  set autoShowEnabled(bool enabled) => _autoShowOverride = enabled;

  StreamSubscription<AppState>? _appStateSubscription;

  /// Starts watching app lifecycle. Idempotent; wired up automatically by
  /// `AdMobMediation.initialize`.
  void listenToAppForeground() {
    if (_appStateSubscription != null) return;
    AppStateEventNotifier.startListening();
    _appStateSubscription = AppStateEventNotifier.appStateStream.listen((
      AppState state,
    ) {
      if (state == AppState.foreground) _onForeground();
    });
  }

  void _onForeground() {
    if (!autoShowEnabled) return;
    if (!showOnNextForeground) {
      showOnNextForeground = true;
      return;
    }
    // If another full-screen ad triggered the background/foreground cycle
    // (its own overlay), the global flag in the base class blocks stacking.
    show();
  }

  @override
  Future<void> loadPlatformAd() {
    return AppOpenAd.load(
      adUnitId: adUnitId!,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: onAdLoaded,
        onAdFailedToLoad: onAdFailedToLoad,
      ),
    );
  }

  @override
  Future<void> showPlatformAd(AppOpenAd ad) {
    ad.fullScreenContentCallback = buildFullScreenCallback<AppOpenAd>();
    return ad.show();
  }

  @override
  Future<void> disposePlatformAd(AppOpenAd ad) => ad.dispose();

  @override
  void dispose() {
    _appStateSubscription?.cancel();
    _appStateSubscription = null;
    super.dispose();
  }
}
