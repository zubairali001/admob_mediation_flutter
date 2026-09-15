import 'package:admob_mediation_flutter/src/ads/ads_service.dart';
import 'package:admob_mediation_flutter/src/ads/core/ad_events.dart';
import 'package:admob_mediation_flutter/src/ads/core/full_screen_ad_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

void main() {
  setUp(FullScreenAdService.resetGlobalStateForTesting);

  test('loads and confirms a successful show', () async {
    final service = _FakeFullScreenService();
    addTearDown(service.dispose);

    service.startPreloading();
    await _flushAsyncWork();

    expect(service.isAdAvailable, isTrue);
    expect(service.isAdReady.value, isTrue);
    expect(await service.show(), isTrue);
    expect(FullScreenAdService.isAnyFullScreenAdShowing, isTrue);

    service.dismiss();
    expect(FullScreenAdService.isAnyFullScreenAdShowing, isFalse);
  });

  test(
    'a second show cannot replace callbacks while an ad is visible',
    () async {
      final service = _FakeFullScreenService();
      addTearDown(service.dispose);
      service.startPreloading();
      await _flushAsyncWork();

      var firstDismissed = 0;
      var secondDismissed = 0;
      expect(await service.show(onDismissed: () => firstDismissed++), isTrue);
      expect(await service.show(onDismissed: () => secondDismissed++), isFalse);

      service.dismiss();
      expect(firstDismissed, 1);
      expect(secondDismissed, 0);
    },
  );

  test('show exceptions release the global lock and report failure', () async {
    final service = _FakeFullScreenService()..throwOnShow = true;
    addTearDown(service.dispose);
    service.startPreloading();
    await _flushAsyncWork();

    final previousHandler = FlutterError.onError;
    FlutterError.onError = (_) {};
    addTearDown(() => FlutterError.onError = previousHandler);

    expect(await service.show(), isFalse);
    expect(FullScreenAdService.isAnyFullScreenAdShowing, isFalse);
  });

  test('load exceptions do not leave the service stuck loading', () async {
    final service = _FakeFullScreenService()..throwOnLoad = true;
    addTearDown(service.dispose);
    final previousHandler = FlutterError.onError;
    FlutterError.onError = (_) {};
    addTearDown(() => FlutterError.onError = previousHandler);

    service.startPreloading();
    await _flushAsyncWork();
    service.throwOnLoad = false;
    await service.load();

    expect(service.isAdAvailable, isTrue);
  });

  test('concurrent loads and startup microtask request only one ad', () async {
    final service = _FakeFullScreenService()..deferLoad = true;
    addTearDown(service.dispose);
    service.startPreloading();
    await Future.wait(List.generate(10, (_) => service.load()));
    await _flushAsyncWork();
    expect(service.loadCount, 1);
    service.completeLoad();
    expect(service.isAdAvailable, isTrue);
  });

  test(
    'stopped and restarted loads ignore stale success and failure',
    () async {
      final service = _FakeFullScreenService()..deferLoad = true;
      addTearDown(service.dispose);
      service.startPreloading();
      await _flushAsyncWork();
      final oldGeneration = service.generations.single;
      await service.stopPreloading();
      service.startPreloading();
      await _flushAsyncWork();
      final staleAd = _FakeAd();
      service.deliverLoaded(staleAd, oldGeneration);
      service.deliverFailure(
        LoadAdError(3, 'test', 'no fill', null),
        oldGeneration,
      );
      expect(staleAd.disposed, isTrue);
      expect(service.isAdReady.value, isFalse);
      await service.load();
      expect(service.loadCount, 2);
      service.completeLoad();
      expect(service.isAdReady.value, isTrue);
    },
  );

  test('disable then enable cannot accept a previous request', () async {
    final service = _FakeFullScreenService(
      canServeAds: () => AdsService.instance.adsEnabled.value,
    )..deferLoad = true;
    addTearDown(service.dispose);
    service.startPreloading();
    await _flushAsyncWork();
    final oldGeneration = service.generations.single;
    AdsService.instance.setAdsEnabled(false);
    AdsService.instance.setAdsEnabled(true);
    await _flushAsyncWork();
    final staleAd = _FakeAd();
    service.deliverLoaded(staleAd, oldGeneration);
    expect(staleAd.disposed, isTrue);
    expect(service.isAdReady.value, isFalse);
    service.completeLoad();
    expect(service.isAdReady.value, isTrue);
  });

  test(
    'placements have separate caches and share the format cooldown',
    () async {
      final first = _FakeFullScreenService(
        placement: 'first',
        interval: const Duration(minutes: 1),
      );
      final second = _FakeFullScreenService(
        placement: 'second',
        interval: const Duration(minutes: 1),
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      first.startPreloading();
      second.startPreloading();
      await _flushAsyncWork();
      expect(first.loadCount, 1);
      expect(second.loadCount, 1);
      expect(await first.show(), isTrue);
      expect(await second.show(), isFalse);
      first.dismiss();
      expect(second.isAdReady.value, isTrue);
      expect(await second.show(), isFalse);
    },
  );

  test('load completing after disposal releases its ad', () async {
    final service = _FakeFullScreenService()..deferLoad = true;
    service.startPreloading();
    await _flushAsyncWork();
    service.dispose();
    final ad = _FakeAd();
    service.deliverLoaded(ad, service.generations.single);
    expect(ad.disposed, isTrue);
  });

  test('disabled services neither load nor show', () async {
    var enabled = false;
    final service = _FakeFullScreenService(canServeAds: () => enabled);
    addTearDown(service.dispose);

    service.startPreloading();
    await _flushAsyncWork();
    expect(service.loadCount, 0);
    expect(await service.show(), isFalse);

    enabled = true;
    await service.load();
    expect(service.loadCount, 1);
  });
}

Future<void> _flushAsyncWork() => Future<void>.delayed(Duration.zero);

final class _FakeAd extends AdWithoutView {
  _FakeAd() : super(adUnitId: 'test-ad-unit');

  var disposed = false;

  @override
  Future<void> dispose() async => disposed = true;
}

final class _FakeFullScreenService extends FullScreenAdService<_FakeAd> {
  _FakeFullScreenService({
    bool Function()? canServeAds,
    super.placement,
    this.interval = Duration.zero,
  }) : super(
         format: AdFormat.interstitial,
         autoPreload: false,
         canServeAds: canServeAds ?? _alwaysEnabled,
       );

  final Duration interval;
  @override
  Duration get minInterval => interval;
  bool deferLoad = false;
  final List<int> generations = [];
  void deliverLoaded(_FakeAd ad, int generation) => onAdLoaded(ad, generation);
  void deliverFailure(LoadAdError error, int generation) =>
      onAdFailedToLoad(error, generation);
  void completeLoad() => onAdLoaded(_FakeAd(), generations.last);

  bool throwOnLoad = false;
  bool throwOnShow = false;
  int loadCount = 0;
  FullScreenContentCallback<_FakeAd>? callback;

  @override
  String get adUnitId => 'test-ad-unit';

  @override
  Future<void> loadPlatformAd(int generation) async {
    loadCount++;
    generations.add(generation);
    if (throwOnLoad) throw StateError('load failed');
    if (!deferLoad) onAdLoaded(_FakeAd(), generation);
  }

  @override
  Future<void> showPlatformAd(_FakeAd ad) async {
    if (throwOnShow) throw StateError('show failed');
    callback = buildFullScreenCallback<_FakeAd>();
    callback!.onAdShowedFullScreenContent?.call(ad);
  }

  void dismiss() {
    final ad = _FakeAd();
    callback!.onAdDismissedFullScreenContent?.call(ad);
  }

  @override
  Future<void> disposePlatformAd(_FakeAd ad) => ad.dispose();
}

bool _alwaysEnabled() => true;
