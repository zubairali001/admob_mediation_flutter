import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads/ads.dart';

/// Demo screen exercising the whole [AdMobMediation] API.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _coins = 0;
  bool _privacyOptionsRequired = false;

  @override
  void initState() {
    super.initState();
    AdMobMediation.status.addListener(_refreshPrivacyRequirement);
    _refreshPrivacyRequirement();
  }

  Future<void> _refreshPrivacyRequirement() async {
    if (!AdMobMediation.isReady) return;
    final required = await AdMobMediation.isPrivacyOptionsRequired();
    if (mounted) setState(() => _privacyOptionsRequired = required);
  }

  @override
  void dispose() {
    AdMobMediation.status.removeListener(_refreshPrivacyRequirement);
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AdMob Mediation'),
        actions: [
          IconButton(
            tooltip: 'Ad inspector',
            onPressed: AdMobMediation.openAdInspector,
            icon: const Icon(Icons.troubleshoot),
          ),
          if (_privacyOptionsRequired)
            IconButton(
              tooltip: 'Privacy options',
              onPressed: AdMobMediation.showPrivacyOptionsForm,
              icon: const Icon(Icons.privacy_tip_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ValueListenableBuilder<AdsStatus>(
            valueListenable: AdMobMediation.status,
            builder: (context, status, _) => Card(
              child: ListTile(
                leading: Icon(
                  status == AdsStatus.ready ? Icons.check_circle : Icons.hourglass_top,
                  color: status == AdsStatus.ready ? Colors.green : null,
                ),
                title: Text('Ads SDK: ${status.name}'),
                subtitle: Text('Coins earned from rewarded ads: $_coins'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _AdButton(
            title: 'Interstitial ad',
            subtitle: 'Full-screen ad at natural transition points',
            label: 'Show interstitial',
            icon: Icons.fullscreen,
            readyListenable: AdMobMediation.isInterstitialReady,
            onPressed: () async {
              final shown = await AdMobMediation.showInterstitial(
                onDismissed: () => _snack('Interstitial dismissed — continue flow'),
              );
              if (!shown) _snack('Interstitial not ready or frequency-capped');
            },
          ),
          _AdButton(
            title: 'Rewarded ad',
            subtitle: 'User opts in, watches a video, earns a reward',
            label: 'Show rewarded ad',
            icon: Icons.card_giftcard,
            readyListenable: AdMobMediation.isRewardedReady,
            onPressed: () async {
              final shown = await AdMobMediation.showRewarded(
                onReward: (reward) {
                  setState(() => _coins += reward.amount.toInt());
                },
              );
              if (!shown) _snack('Rewarded ad not ready yet');
            },
          ),
          _AdButton(
            title: 'Rewarded interstitial ad',
            subtitle: 'Reward ad at transitions, no opt-in button (show an intro first)',
            label: 'Show rewarded interstitial',
            icon: Icons.redeem,
            readyListenable: AdMobMediation.isRewardedInterstitialReady,
            onPressed: () async {
              final shown = await AdMobMediation.showRewardedInterstitial(
                onReward: (reward) {
                  setState(() => _coins += reward.amount.toInt());
                },
              );
              if (!shown) _snack('Rewarded interstitial not ready yet');
            },
          ),
          _AdButton(
            title: 'App open ad',
            subtitle: 'Also shows automatically when the app returns to foreground',
            label: 'Show app open ad now',
            icon: Icons.open_in_new,
            readyListenable: AdMobMediation.isAppOpenReady,
            onPressed: () async {
              final shown = await AdMobMediation.showAppOpen();
              if (!shown) _snack('App open ad not ready yet');
            },
          ),
          const SizedBox(height: 12),
          const _SectionTitle(
            'Native ad',
            subtitle: 'Blends with your UI — medium template',
          ),
          const SizedBox(height: 8),
          const Center(child: NativeAdCard(template: TemplateType.medium)),
          // Small-template example: only pair it with an IMAGE-ONLY native
          // ad unit in production — its media box (~100x100) is below the
          // 120x120 minimum for video, which triggers the debug validator
          // warning on Google's video-enabled test unit.
          // const Center(child: NativeAdCard(template: TemplateType.small)),
          const SizedBox(height: 24),
        ],
      ),
      bottomNavigationBar: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 8, bottom: 4),
            child: _SectionTitle(
              'Banner ad',
              subtitle: 'Anchored adaptive — sized to this device',
              centered: true,
            ),
          ),
          AdaptiveBannerAd(),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.subtitle, this.centered = false});

  final String title;
  final String? subtitle;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        if (subtitle != null)
          Text(
            subtitle!,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

class _AdButton extends StatelessWidget {
  const _AdButton({
    required this.title,
    required this.subtitle,
    required this.label,
    required this.icon,
    required this.readyListenable,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final String label;
  final IconData icon;
  final ValueListenable<bool> readyListenable;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title, subtitle: subtitle),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ValueListenableBuilder<bool>(
              valueListenable: readyListenable,
              builder: (context, isReady, _) => FilledButton.icon(
                onPressed: isReady ? onPressed : null,
                icon: Icon(icon),
                label: Text(isReady ? label : '$label (loading...)'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
