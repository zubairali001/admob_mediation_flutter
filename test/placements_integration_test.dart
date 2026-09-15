import 'package:admob_mediation_flutter/admob_mediation_flutter.dart';
import 'package:admob_mediation_flutter/src/ads/ads_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart'
    show InitializationStatus;
import 'package:google_mobile_ads/src/ad_instance_manager.dart';
import 'package:google_mobile_ads/src/ump/user_messaging_codec.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  final events = <AdEvent>[];
  final config = AdsConfig(
    useTestAds: false,
    bannerPlacements: {
      for (var i = 0; i < 10; i++)
        'banner_$i': AdUnitId(android: 'banner-id-$i'),
    },
    nativePlacements: const {
      'feed': AdUnitId(android: 'feed-id'),
      'profile': AdUnitId(android: 'profile-id'),
    },
    interstitialPlacements: const {
      'first': AdUnitId(android: 'first-id'),
      'second': AdUnitId(android: 'second-id'),
    },
    rewardedPlacements: const {'coins': AdUnitId(android: 'coins-id')},
    rewardedInterstitialPlacements: const {
      'bonus': AdUnitId(android: 'bonus-id'),
    },
    appOpenPlacements: const {'splash': AdUnitId(android: 'splash-id')},
  );

  setUpAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      MethodChannel(
        'plugins.flutter.io/google_mobile_ads/ump',
        StandardMethodCodec(UserMessagingCodec()),
      ),
      (call) async =>
          call.method == 'ConsentInformation#canRequestAds' ? true : null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      instanceManager.channel,
      (call) async {
        calls.add(call);
        if (call.method == 'MobileAds#initialize') {
          return InitializationStatus({});
        }
        if (call.method == 'AdSize#getLargeAnchoredAdaptiveBannerAdSize') {
          return 50;
        }
        return null;
      },
    );
    await AdsService.instance.initialize(config: config);
    expect(AdsService.instance.isReady, isTrue);
  });

  setUp(() {
    calls.clear();
    events.clear();
    AdsService.instance.setAdsEnabled(true);
  });
  tearDown(() {
    AdsService.instance.setAdsEnabled(false);
  });

  Future<void> emitLoaded(
    MethodCall call, {
    String eventName = 'onAdLoaded',
    Map<String, Object> extras = const {},
  }) async {
    final channel = instanceManager.channel;
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        MethodCall('onAdEvent', {
          'adId': call.arguments['adId'],
          'eventName': eventName,
          ...extras,
        }),
      ),
      (_) {},
    );
  }

  testWidgets('ten simultaneous banners request the ten selected IDs', (
    tester,
  ) async {
    final subscription = AdMobMediation.events.listen(events.add);
    addTearDown(subscription.cancel);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (var i = 0; i < 10; i++)
                AdaptiveBannerAd(placement: 'banner_$i'),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final loads = calls.where((call) => call.method == 'loadBannerAd').toList();
    expect(loads, hasLength(10));
    expect(
      loads.map((call) => call.arguments['adUnitId']),
      unorderedEquals(List.generate(10, (i) => 'banner-id-$i')),
    );
    expect(
      events
          .where((event) => event.type == AdEventType.requested)
          .map((event) => event.placement),
      unorderedEquals(List.generate(10, (i) => 'banner_$i')),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(calls.where((call) => call.method == 'disposeAd'), hasLength(10));
  });

  testWidgets('changing a banner placement disposes only its previous ad', (
    tester,
  ) async {
    Widget screen(String placement) => MaterialApp(
      home: Scaffold(
        bottomNavigationBar: AdaptiveBannerAd(placement: placement),
      ),
    );
    await tester.pumpWidget(screen('banner_0'));
    await tester.pump();
    final first = calls.singleWhere((call) => call.method == 'loadBannerAd');
    await tester.pumpWidget(screen('banner_1'));
    await tester.pump();
    final loads = calls.where((call) => call.method == 'loadBannerAd').toList();
    expect(loads.map((call) => call.arguments['adUnitId']), [
      'banner-id-0',
      'banner-id-1',
    ]);
    expect(
      calls.singleWhere((call) => call.method == 'disposeAd').arguments['adId'],
      first.arguments['adId'],
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('native placement changes reload; disabled widgets collapse', (
    tester,
  ) async {
    Widget screen(String placement) => MaterialApp(
      home: Scaffold(body: NativeAdCard(placement: placement)),
    );
    await tester.pumpWidget(screen('feed'));
    await tester.pump();
    expect(find.text('Ad'), findsOneWidget);
    await tester.pumpWidget(screen('profile'));
    await tester.pump();
    expect(
      calls
          .where((call) => call.method == 'loadNativeAd')
          .map((call) => call.arguments['adUnitId']),
      ['feed-id', 'profile-id'],
    );
    AdsService.instance.setAdsEnabled(false);
    await tester.pump();
    expect(find.text('Ad'), findsNothing);
    expect(calls.where((call) => call.method == 'disposeAd'), hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'full-screen registry isolates readiness and starts only requested placements',
    (tester) async {
      final subscription = AdMobMediation.events.listen(events.add);
      addTearDown(subscription.cancel);
      expect(calls.where((call) => call.method.startsWith('load')), isEmpty);
      final first = AdMobMediation.isAdReady(
        AdFormat.interstitial,
        placement: 'first',
      );
      await tester.pump();
      var loads = calls
          .where((call) => call.method == 'loadInterstitialAd')
          .toList();
      expect(loads, hasLength(1));
      expect(loads.single.arguments['adUnitId'], 'first-id');
      final second = AdMobMediation.isAdReady(
        AdFormat.interstitial,
        placement: 'second',
      );
      await tester.pump();
      loads = calls
          .where((call) => call.method == 'loadInterstitialAd')
          .toList();
      expect(loads, hasLength(2));
      await emitLoaded(loads.first);
      await tester.pump();
      expect(first.value, isTrue);
      expect(second.value, isFalse);
      final loaded = events.singleWhere(
        (event) => event.type == AdEventType.loaded,
      );
      expect(loaded.placement, 'first');
      expect(loaded.adUnitId, 'first-id');
      await AdMobMediation.stopPreloading(
        AdFormat.interstitial,
        placement: 'first',
      );
      expect(first.value, isFalse);
      expect(
        identical(
          first,
          AdMobMediation.isAdReady(AdFormat.interstitial, placement: 'first'),
        ),
        isTrue,
      );
      await tester.pump();
      expect(
        calls.where((call) => call.method == 'loadInterstitialAd'),
        hasLength(3),
      );
      await AdMobMediation.stopPreloading(
        AdFormat.interstitial,
        placement: 'first',
      );
      await AdMobMediation.stopPreloading(
        AdFormat.interstitial,
        placement: 'second',
      );
    },
  );

  testWidgets('all remaining full-screen load APIs select their named unit', (
    tester,
  ) async {
    AdMobMediation.loadRewarded(placement: 'coins');
    AdMobMediation.loadRewardedInterstitial(placement: 'bonus');
    AdMobMediation.loadAppOpen(placement: 'splash');
    await tester.pump();
    expect(
      calls
          .where((call) => call.method.startsWith('load'))
          .map((call) => call.arguments['adUnitId']),
      unorderedEquals(['coins-id', 'bonus-id', 'splash-id']),
    );
    final rewardLoad = calls.singleWhere(
      (call) => call.method == 'loadRewardedAd',
    );
    await emitLoaded(rewardLoad);
    var earned = 0;
    final shown = AdMobMediation.showRewarded(
      placement: 'coins',
      onReward: (reward) => earned += reward.amount.toInt(),
    );
    await tester.pump();
    expect(
      calls
          .singleWhere((call) => call.method == 'showAdWithoutView')
          .arguments['adId'],
      rewardLoad.arguments['adId'],
    );
    await emitLoaded(rewardLoad, eventName: 'onAdShowedFullScreenContent');
    expect(await shown, isTrue);
    for (var i = 0; i < 2; i++) {
      await emitLoaded(
        rewardLoad,
        eventName: 'onRewardedAdUserEarnedReward',
        extras: {'rewardItem': RewardItem(10, 'coins')},
      );
    }
    expect(earned, 10);
    await emitLoaded(rewardLoad, eventName: 'onAdDismissedFullScreenContent');
    await AdMobMediation.stopPreloading(AdFormat.rewarded, placement: 'coins');
    await AdMobMediation.stopPreloading(
      AdFormat.rewardedInterstitial,
      placement: 'bonus',
    );
    await AdMobMediation.stopPreloading(AdFormat.appOpen, placement: 'splash');
  });

  test('unknown full-screen placement throws before any request', () {
    expect(
      () => AdMobMediation.loadInterstitial(placement: 'typo'),
      throwsArgumentError,
    );
    expect(
      () => AdMobMediation.isAdReady(AdFormat.banner),
      throwsArgumentError,
    );
    expect(calls.where((call) => call.method.startsWith('load')), isEmpty);
  });
}
