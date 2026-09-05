# Publishing admob_mediation_flutter

## pub.dev listing values

The following values are already in `pubspec.yaml` and become the pub.dev
listing metadata:

| Field | Value |
|---|---|
| Package name | `admob_mediation_flutter` |
| Version | `0.1.0` |
| Description | An unofficial Flutter service layer for AdMob mediation with UMP consent, preloading, retry backoff, frequency caps, ad widgets, and revenue events. |
| Homepage | `https://github.com/zubairali001/admob_mediation_flutter` |
| Repository | `https://github.com/zubairali001/admob_mediation_flutter` |
| Issue tracker | `https://github.com/zubairali001/admob_mediation_flutter/issues` |
| Topics | `ads`, `admob`, `mediation`, `monetization`, `google-mobile-ads` |
| Platforms | Android, iOS |
| License | BSD 3-Clause |

pub.dev does not read a publisher name, support email, screenshots, or funding
details from this package. Manage uploader accounts and select a verified
publisher in the pub.dev web interface. A verified publisher is recommended
when you control a domain; otherwise the package is published under the signed-
in account.

On 2026-09-05 the pub.dev package API returned `404`, so the package name
appeared available. Names are not reserved by a local check; verify again
immediately before publishing.

## Required before the first publish

1. Create `zubairali001/admob_mediation_flutter` on GitHub, make it public, and
   push this repository. The homepage, repository, and issue tracker URLs must
   all resolve publicly.
2. Confirm that `admob_mediation_flutter` is still available on pub.dev.
3. Add a short repository description and the same five topics on GitHub.
4. Enable GitHub Issues so the declared issue tracker works.
5. Review the README, changelog, license holder, package version, minimum SDKs,
   and all dependencies.
6. Inspect the publish archive for secrets, credentials, production ad IDs,
   signing material, build output, and unrelated files.
7. Run the full release validation below from the package root.
8. Test the example on at least one Android and one iOS device with test ads.
   Confirm consent, each enabled format, rewards, paid events, Ad Inspector,
   foreground behavior, and the runtime disable switch.

## Release validation

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test example/lib
flutter analyze
flutter test
(cd example && flutter pub get && flutter analyze)
dart doc
dart pub publish --dry-run
```

Treat a successful analyzer, test run, documentation build, and dry run as code
checks. They do not replace real-device ad serving, AdMob console setup, partner
dashboard setup, consent-message review, store declarations, or policy review.

## Publish

Sign in with the Google account that should own the package, then run:

```sh
dart pub login
dart pub publish
```

Review the generated archive and confirm the prompt only after every dry-run
warning is understood. Publishing is permanent: a released version cannot be
replaced. After publication, push a matching `v0.1.0` git tag and verify the
pub.dev documentation, scores, links, and example rendering.

For later releases, update the version and changelog, repeat all validation,
publish, and create a matching git tag. Never reuse a published version number.
