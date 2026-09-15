import 'package:admob_mediation_flutter/admob_mediation_flutter.dart';
import 'package:admob_mediation_flutter/src/ads/ads_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    AdsService.instance.status.value = AdsStatus.ready;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      instanceManager.channel,
      (call) async {
        calls.add(call);
        if (call.method == 'AdSize#getLargeAnchoredAdaptiveBannerAdSize') {
          return 50;
        }
        return null;
      },
    );
  });
  tearDown(() => AdsService.instance.status.value = AdsStatus.idle);

  testWidgets('raw banner and native IDs cannot bypass default test mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AdaptiveBannerAd(adUnitId: 'production-banner'),
          body: NativeAdCard(adUnitId: 'production-native'),
        ),
      ),
    );
    await tester.pump();
    expect(
      calls
          .singleWhere((call) => call.method == 'loadBannerAd')
          .arguments['adUnitId'],
      'ca-app-pub-3940256099942544/9214589741',
    );
    expect(
      calls
          .singleWhere((call) => call.method == 'loadNativeAd')
          .arguments['adUnitId'],
      'ca-app-pub-3940256099942544/2247696110',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('unconfigured native widget occupies no ad space', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: NativeAdCard())),
    );
    expect(find.text('Ad'), findsNothing);
    expect(calls.where((call) => call.method.startsWith('load')), isEmpty);
    expect(tester.getSize(find.byType(NativeAdCard)), Size.zero);
  });
}
