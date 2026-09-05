import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Every ad format the app serves.
enum AdFormat {
  appOpen,
  banner,
  interstitial,
  rewarded,
  rewardedInterstitial,
  native,
}

/// Lifecycle events emitted by the ad services.
enum AdEventType {
  requested,
  loaded,
  failedToLoad,
  shown,
  failedToShow,
  impression,
  clicked,
  dismissed,
  rewardEarned,
  paid,
}

/// Revenue data reported by `onPaidEvent` (impression-level ad revenue).
@immutable
class AdRevenue {
  const AdRevenue({
    required this.valueMicros,
    required this.currencyCode,
    required this.precision,
  });

  final double valueMicros;
  final String currencyCode;
  final PrecisionType precision;

  double get value => valueMicros / 1000000;

  @override
  String toString() => '$value $currencyCode (${precision.name})';
}

/// A single ad lifecycle event. Fan these out to your analytics SDK
/// (Firebase, Adjust, AppsFlyer, ...) from one place.
@immutable
class AdEvent {
  const AdEvent({
    required this.format,
    required this.type,
    this.error,
    this.reward,
    this.revenue,
    this.mediationAdapter,
  });

  final AdFormat format;
  final AdEventType type;
  final Object? error;
  final RewardItem? reward;
  final AdRevenue? revenue;

  /// Class name of the mediation adapter that filled the impression
  /// (e.g. Unity, Meta, AppLovin...). Useful to see which network is serving.
  final String? mediationAdapter;

  @override
  String toString() =>
      'AdEvent(${format.name}.${type.name}'
      '${mediationAdapter != null ? ', adapter: $mediationAdapter' : ''}'
      '${reward != null ? ', reward: ${reward!.amount} ${reward!.type}' : ''}'
      '${revenue != null ? ', revenue: $revenue' : ''}'
      '${error != null ? ', error: $error' : ''})';
}

/// Broadcast bus for ad events. Services publish; analytics subscribes once.
///
/// ```dart
/// AdEventBus.instance.stream.listen((e) {
///   if (e.type == AdEventType.paid) {
///     analytics.logAdImpression(value: e.revenue!.value, ...);
///   }
/// });
/// ```
class AdEventBus {
  AdEventBus._();

  static final AdEventBus instance = AdEventBus._();

  final StreamController<AdEvent> _controller =
      StreamController<AdEvent>.broadcast();

  Stream<AdEvent> get stream => _controller.stream;

  void emit(AdEvent event) {
    if (kDebugMode) debugPrint('[Ads] $event');
    if (!_controller.isClosed) _controller.add(event);
  }
}
