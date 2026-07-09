import 'dart:math';

/// Exponential backoff for ad load retries.
///
/// Delays: 2s, 4s, 8s, 16s, 32s, 64s ... capped at [maxDelay]. Retrying
/// immediately after a no-fill wastes battery/network and can hurt your
/// AdMob quality score, so failures back off progressively.
class RetryPolicy {
  RetryPolicy({
    this.baseDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
    this.maxAttempts = 8,
  });

  final Duration baseDelay;
  final Duration maxDelay;
  final int maxAttempts;

  int _attempt = 0;

  bool get canRetry => _attempt < maxAttempts;

  /// Returns the delay to wait before the next retry and records the attempt.
  Duration nextDelay() {
    final delayMs = baseDelay.inMilliseconds * pow(2, _attempt).toInt();
    _attempt++;
    return Duration(milliseconds: min(delayMs, maxDelay.inMilliseconds));
  }

  void reset() => _attempt = 0;
}
