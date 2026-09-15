import 'package:admob_mediation_flutter/admob_mediation_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('unconfigured formats stay disabled when test ads are enabled', () {
    const config = AdsConfig(useTestAds: true);

    expect(config.adUnitIdFor(AdFormat.interstitial), isNull);
  });

  test('configured formats use Google test ids in debug mode', () {
    const config = AdsConfig(
      useTestAds: true,
      interstitial: AdUnitId(android: 'production-id'),
    );

    expect(
      config.adUnitIdFor(AdFormat.interstitial),
      'ca-app-pub-3940256099942544/1033173712',
    );
  });

  test('production ids resolve for the active platform', () {
    const config = AdsConfig(
      useTestAds: false,
      rewarded: AdUnitId(android: 'android-id', ios: 'ios-id'),
    );

    expect(config.adUnitIdFor(AdFormat.rewarded), 'android-id');

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(config.adUnitIdFor(AdFormat.rewarded), 'ios-id');
  });

  test('ten banner placements resolve independently on both platforms', () {
    final config = AdsConfig(
      useTestAds: false,
      banner: const AdUnitId(android: 'default'),
      bannerPlacements: {
        for (var i = 0; i < 10; i++)
          'screen_$i': AdUnitId(android: 'android_$i', ios: 'ios_$i'),
      },
    );
    expect(config.adUnitIdFor(AdFormat.banner), 'default');
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      debugDefaultTargetPlatformOverride = platform;
      for (var i = 0; i < 10; i++) {
        expect(
          config.adUnitIdFor(AdFormat.banner, placement: 'screen_$i'),
          '${platform == TargetPlatform.android ? 'android' : 'ios'}_$i',
        );
      }
    }
  });

  test('placement names are scoped by format', () {
    const unit = AdUnitId(android: 'unit');
    const config = AdsConfig(
      useTestAds: false,
      appOpenPlacements: {'home': unit},
      bannerPlacements: {'home': unit},
      interstitialPlacements: {'home': unit},
      rewardedPlacements: {'home': unit},
      rewardedInterstitialPlacements: {'home': unit},
      nativePlacements: {'home': unit},
    );
    for (final format in AdFormat.values) {
      expect(config.adUnitIdFor(format, placement: 'home'), 'unit');
      expect(config.adUnitIdFor(format), isNull);
    }
  });

  test('unknown or blank placements never use the default ID', () {
    const config = AdsConfig(banner: AdUnitId(android: 'default'));
    for (final placement in ['unknown', '', ' ']) {
      expect(
        () => config.adUnitIdFor(AdFormat.banner, placement: placement),
        throwsArgumentError,
      );
    }
  });

  test('missing platform and blank IDs stay disabled even in test mode', () {
    const config = AdsConfig(
      useTestAds: true,
      banner: AdUnitId(android: 'default'),
      bannerPlacements: {
        'ios_only': AdUnitId(ios: 'ios'),
        'empty': AdUnitId(android: '  '),
      },
    );
    expect(config.adUnitIdFor(AdFormat.banner, placement: 'ios_only'), isNull);
    expect(config.adUnitIdFor(AdFormat.banner, placement: 'empty'), isNull);
    expect(config.adUnitIdFor(AdFormat.banner, adUnitId: ''), isNull);
  });

  test('test mode also replaces named placements and raw widget overrides', () {
    const config = AdsConfig(
      useTestAds: true,
      bannerPlacements: {'home': AdUnitId(android: 'production')},
    );
    const testId = 'ca-app-pub-3940256099942544/9214589741';
    expect(config.adUnitIdFor(AdFormat.banner, placement: 'home'), testId);
    expect(config.adUnitIdFor(AdFormat.banner, adUnitId: 'production'), testId);
    expect(
      () => config.adUnitIdFor(
        AdFormat.banner,
        placement: 'home',
        adUnitId: 'override',
      ),
      throwsArgumentError,
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(config.adUnitIdFor(AdFormat.banner, adUnitId: 'production'), isNull);
  });

  test('initialization snapshot isolates caller-owned placement maps', () {
    final units = {'home': const AdUnitId(android: 'original')};
    final config = AdsConfig(
      useTestAds: false,
      bannerPlacements: units,
    ).snapshot();
    units['home'] = const AdUnitId(android: 'changed');
    expect(config.adUnitIdFor(AdFormat.banner, placement: 'home'), 'original');
    expect(() => config.bannerPlacements.clear(), throwsUnsupportedError);
    expect(
      () => const AdsConfig(
        bannerPlacements: {' home ': AdUnitId(android: 'id')},
      ).snapshot(),
      throwsArgumentError,
    );
  });

  test('requestFor preserves targeting and merges format extras', () {
    const config = AdsConfig(
      adRequest: AdRequest(
        keywords: <String>['game'],
        nonPersonalizedAds: true,
        extras: <String, String>{'rdp': '1'},
      ),
    );

    final request = config.requestFor(
      AdFormat.banner,
      extras: const <String, String>{'collapsible': 'bottom'},
    );

    expect(request.keywords, <String>['game']);
    expect(request.nonPersonalizedAds, isTrue);
    expect(request.extras, <String, String>{
      'rdp': '1',
      'collapsible': 'bottom',
    });
  });
}
