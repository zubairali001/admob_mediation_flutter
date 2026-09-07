## 0.1.2

- Fix `NativeAdCard` losing its loaded (or in-flight) ad whenever it scrolled
  out of a lazy list's cache extent — the widget's state was destroyed and
  rebuilt from scratch on every return, so a native ad placed inside a feed
  or grid rarely survived long enough to actually be seen. It now keeps
  itself alive like any other stateful list item.

## 0.1.1

- Fix expiry timer not cancelled when `show()` takes the cached ad, preventing
  a redundant load after the timer fires.
- Fix double-dispose in `AdaptiveBannerAd` and `NativeAdCard` when the widget
  is removed while a load is in-flight.
- Rewrite README: remove stale adapter version table, add AdMob dashboard
  consent setup guide (GDPR and US-state), add initialization flow overview,
  and expand event and test-device documentation.

## 0.1.0

- Add app open, adaptive banner, interstitial, native, rewarded, and rewarded
  interstitial support.
- Add UMP consent sequencing and an explicit mediation consent provider.
- Add full-screen preloading, retry backoff, TTL expiry, frequency caps, and
  safe show coordination.
- Add a runtime master switch that disposes cached ads when disabled.
- Add lifecycle, reward, and impression-level revenue events.
- Add request customization and current Google Mobile Ads age treatment.
- Add a runnable Android/iOS example using Google's official test IDs.
- Add unit tests and continuous integration checks.
