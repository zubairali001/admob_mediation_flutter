import 'package:admob_mediation_flutter/admob_mediation_flutter.dart';
import 'package:admob_mediation_flutter/src/ads/consent/mediation_consent_bridge.dart'
    show MediationConsentBridge;
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(MediationConsentBridge.clearHandlers);
  tearDown(MediationConsentBridge.clearHandlers);

  test('forwards explicit consent to registered partners', () async {
    bool? gdpr;
    bool? ccpa;
    AdMobMediation.registerConsentHandler('Partner', ({
      required hasGdprConsent,
      required ccpaOptedOut,
    }) async {
      gdpr = hasGdprConsent;
      ccpa = ccpaOptedOut;
    });

    await MediationConsentBridge.sync(
      const MediationConsent(hasGdprConsent: false, ccpaOptedOut: true),
    );

    expect(gdpr, isFalse);
    expect(ccpa, isTrue);
  });

  test('registering the same partner replaces its handler', () async {
    var calls = 0;
    AdMobMediation.registerConsentHandler(
      'Partner',
      ({required hasGdprConsent, required ccpaOptedOut}) async => calls++,
    );
    AdMobMediation.registerConsentHandler(
      'Partner',
      ({required hasGdprConsent, required ccpaOptedOut}) async => calls += 10,
    );

    await MediationConsentBridge.sync(
      const MediationConsent(hasGdprConsent: true, ccpaOptedOut: false),
    );

    expect(calls, 10);
  });

  test(
    'aggregates partner failures so initialization can fail closed',
    () async {
      AdMobMediation.registerConsentHandler('Broken partner', ({
        required hasGdprConsent,
        required ccpaOptedOut,
      }) async {
        throw StateError('unavailable');
      });

      await expectLater(
        MediationConsentBridge.sync(
          const MediationConsent(hasGdprConsent: true, ccpaOptedOut: false),
        ),
        throwsA(
          isA<MediationConsentException>().having(
            (error) => error.failures.keys,
            'partners',
            contains('Broken partner'),
          ),
        ),
      );
    },
  );
}
