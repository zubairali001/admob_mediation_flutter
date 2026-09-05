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
