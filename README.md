# admob_mediation_flutter

An unofficial Flutter service layer for Google Mobile Ads mediation. It adds
UMP consent sequencing, ad preloading, retry backoff, frequency caps, reusable
banner/native widgets, and a unified lifecycle and revenue event stream.

This package is not affiliated with or endorsed by Google.

## Features

- App open, banner, interstitial, native, rewarded, and rewarded interstitial ads
- Consent before Mobile Ads initialization and the first ad request
- One cached full-screen ad per configured format with TTL expiry
- Exponential retry backoff after load failures
- Per-format frequency caps and a global full-screen lock
- Runtime master switch for subscriptions and remove-ads entitlements
- Impression-level revenue and lifecycle events from one stream
- Google test IDs for configured formats in debug builds
- Optional partner adapters installed directly by the host app

## Requirements

- Flutter 3.38.1 or newer
- Dart 3.10 or newer
- Android and iOS only
- An AdMob account, registered apps, and an ad unit for each format you enable

## Installation

```yaml
dependencies:
  admob_mediation_flutter: ^0.1.0
```

The host app must add each mediation adapter it uses. Compatible adapter
versions for `google_mobile_ads: ^9.1.0` at this release are:

| Network | Package |
|---|---|
| Unity Ads | `gma_mediation_unity: ^1.10.0` |
| Meta Audience Network | `gma_mediation_meta: ^1.7.0` |
| AppLovin | `gma_mediation_applovin: ^2.6.3` |
| Mintegral | `gma_mediation_mintegral: ^2.1.3` |
| Pangle | `gma_mediation_pangle: ^4.1.1` |
| ironSource | `gma_mediation_ironsource: ^2.5.1` |
| Liftoff Monetize | `gma_mediation_liftoffmonetize: ^1.5.3` |
| InMobi | `gma_mediation_inmobi: ^2.3.1` |
| DT Exchange | `gma_mediation_dtexchange: ^1.3.6` |
| Moloco | `gma_mediation_moloco: ^3.6.1` |

Adapter versions change independently. Confirm the latest compatible version
and complete the network-specific Android, iOS, and privacy steps on the
[Google mediation integrations page](https://developers.google.com/admob/flutter/mediation).

## Platform setup

Add your AdMob **App ID**, not an ad unit ID, to Android
`android/app/src/main/AndroidManifest.xml`:

```xml
<manifest ...>
  <application ...>
    <meta-data
      android:name="com.google.android.gms.ads.APPLICATION_ID"
      android:value="ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY" />
  </application>
</manifest>
```

Add the iOS App ID to `ios/Runner/Info.plist`:

```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY</string>
```

Also copy the current `SKAdNetworkItems` list from Google's
[iOS Mobile Ads setup guide](https://developers.google.com/admob/ios/quick-start#update_your_infoplist).

Set the deployment targets required by the selected
[`google_mobile_ads`](https://pub.dev/packages/google_mobile_ads) and adapter
versions. Add any Maven repositories, SKAdNetwork identifiers, attribution
endpoints, or manifest entries required by each adapter's current guide.

If iOS fails with a `GoogleMobileAds_Beta.h` non-modular-header error, remove
`use_frameworks!` from the Podfile and reinstall pods. The included example
uses the static-library CocoaPods integration verified with version 9.1.0.

## Initialize

Configure only formats that the app actually uses. An unconfigured format
stays disabled, including when test mode is active.

```dart
import 'package:admob_mediation_flutter/admob_mediation_flutter.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AdMobMediation.initialize(
    config: const AdsConfig(
      appOpen: AdUnitId(
        android: 'ca-app-pub-xxx/android-app-open',
        ios: 'ca-app-pub-xxx/ios-app-open',
      ),
      banner: AdUnitId(
        android: 'ca-app-pub-xxx/android-banner',
        ios: 'ca-app-pub-xxx/ios-banner',
      ),
      interstitial: AdUnitId(
        android: 'ca-app-pub-xxx/android-interstitial',
        ios: 'ca-app-pub-xxx/ios-interstitial',
      ),
      rewarded: AdUnitId(
        android: 'ca-app-pub-xxx/android-rewarded',
        ios: 'ca-app-pub-xxx/ios-rewarded',
      ),
      native: AdUnitId(
        android: 'ca-app-pub-xxx/android-native',
        ios: 'ca-app-pub-xxx/ios-native',
      ),
      maxAdContentRating: MaxAdContentRating.pg,
    ),
  );

  runApp(const MyApp());
}
```

Debug builds use Google's test ad unit IDs for each configured format by
default. For a release-mode QA build, use
`--dart-define=FORCE_TEST_ADS=true`. Never click live ads during development.

## Show ads

Configured full-screen ads preload automatically. A show call returns `false`
when an ad is not ready, ads are disabled, the frequency cap is active, or
another full-screen ad is visible. The app should continue its normal flow in
that case.

```dart
await AdMobMediation.showInterstitial(onDismissed: openNextPage);

await AdMobMediation.showRewarded(
  onReward: (reward) {
    // Grant the reward only here.
    wallet.add(reward.amount.toInt());
  },
);

await AdMobMediation.showRewardedInterstitial(
  onReward: grantBonus,
);

await AdMobMediation.showAppOpen();
AdMobMediation.skipNextAppOpen(); // Before payment, sign-in, or file pickers.
```

Rewarded interstitials require an intro screen that clearly describes the
reward and lets the user skip the ad. Follow the current AdMob placement policy.

Bind a button to readiness instead of allowing repeated taps:

```dart
ValueListenableBuilder<bool>(
  valueListenable: AdMobMediation.isRewardedReady,
  builder: (context, ready, child) => FilledButton(
    onPressed: ready ? () => AdMobMediation.showRewarded(onReward: grant) : null,
    child: Text(ready ? 'Watch ad' : 'Loading ad'),
  ),
)
```

## Banner and native widgets

```dart
const AdaptiveBannerAd()
const AdaptiveBannerAd(collapsible: true)
const NativeAdCard(template: TemplateType.medium)
```

Only use collapsible banners on placements permitted by Google. For video
native ads, use the medium template; the small template's media area can be too
small for video creative requirements.

## Consent and privacy

Configure GDPR and US-state messages under **Privacy & messaging** in AdMob.
The package updates UMP first, shows a required form, checks whether ads may be
requested, and only then initializes Mobile Ads.

```dart
if (await AdMobMediation.isPrivacyOptionsRequired()) {
  await AdMobMediation.showPrivacyOptionsForm();
}
```

Do not infer GDPR or US-state choices from unrelated local preferences. If an
installed adapter requires an explicit privacy API, supply the current values
from your consent-management implementation and register its handler before
initialization:

```dart
AdMobMediation.registerConsentHandler(
  'Partner name',
  ({required hasGdprConsent, required ccpaOptedOut}) async {
    await partnerPrivacyApi.update(
      hasGdprConsent: hasGdprConsent,
      ccpaOptedOut: ccpaOptedOut,
    );
  },
);

await AdMobMediation.initialize(
  config: AdsConfig(
    mediationConsentProvider: () async => MediationConsent(
      hasGdprConsent: await consentStore.hasGdprConsent(),
      ccpaOptedOut: await consentStore.ccpaOptedOut(),
    ),
  ),
);
```

The identifiers above are placeholders for your own consent store and the
adapter's documented privacy API. If a handler fails, initialization fails
closed and `AdMobMediation.status` becomes `AdsStatus.disabled`.

For child-directed or under-age treatment, provide values based on your app's
audience and legal review:

```dart
const AdsConfig(
  ageRestrictedTreatment: AgeRestrictedTreatment.child,
  underAgeOfConsent: true,
)
```

## Requests and remove-ads entitlement

Customize the base request once; format-specific extras are merged into it:

```dart
AdsConfig(
  adRequest: const AdRequest(
    keywords: ['games'],
    contentUrl: 'https://example.com/game',
  ),
)
```

Disable every load and show as soon as a premium entitlement is known. Cached
ads are disposed and preloading resumes when re-enabled.

```dart
AdMobMediation.setAdsEnabled(!isPremium);
```

## Events and diagnostics

```dart
final subscription = AdMobMediation.events.listen((event) {
  if (event.type == AdEventType.paid && event.revenue != null) {
    analytics.logAdRevenue(
      value: event.revenue!.value,
      currency: event.revenue!.currencyCode,
    );
  }
});

AdMobMediation.openAdInspector();
```

`AdRevenue.valueMicros` is the raw value reported by Google;
`AdRevenue.value` converts it to currency units.

## Configuration reference

| Parameter | Default | Purpose |
|---|---|---|
| `appOpen`, `banner`, `interstitial`, `rewarded`, `rewardedInterstitial`, `native` | unconfigured | Platform ad unit IDs |
| `useTestAds` | debug/`FORCE_TEST_ADS` | Replaces configured IDs with Google test IDs |
| `testDeviceIds` | empty | Test devices used by UMP and Mobile Ads |
| `ageRestrictedTreatment` | unspecified | Google Mobile Ads age treatment |
| `underAgeOfConsent` | `null` | UMP under-age signal |
| `maxAdContentRating` | `null` | Maximum G, PG, T, or MA rating |
| `adRequest` | empty | Base targeting, privacy, and adapter extras |
| `interstitialMinInterval` | 60 seconds | Interstitial frequency cap |
| `rewardedInterstitialMinInterval` | 60 seconds | Rewarded interstitial frequency cap |
| `autoShowAppOpenOnResume` | `true` | App-open behavior on foreground |
| `debugGeography` | `null` | Debug-only UMP geography |
| `mediationConsentProvider` | `null` | Required with explicit consent handlers |

## Before shipping

- Replace every placeholder App ID and ad unit ID.
- Keep test ads enabled throughout development and QA.
- Create and verify every mediation ad source in the AdMob dashboard.
- Complete each partner's account, bidding/waterfall, and privacy setup.
- Publish `app-ads.txt` with Google and partner entries.
- Add the required privacy-options entry point when UMP reports it is required.
- Declare ads and data use in Google Play and App Store Connect.
- Validate consent, every format, rewards, paid events, and remove-ads on devices.
- Use Ad Inspector to confirm every expected adapter initializes.
- Implement server-side verification for rewards when fraud resistance matters.

See the runnable [example](example/lib/main.dart) and the maintainer
[publishing guide](PUBLISHING.md).
