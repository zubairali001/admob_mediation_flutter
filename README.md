# AdMob Mediation — Flutter

Production-grade AdMob mediation stack for Flutter. Every ad format, full
consent handling (UMP / GDPR / ATT), 9 mediation networks, and a lazy,
service-based architecture where nothing loads until it is allowed to and
needed.

## What's included

| Piece | File |
|---|---|
| Orchestrator (consent → adapters → SDK init) | `lib/src/ads/ads_service.dart` |
| UMP consent (GDPR form, privacy options) | `lib/src/ads/consent/consent_service.dart` |
| Consent forwarding to mediation partners | `lib/src/ads/consent/mediation_consent_bridge.dart` |
| Generic full-screen ad engine (preload, retry backoff, TTL, frequency caps) | `lib/src/ads/core/full_screen_ad_service.dart` |
| App open ads (auto-show on foreground) | `lib/src/ads/services/app_open_ad_service.dart` |
| Interstitial ads | `lib/src/ads/services/interstitial_ad_service.dart` |
| Rewarded ads | `lib/src/ads/services/rewarded_ad_service.dart` |
| Rewarded interstitial ads | `lib/src/ads/services/rewarded_interstitial_ad_service.dart` |
| Anchored adaptive banner widget (+ collapsible option) | `lib/src/ads/widgets/adaptive_banner_ad.dart` |
| Native ad widget (Google templates) | `lib/src/ads/widgets/native_ad_card.dart` |
| Public facade — one function per ad format | `lib/src/ads/admob_mediation.dart` |
| Config object (ad unit ids + all options, auto test ids in debug) | `lib/src/ads/ads_config.dart` |
| Analytics event bus (incl. impression-level revenue) | `lib/src/ads/core/ad_events.dart` |

### Mediation networks bundled

Unity Ads, Meta Audience Network, AppLovin, Mintegral, Pangle, ironSource,
Liftoff Monetize (Vungle), InMobi, DT Exchange, Moloco — via Google's
official `gma_mediation_*` Flutter packages, so the native adapter versions
on Android and iOS are managed for you. This is every official Flutter
adapter Google publishes.

## How the architecture works

```
main()
 └─ AdsService.initialize()            ← runs async, never blocks first frame
     1. ConsentService.gatherConsent() ← UMP form if required (GDPR/US states)
     2. MediationConsentBridge         ← forwards consent to partner SDKs
     3. RequestConfiguration           ← test devices, COPPA, content rating
     4. MobileAds.initialize()         ← boots SDK + all 9 adapters
     └─ status → AdsStatus.ready

Each ad service/widget subscribes to AdsService.status.
Nothing loads before "ready"; everything pre-loads itself after.
Full-screen services keep one warm ad each, retry no-fills with
exponential backoff, expire stale ads (1h / 4h for app open), and share
a global "one full-screen ad at a time" lock + frequency caps.
```

Usage — everything goes through the `AdMobMediation` facade:

```dart
// 1. Manual initialization, all parameters in one config object:
await AdMobMediation.initialize(
  config: const AdsConfig(
    interstitial: AdUnitId(android: 'ca-app-pub-x/a', ios: 'ca-app-pub-x/b'),
    rewarded: AdUnitId(android: 'ca-app-pub-x/c', ios: 'ca-app-pub-x/d'),
    appOpen: AdUnitId(android: 'ca-app-pub-x/e', ios: 'ca-app-pub-x/f'),
    banner: AdUnitId(android: 'ca-app-pub-x/g', ios: 'ca-app-pub-x/h'),
    native: AdUnitId(android: 'ca-app-pub-x/i', ios: 'ca-app-pub-x/j'),
    rewardedInterstitial: AdUnitId(android: 'ca-app-pub-x/k'),
    testDeviceIds: ['HASHED-DEVICE-ID'],
    interstitialMinInterval: Duration(seconds: 60),
    autoShowAppOpenOnResume: true,
  ),
);

// 2. One function per format:
await AdMobMediation.showInterstitial(onDismissed: goNext);
await AdMobMediation.showRewarded(onReward: (r) => wallet.add(r.amount.toInt()));
await AdMobMediation.showRewardedInterstitial(onReward: (r) => ...);
await AdMobMediation.showAppOpen();          // manual (auto-show also built in)
AdMobMediation.skipNextAppOpen();            // before payment/picker flows
AdMobMediation.isInterstitialReady;          // ValueListenable<bool> for UI

// 3. Banner / native are widgets (optional per-instance adUnitId override):
Scaffold(bottomNavigationBar: const AdaptiveBannerAd());
const NativeAdCard(template: TemplateType.medium, adUnitId: '...');

// 4. Consent + utilities:
await AdMobMediation.isPrivacyOptionsRequired();
await AdMobMediation.showPrivacyOptionsForm();
AdMobMediation.openAdInspector();
AdMobMediation.events.listen((e) { /* analytics, incl. revenue */ });
```

In **debug builds Google test ids are used automatically** (any ids you pass
are ignored until release; `--dart-define=FORCE_TEST_ADS=true` keeps test ads
in release QA builds). Also replace the Android app id in
`android/app/src/main/AndroidManifest.xml` and the iOS app id in
`ios/Runner/Info.plist`.

---

# AdMob dashboard — complete setup checklist

## 1. Create the apps

1. Go to [apps.admob.com](https://apps.admob.com) → **Apps → Add app**.
2. Do this twice: once for **Android**, once for **iOS** (each platform is a
   separate AdMob app with its own App ID and ad units).
3. Copy each **App ID** (`ca-app-pub-…~…`):
   - Android → `AndroidManifest.xml` → `com.google.android.gms.ads.APPLICATION_ID`
   - iOS → `Info.plist` → `GADApplicationIdentifier`

## 2. Create the ad units (per platform)

**Apps → your app → Ad units → Add ad unit**, one of each:

| Ad unit | Paste into `AdsConfig` parameter |
|---|---|
| App open | `appOpen: AdUnitId(...)` |
| Banner (anchored adaptive) | `banner: AdUnitId(...)` |
| Interstitial | `interstitial: AdUnitId(...)` |
| Rewarded | `rewarded: AdUnitId(...)` |
| Rewarded interstitial | `rewardedInterstitial: AdUnitId(...)` |
| Native advanced | `native: AdUnitId(...)` |

## 3. Privacy & messaging (required for EEA/UK)

1. **Privacy & messaging → GDPR** → create a **GDPR message** for both apps,
   review the ad-partner list, publish it.
2. Optionally create a **US states** message (CCPA) and an **iOS ATT/IDFA
   explainer** message.
3. The app already runs the UMP flow on launch — the form appears
   automatically for users in regions that require it.

## 4. Sign up at each mediation partner & collect keys

For every network you keep, create a publisher account, register your app
(per platform), and create placements matching your ad formats:

| Network | What you need from their dashboard |
|---|---|
| Unity Ads | Game ID + Placement IDs (cloud.unity.com) |
| Meta Audience Network | App ID + Placement IDs (business.facebook.com) |
| AppLovin | SDK key + Zone IDs (dash.applovin.com) |
| ironSource | App key + Instance IDs (platform.ironsrc.com) |
| Mintegral | App ID, App Key + Placement/Unit IDs |
| Pangle | App ID + Ad Placement IDs |
| Liftoff Monetize (Vungle) | App ID + Placement reference IDs |
| InMobi | Account ID + Placement IDs |
| DT Exchange | App ID + Spot IDs |
| Moloco | App key + Ad unit IDs (adcloud.moloco.com) |

Tip: start with 2–4 networks (Meta, Unity, AppLovin, ironSource are the
usual best earners) — every extra SDK adds app size and startup work. Remove
a network by deleting its `gma_mediation_*` line from `pubspec.yaml`.

## 5. Wire the networks into AdMob mediation

For **each ad format** on **each platform**:

1. AdMob → **Mediation → Create mediation group**.
2. Choose the ad format + platform, target the matching ad unit(s).
3. Click **Add ad source**:
   - **Bidding** partners (Meta is bidding-only; most others support it):
     choose the ad source → sign their partnership agreement inside AdMob →
     paste the keys from step 4 into the "ad source mapping".
   - **Waterfall** sources: same mapping, plus a manual **eCPM** value (or
     enable eCPM optimization where offered).
4. Repeat per format (banner group, interstitial group, rewarded group, …).
5. Meta only: in Monetization Manager set the app to **bidding** with AdMob
   as the mediation platform.

## 6. Test everything

1. Add your device's hashed test-device id (printed in logcat/Xcode console
   on first run) to `AdsService.instance.initialize(testDeviceIds: [...])` in
   `main.dart`.
2. Run the app → tap the **Ad Inspector** icon in the app bar. It shows every
   ad unit, the full mediation waterfall, which adapter filled, and any
   per-network configuration errors.
3. On the AdMob **Mediation** page confirm every ad source mapping shows a
   green check.
4. GDPR flow: uncomment `debugGeography: DebugGeography.debugGeographyEea`
   in `main.dart` to force the consent form from anywhere.
5. Watch the console: every service logs `[Ads]` events including which
   mediation adapter filled each impression and its revenue.

## 7. Before release

- [ ] Replace all `ca-app-pub-XXXX…` placeholders (6 ad units × 2 platforms
      + both App IDs).
- [ ] `app-ads.txt`: AdMob → Apps → View all apps → app-ads.txt tab — publish
      the snippet at `https://yourdomain.com/app-ads.txt` and **append every
      mediation partner's app-ads.txt lines** (each partner's docs list them).
- [ ] Add your store listing URL to the AdMob app settings (needed for
      app-ads.txt verification) and to each partner dashboard.
- [ ] Google Play Console → App content → Ads declaration = yes;
      App Store Connect → App Privacy (tracking = yes, IDFA).
- [ ] If your app targets children: `childDirected: true` in
      `AdsService.initialize`, and configure the same in AdMob + partners.

## Build notes

- Android: Mintegral and Pangle resolve from their own Maven repositories —
  already added in `android/build.gradle.kts`.
- iOS: `platform :ios, '14.0'` is set in the Podfile (partner SDK minimums).
  Run `pod install --repo-update` in `ios/` after changing adapters.
- `gma_mediation_ironsource` is pinned to 2.4.1 and `gma_mediation_inmobi`
  to 2.1.0: their newer releases require the iOS GMA SDK 13.3, while
  `google_mobile_ads` 8.0.0 pins 13.2. Unpin them when upgrading
  `google_mobile_ads` past 8.x.
- Benign `pod install` warnings: the `EXCLUDED_ARCHS` merge notice
  (Meta vs ironSource simulator archs — only affects Intel-Mac simulators)
  and the Profile `base configuration` notice (standard Flutter warning).
- QA builds with real ad units but forced test ads:
  `flutter build apk --dart-define=FORCE_TEST_ADS=true`.
