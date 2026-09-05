import 'dart:async';

import 'package:admob_mediation_flutter/admob_mediation_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const _config = AdsConfig(
  // The example always uses Google's public test ads, including release builds.
  useTestAds: true,
  appOpen: AdUnitId(android: 'configured', ios: 'configured'),
  banner: AdUnitId(android: 'configured', ios: 'configured'),
  interstitial: AdUnitId(android: 'configured', ios: 'configured'),
  rewarded: AdUnitId(android: 'configured', ios: 'configured'),
  rewardedInterstitial: AdUnitId(android: 'configured', ios: 'configured'),
  native: AdUnitId(android: 'configured', ios: 'configured'),
  autoShowAppOpenOnResume: false,
  interstitialMinInterval: Duration.zero,
  rewardedInterstitialMinInterval: Duration.zero,
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AdMob Mediation Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const AdsExamplePage(),
    );
  }
}

class AdsExamplePage extends StatefulWidget {
  const AdsExamplePage({super.key});

  @override
  State<AdsExamplePage> createState() => _AdsExamplePageState();
}

class _AdsExamplePageState extends State<AdsExamplePage> {
  late final Future<void> _initialization;
  StreamSubscription<AdEvent>? _eventSubscription;
  String _lastEvent = 'Waiting for initialization';
  bool _adsEnabled = true;

  @override
  void initState() {
    super.initState();
    _eventSubscription = AdMobMediation.events.listen((event) {
      if (mounted) setState(() => _lastEvent = event.toString());
    });
    _initialization = _initializeAds();
  }

  Future<void> _initializeAds() async {
    await AdMobMediation.initialize(config: _config);
    if (mounted) {
      setState(
        () => _lastEvent = 'Status: ${AdMobMediation.status.value.name}',
      );
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }

  void _setAdsEnabled(bool enabled) {
    AdMobMediation.setAdsEnabled(enabled);
    setState(() => _adsEnabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AdMob mediation')),
      bottomNavigationBar: const AdaptiveBannerAd(),
      body: FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ads enabled'),
                subtitle: const Text('Use this for remove-ads entitlements'),
                value: _adsEnabled,
                onChanged: _setAdsEnabled,
              ),
              _ReadyButton(
                ready: AdMobMediation.isInterstitialReady,
                label: 'Show interstitial',
                onPressed: () => AdMobMediation.showInterstitial(),
              ),
              _ReadyButton(
                ready: AdMobMediation.isRewardedReady,
                label: 'Show rewarded',
                onPressed: () => AdMobMediation.showRewarded(
                  onReward: (reward) => setState(
                    () =>
                        _lastEvent = 'Granted ${reward.amount} ${reward.type}',
                  ),
                ),
              ),
              _ReadyButton(
                ready: AdMobMediation.isRewardedInterstitialReady,
                label: 'Show rewarded interstitial',
                onPressed: () => AdMobMediation.showRewardedInterstitial(
                  onReward: (reward) => setState(
                    () =>
                        _lastEvent = 'Granted ${reward.amount} ${reward.type}',
                  ),
                ),
              ),
              _ReadyButton(
                ready: AdMobMediation.isAppOpenReady,
                label: 'Show app open',
                onPressed: () => AdMobMediation.showAppOpen(),
              ),
              FilledButton.tonal(
                onPressed: AdMobMediation.openAdInspector,
                child: const Text('Open Ad Inspector'),
              ),
              const SizedBox(height: 12),
              Text(_lastEvent, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              const NativeAdCard(template: TemplateType.medium),
            ],
          );
        },
      ),
    );
  }
}

class _ReadyButton extends StatelessWidget {
  const _ReadyButton({
    required this.ready,
    required this.label,
    required this.onPressed,
  });

  final ValueListenable<bool> ready;
  final String label;
  final Future<bool> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ready,
      builder: (context, isReady, child) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FilledButton(
          onPressed: isReady ? () => unawaited(onPressed()) : null,
          child: Text(isReady ? label : '$label (loading)'),
        ),
      ),
    );
  }
}
