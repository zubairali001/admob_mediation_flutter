// ignore_for_file: unused_local_variable

import 'package:admob_mediation_flutter/admob_mediation_flutter.dart';
import 'package:flutter/material.dart';

// If using networks with explicit consent APIs, import them and register
// handlers before initialize(). Example with Unity:
//
// import 'package:gma_mediation_unity/gma_mediation_unity.dart';
//
// AdMobMediation.registerConsentHandler('Unity', ({
//   required bool hasGdprConsent,
//   required bool ccpaOptedOut,
// }) async {
//   final unity = GmaMediationUnity();
//   await unity.setGDPRConsent(hasGdprConsent);
//   await unity.setCCPAConsent(!ccpaOptedOut);
// });

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Listen to all ad events (analytics, impression-level revenue).
  AdMobMediation.events.listen((event) {
    if (event.type == AdEventType.paid && event.revenue != null) {
      // Forward to Firebase / Adjust / AppsFlyer / etc.
    }
  });

  // 2. Initialize — consent flow + SDK boot run async, never blocks UI.
  await AdMobMediation.initialize(
    config: const AdsConfig(
      // In debug builds Google test IDs are used automatically.
      // Fill these with your real ad unit IDs for release:
      interstitial: AdUnitId(
        android: 'ca-app-pub-xxx/aaa',
        ios: 'ca-app-pub-xxx/bbb',
      ),
      rewarded: AdUnitId(
        android: 'ca-app-pub-xxx/ccc',
        ios: 'ca-app-pub-xxx/ddd',
      ),
      banner: AdUnitId(
        android: 'ca-app-pub-xxx/eee',
        ios: 'ca-app-pub-xxx/fff',
      ),
      appOpen: AdUnitId(
        android: 'ca-app-pub-xxx/ggg',
        ios: 'ca-app-pub-xxx/hhh',
      ),
      native: AdUnitId(
        android: 'ca-app-pub-xxx/iii',
        ios: 'ca-app-pub-xxx/jjj',
      ),
      testDeviceIds: [], // Add your hashed device ID from logcat/Xcode
      interstitialMinInterval: Duration(seconds: 60),
      autoShowAppOpenOnResume: true,
    ),
  );

  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('AdMob Mediation Example')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Show interstitial at a natural transition
              FilledButton(
                onPressed: () async {
                  final shown = await AdMobMediation.showInterstitial(
                    onDismissed: () => debugPrint('Interstitial closed'),
                  );
                  if (!shown) debugPrint('Not ready or frequency-capped');
                },
                child: const Text('Show Interstitial'),
              ),
              const SizedBox(height: 16),

              // Show rewarded — grant reward only in the callback
              FilledButton(
                onPressed: () async {
                  await AdMobMediation.showRewarded(
                    onReward: (reward) {
                      debugPrint('Earned ${reward.amount} ${reward.type}');
                    },
                  );
                },
                child: const Text('Show Rewarded'),
              ),
              const SizedBox(height: 16),

              // Native ad widget
              const NativeAdCard(template: TemplateType.medium),
            ],
          ),
        ),

        // Adaptive banner at the bottom
        bottomNavigationBar: const AdaptiveBannerAd(),
      ),
    );
  }
}
