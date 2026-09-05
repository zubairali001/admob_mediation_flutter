# admob_mediation_flutter

Production-ready AdMob mediation for Flutter. One-call initialization with
UMP/GDPR consent, pre-loading, retry backoff, frequency caps, and an
analytics event bus — every ad format, any combination of mediation networks.

## Features

- **Every ad format**: interstitial, rewarded, rewarded interstitial, app open,
  adaptive banner (collapsible), native (template-based).
- **Full consent handling**: UMP/GDPR flow runs before any ad request;
  pluggable consent forwarding for partner SDKs.
- **Pre-loading & retry**: full-screen ads keep one warm ad cached, retry
  no-fills with exponential backoff, expire stale ads (1h / 4h for app open).
- **Frequency caps**: configurable per-format minimum interval + global
  "one full-screen at a time" lock.
- **Analytics event bus**: every lifecycle event (loaded, shown, clicked,
  dismissed, reward earned, impression-level revenue) in one stream.
- **Automatic test IDs**: Google test ad unit IDs in debug builds — zero
  config to start testing.
- **Mediation networks are optional**: add only the `gma_mediation_*`
  packages you need — the core package doesn't force any.

## Getting started

### 1. Add the package

```yaml
dependencies:
  admob_mediation_flutter: ^1.0.0

  # Add only the mediation networks you want:
  gma_mediation_unity: ^1.8.0
  gma_mediation_meta: ^1.5.2
  gma_mediation_applovin: ^2.6.1
  # gma_mediation_mintegral: ^2.1.0
  # gma_mediation_pangle: ^3.6.0
  # gma_mediation_ironsource: ^2.4.1
  # gma_mediation_liftoffmonetize: ^1.5.0
  # gma_mediation_inmobi: ^2.1.0
  # gma_mediation_dtexchange: ^1.3.4
  # gma_mediation_moloco: ^3.4.0
```

### 2. Platform setup

**Android** — set your AdMob App ID in `android/app/src/main/AndroidManifest.xml`:

```xml
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY"/>
```

If you use **Mintegral** or **Pangle**, add their Maven repos in
`android/build.gradle.kts` (or `build.gradle`) under `allprojects.repositories`:

```kotlin
allprojects {
    repositories {
        // Mintegral
        maven { url = uri("https://dl-maven-android.mintegral.com/repository/mbridge_android_sdk_oversea") }
        // Pangle
        maven { url = uri("https://artifact.bytedance.com/repository/pangle") }
    }
}
```

**iOS** — set your AdMob App ID in `ios/Runner/Info.plist`:

```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY</string>
```

Set the minimum iOS version to 14.0+ in `ios/Podfile`:

```ruby
platform :ios, '14.0'
```

Then run `pod install --repo-update` in `ios/`.

### 3. Initialize

```dart
import 'package:admob_mediation_flutter/admob_mediation_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Optional: register consent handlers for networks that need them
  // (see "Mediation consent" below).

  await AdMobMediation.initialize(
    config: const AdsConfig(
      interstitial: AdUnitId(android: 'ca-app-pub-xxx/aaa', ios: 'ca-app-pub-xxx/bbb'),
      rewarded:     AdUnitId(android: 'ca-app-pub-xxx/ccc', ios: 'ca-app-pub-xxx/ddd'),
      banner:       AdUnitId(android: 'ca-app-pub-xxx/eee', ios: 'ca-app-pub-xxx/fff'),
      appOpen:      AdUnitId(android: 'ca-app-pub-xxx/ggg', ios: 'ca-app-pub-xxx/hhh'),
      native:       AdUnitId(android: 'ca-app-pub-xxx/iii', ios: 'ca-app-pub-xxx/jjj'),
    ),
  );

  runApp(const MyApp());
}
```

In **debug builds** Google test IDs replace yours automatically — just run
the app and ads work out of the box.

## Usage

```dart
// Full-screen ads — returns false if not ready or frequency-capped
await AdMobMediation.showInterstitial(onDismissed: goNext);

await AdMobMediation.showRewarded(
  onReward: (reward) => wallet.add(reward.amount.toInt()),
);

await AdMobMediation.showRewardedInterstitial(
  onReward: (reward) => grantBonus(reward),
);

await AdMobMediation.showAppOpen(); // also auto-shows on foreground by default

// Suppress app-open before flows that leave the app (payments, sign-in)
AdMobMediation.skipNextAppOpen();

// Widgets — drop anywhere
const AdaptiveBannerAd()                          // anchored adaptive banner
const AdaptiveBannerAd(collapsible: true)          // collapsible variant
const NativeAdCard(template: TemplateType.medium)  // native template ad

// Readiness — bind to UI (e.g. enable/disable a "Watch ad" button)
ValueListenableBuilder<bool>(
  valueListenable: AdMobMediation.isRewardedReady,
  builder: (_, ready, __) => ElevatedButton(
    onPressed: ready ? showRewardedAd : null,
    child: Text(ready ? 'Watch ad' : 'Loading...'),
  ),
)

// Analytics — impression-level revenue, ad lifecycle
AdMobMediation.events.listen((e) {
  if (e.type == AdEventType.paid) {
    analytics.logAdRevenue(value: e.revenue!.value, currency: e.revenue!.currencyCode);
  }
});

// Consent
if (await AdMobMediation.isPrivacyOptionsRequired()) {
  // Show a "Privacy options" button in settings
  AdMobMediation.showPrivacyOptionsForm();
}

// Debugging
AdMobMediation.openAdInspector(); // Google's mediation debug overlay
```

## AdsConfig reference

| Parameter | Default | Description |
|---|---|---|
| `appOpen` | none | Ad unit IDs for app open format |
| `banner` | none | Ad unit IDs for banner format |
| `interstitial` | none | Ad unit IDs for interstitial format |
| `rewarded` | none | Ad unit IDs for rewarded format |
| `rewardedInterstitial` | none | Ad unit IDs for rewarded interstitial format |
| `native` | none | Ad unit IDs for native format |
| `useTestAds` | `true` in debug | Force Google test IDs |
| `testDeviceIds` | `[]` | Hashed device IDs for test ads on real ad units |
| `childDirected` | `false` | COPPA flag |
| `maxAdContentRating` | `null` | G / PG / T / MA |
| `interstitialMinInterval` | 60s | Minimum time between interstitials |
| `rewardedInterstitialMinInterval` | 60s | Minimum time between rewarded interstitials |
| `autoShowAppOpenOnResume` | `true` | Auto-show app open on foreground |
| `debugGeography` | `null` | Test GDPR from anywhere (debug only) |

Only configure the formats you use — unconfigured formats stay idle.

## Mediation consent

The UMP consent form handles GDPR automatically. Most modern partner SDKs
(Meta, Mintegral, Pangle, InMobi, Moloco) read the IAB TCF string written
by UMP — they need no extra work.

Networks with **explicit consent APIs** need a registered handler. Call
`registerConsentHandler` before `initialize`:

```dart
// Unity
import 'package:gma_mediation_unity/gma_mediation_unity.dart';

AdMobMediation.registerConsentHandler('Unity', ({
  required bool hasGdprConsent,
  required bool ccpaOptedOut,
}) async {
  final unity = GmaMediationUnity();
  await unity.setGDPRConsent(hasGdprConsent);
  await unity.setCCPAConsent(!ccpaOptedOut);
});

// AppLovin
import 'package:gma_mediation_applovin/gma_mediation_applovin.dart';

AdMobMediation.registerConsentHandler('AppLovin', ({
  required bool hasGdprConsent,
  required bool ccpaOptedOut,
}) async {
  final appLovin = GmaMediationApplovin();
  await appLovin.setHasUserConsent(hasGdprConsent);
  await appLovin.setDoNotSell(ccpaOptedOut);
});

// ironSource
import 'package:gma_mediation_ironsource/gma_mediation_ironsource.dart';

AdMobMediation.registerConsentHandler('ironSource', ({
  required bool hasGdprConsent,
  required bool ccpaOptedOut,
}) async {
  final ironSource = GmaMediationIronsource();
  await ironSource.setConsent(hasGdprConsent);
  await ironSource.setDoNotSell(ccpaOptedOut);
});

// Liftoff Monetize (Vungle)
import 'package:gma_mediation_liftoffmonetize/gma_mediation_liftoffmonetize.dart';

AdMobMediation.registerConsentHandler('Liftoff', ({
  required bool hasGdprConsent,
  required bool ccpaOptedOut,
}) async {
  final liftoff = GmaMediationLiftoffmonetize();
  await liftoff.setGDPRStatus(hasGdprConsent, null);
  await liftoff.setCCPAStatus(!ccpaOptedOut);
});

// DT Exchange
import 'package:gma_mediation_dtexchange/gma_mediation_dtexchange.dart';

AdMobMediation.registerConsentHandler('DT Exchange', ({
  required bool hasGdprConsent,
  required bool ccpaOptedOut,
}) async {
  final dt = GmaMediationDTExchange();
  await dt.setUSPrivacyString(ccpaOptedOut ? '1YYN' : '1YNN');
  await dt.setLgpdConsent(hasGdprConsent);
});
```

## Removing a network

Delete its `gma_mediation_*` line from your `pubspec.yaml` and remove its
consent handler registration (if any). Run `flutter pub get` and
`pod install --repo-update` in `ios/`. That's it — the core package has no
hard dependency on any mediation adapter.

## Before release checklist

- [ ] Replace all `ca-app-pub-xxx` placeholders with real ad unit IDs.
- [ ] Set your AdMob App ID in `AndroidManifest.xml` and `Info.plist`.
- [ ] Publish `app-ads.txt` at your domain with AdMob's snippet + each
      partner's lines.
- [ ] Google Play: App content → Ads declaration = yes.
- [ ] App Store Connect: App Privacy → tracking declaration.
- [ ] If targeting children: set `childDirected: true` in `AdsConfig`.
- [ ] QA with forced test ads: `flutter build apk --dart-define=FORCE_TEST_ADS=true`.
