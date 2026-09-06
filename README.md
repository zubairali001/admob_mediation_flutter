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

This package works with AdMob on its own. If you use mediation partners
(Unity, Meta, AppLovin, etc.), add their adapter packages to your app
following the
[Google mediation integrations page](https://developers.google.com/admob/flutter/mediation).
The adapters are separate packages maintained by Google — this package does
not bundle or version-lock any of them.

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

Set the deployment targets required by
[`google_mobile_ads`](https://pub.dev/packages/google_mobile_ads). If you use
mediation adapters, add any Maven repositories, SKAdNetwork identifiers, or
manifest entries their guides require.

If iOS fails with a `GoogleMobileAds_Beta.h` non-modular-header error, remove
`use_frameworks!` from the Podfile and reinstall pods.

## How it works

When you call `initialize`, the package runs this sequence automatically:

1. **UMP consent** — requests consent info, shows the form if required (GDPR/US-state).
2. **Partner consent sync** — forwards choices to registered mediation handlers (if any).
3. **Request configuration** — applies test devices, content rating, and age treatment.
4. **Mobile Ads SDK init** — boots the SDK (and any adapters the host app installed).
5. **Preload** — each configured full-screen format loads one ad in the background.

If consent is denied at step 1, the flow stops and ads stay disabled. No ad
request ever fires before consent is resolved. The whole sequence is
idempotent — calling `initialize` multiple times is safe.

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

Debug builds use Google's test ad unit IDs automatically — you never need to
look up test IDs yourself. For a release-mode QA build, use
`--dart-define=FORCE_TEST_ADS=true`. Never click live ads during development.

To see test ads on a physical device against production ad units, add the
device's hashed ID (printed in the debug console on first ad request):

```dart
AdsConfig(
  testDeviceIds: ['YOUR-HASHED-DEVICE-ID'],
)
```

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

The package handles GDPR and US-state privacy automatically through Google's
User Messaging Platform (UMP). It runs consent **before** any ad request — if
consent is denied, ads stay disabled for the session and the app continues
normally.

### 1. Create consent messages in AdMob

You must create the messages in the AdMob dashboard first, otherwise UMP has
nothing to show:

**GDPR (required for EEA/UK users):**

1. Open [AdMob](https://apps.admob.com) → **Privacy & messaging** → **GDPR**.
2. Click **Create message**.
3. Select the apps this message applies to.
4. Choose the consent options — "Consent or manage options" is recommended so
   users can accept, reject, or manage individual purposes.
5. Customize the message text and styling to match your app.
6. **Publish** the message. It will not appear to users until published.

**US state privacy (CCPA/CPRA — required for US users in applicable states):**

1. In **Privacy & messaging** → **US states**.
2. Click **Create message**.
3. Select the apps and customize the opt-out message.
4. **Publish** the message.

Without published messages, UMP will not show any consent form and will
fall back to the cached consent status from a previous session (or allow ads
if no prior status exists and the user is outside a regulated region).

### 2. Test consent from anywhere

Use `debugGeography` to simulate EEA or US regions during development. This
only works in debug builds:

```dart
AdsConfig(
  debugGeography: DebugGeography.debugGeographyEea, // Test GDPR form
  testDeviceIds: ['YOUR-HASHED-ID'], // Required for debug geography
)
```

To find your test device ID, run the app once — the Mobile Ads SDK prints a
line like `Use RequestConfiguration.Builder().setTestDeviceIds(Arrays.asList("ABCDEF123456"))`
in the debug console.

### 3. Add a privacy settings entry point

When UMP reports that a privacy options button is required (EEA/UK users),
your settings screen must offer one:

```dart
if (await AdMobMediation.isPrivacyOptionsRequired()) {
  // Show a "Privacy settings" or "Ad preferences" button that calls:
  await AdMobMediation.showPrivacyOptionsForm();
}
```

This reopens the consent form so users can change their choices. The package
automatically re-checks consent and updates ad loading status afterward.

### 4. What happens when consent is denied

- `AdMobMediation.status` becomes `AdsStatus.disabled`.
- No ads load or show — the app keeps running normally.
- Call `AdMobMediation.reinitialize()` if the user grants consent later
  (e.g. through the privacy options form).

### Mediation partner consent (optional)

Only needed when an installed mediation adapter requires an explicit privacy
API call. Most adapters read consent strings automatically — check the
adapter's integration guide before adding a handler.

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

### Child-directed apps

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

All ad formats emit events through a single stream. Subscribe once, early:

```dart
AdMobMediation.events.listen((event) {
  switch (event.type) {
    case AdEventType.paid:
      // Impression-level ad revenue — send to your analytics
      analytics.logAdRevenue(
        value: event.revenue!.value,
        currency: event.revenue!.currencyCode,
        adFormat: event.format.name,
        network: event.mediationAdapter,
      );
    case AdEventType.impression:
      analytics.logAdImpression(format: event.format.name);
    case AdEventType.failedToLoad:
      debugPrint('Ad failed: ${event.format.name} — ${event.error}');
    default:
      break;
  }
});
```

Available event types: `requested`, `loaded`, `failedToLoad`, `shown`,
`failedToShow`, `impression`, `clicked`, `dismissed`, `rewardEarned`, `paid`.

Use Google's Ad Inspector to verify your ad sources on a real device:

```dart
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
- Publish `app-ads.txt` with Google's entry (and partner entries if using mediation).
- Add the required privacy-options entry point when UMP reports it is required.
- Declare ads and data use in Google Play and App Store Connect.
- Validate consent, every format, rewards, paid events, and remove-ads on devices.
- Use Ad Inspector to confirm expected ad sources initialize.
- Implement server-side verification for rewards when fraud resistance matters.

See the runnable [example](example/lib/main.dart) and the maintainer
[publishing guide](PUBLISHING.md).
