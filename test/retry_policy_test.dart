import 'package:admob_mediation_flutter/src/ads/core/retry_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('backs off exponentially and respects the maximum delay', () {
    final policy = RetryPolicy(
      baseDelay: const Duration(seconds: 2),
      maxDelay: const Duration(seconds: 5),
      maxAttempts: 4,
    );

    expect(policy.nextDelay(), const Duration(seconds: 2));
    expect(policy.nextDelay(), const Duration(seconds: 4));
    expect(policy.nextDelay(), const Duration(seconds: 5));
    expect(policy.nextDelay(), const Duration(seconds: 5));
    expect(policy.canRetry, isFalse);

    policy.reset();
    expect(policy.canRetry, isTrue);
    expect(policy.nextDelay(), const Duration(seconds: 2));
  });
}
