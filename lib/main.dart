import 'dart:async';

import 'package:flutter/material.dart';

import 'src/ads/ads.dart';
import 'src/demo/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Wire analytics once: every ad event from every service flows through here.
  AdMobMediation.events.listen((event) {
    if (event.type == AdEventType.paid && event.revenue != null) {
      // TODO(you): forward impression-level revenue to Firebase/Adjust/etc.
    }
  });

  runApp(const AdMobMediationApp());

  // Manual, explicit initialization — non-blocking: consent flow + SDK init
  // run while the first frame renders. All services subscribe and pre-load
  // the moment the SDK is ready.
  unawaited(AdMobMediation.initialize(
    config: const AdsConfig(
      // In debug builds Google test ids are used automatically; fill these
      // with your real ad unit ids for release:
      appOpen: AdUnitId(android: 'ca-app-pub-xxx/aaa', ios: 'ca-app-pub-xxx/bbb'),
      banner: AdUnitId(android: 'ca-app-pub-xxx/ccc', ios: 'ca-app-pub-xxx/ddd'),
      interstitial: AdUnitId(android: 'ca-app-pub-xxx/eee', ios: 'ca-app-pub-xxx/fff'),
      rewarded: AdUnitId(android: 'ca-app-pub-xxx/ggg', ios: 'ca-app-pub-xxx/hhh'),
      rewardedInterstitial: AdUnitId(android: 'ca-app-pub-xxx/iii', ios: 'ca-app-pub-xxx/jjj'),
      native: AdUnitId(android: 'ca-app-pub-xxx/kkk', ios: 'ca-app-pub-xxx/lll'),
      // Options:
      testDeviceIds: <String>[], // hashed ids from the console on first run
      interstitialMinInterval: Duration(seconds: 60),
      autoShowAppOpenOnResume: true,
      // debugGeography: DebugGeography.debugGeographyEea, // test GDPR form
    ),
  ));
}

class AdMobMediationApp extends StatelessWidget {
  const AdMobMediationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AdMob Mediation',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
