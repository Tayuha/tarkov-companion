import '../settings/app_settings.dart';

/// How current a price observation is relative to a freshness threshold.
enum FreshnessStatus {
  /// The observation exists and is at most [FreshnessPolicy.threshold] old.
  fresh,

  /// The observation exists and is strictly older than the threshold.
  stale,

  /// The item or its price observation is missing.
  unknown,
}

/// The freshness verdict for one item's newest price observation.
///
/// This type is the data layer's contract with the catalog UI
/// (`docs/freshness.md`): a stale price is never shown as an unqualified
/// current price. The UI must render [observedAt] next to a stale value, which
/// is why the timestamp travels with the verdict instead of being recomputed by
/// the widget.
final class PriceFreshness {
  const PriceFreshness({
    required this.status,
    required this.observedAt,
    required this.age,
    required this.threshold,
  });

  /// A verdict for an item (or observation) that does not exist.
  const PriceFreshness.unknown(this.threshold)
    : status = FreshnessStatus.unknown,
      observedAt = null,
      age = null;

  /// The observation instant, or `null` when [status] is
  /// [FreshnessStatus.unknown].
  final DateTime? observedAt;

  /// Non-negative age of the observation at evaluation time.
  ///
  /// `null` exactly when [status] is [FreshnessStatus.unknown]. A future
  /// observation is clamped to [Duration.zero] rather than reported as a
  /// negative age.
  final Duration? age;

  /// The threshold this verdict was evaluated against.
  final Duration threshold;

  final FreshnessStatus status;

  /// Whether the observation exists but is older than [threshold].
  bool get isStale => status == FreshnessStatus.stale;

  /// Whether the observation exists and is inside [threshold].
  bool get isFresh => status == FreshnessStatus.fresh;

  /// Whether no usable observation exists (missing item, missing time, or
  /// missing prices).
  bool get isUnknown => status == FreshnessStatus.unknown;

  /// Whether the UI must show [observedAt] next to the price.
  ///
  /// Always true for a known observation: a fresh price is qualified by its
  /// source time, and a stale price is explicitly labelled with it. Only an
  /// unknown observation has no time to show.
  bool get requiresObservationTime => observedAt != null;

  @override
  bool operator ==(Object other) =>
      other is PriceFreshness &&
      other.status == status &&
      other.observedAt == observedAt &&
      other.age == age &&
      other.threshold == threshold;

  @override
  int get hashCode => Object.hash(status, observedAt, age, threshold);

  @override
  String toString() =>
      'PriceFreshness(status: ${status.name}, observedAt: $observedAt, '
      'age: $age, threshold: $threshold)';
}

/// Decides whether a price observation is fresh or stale.
///
/// The comparison is deliberately **strictly greater**: an age exactly equal
/// to the threshold is still [FreshnessStatus.fresh]. "Older than the
/// threshold" means `age > threshold`, so a 24-hour threshold accepts an
/// observation that is exactly 24 hours old and rejects one at 24 h + 1 s.
///
/// A future timestamp (the client clock is behind upstream) is
/// [FreshnessStatus.fresh] with an [PriceFreshness.age] clamped to
/// [Duration.zero]. Treating it as stale would label data as outdated because
/// of clock skew, and a negative age is not meaningful to display.
final class FreshnessPolicy {
  FreshnessPolicy(this.threshold)
    : assert(!threshold.isNegative, 'threshold must not be negative');

  /// The documented default: [AppSettings.defaultDataFreshnessHours] hours.
  const FreshnessPolicy.defaults()
    : threshold = const Duration(hours: AppSettings.defaultDataFreshnessHours);

  /// Builds the policy from the user's configured threshold.
  ///
  /// [AppSettings.dataFreshnessHours] defaults to 24, so a default
  /// [AppSettings] produces a 24-hour policy.
  factory FreshnessPolicy.fromSettings(AppSettings settings) =>
      FreshnessPolicy(Duration(hours: settings.dataFreshnessHours));

  /// Maximum age that still counts as fresh.
  final Duration threshold;

  /// Evaluates [observedAt] at [now].
  ///
  /// * `null` observation → [FreshnessStatus.unknown] (no age, no timestamp).
  /// * age exactly [threshold] → [FreshnessStatus.fresh].
  /// * age greater than [threshold] → [FreshnessStatus.stale].
  /// * [observedAt] after [now] → [FreshnessStatus.fresh], age zero.
  PriceFreshness evaluate(DateTime? observedAt, DateTime now) {
    if (observedAt == null) {
      return PriceFreshness.unknown(threshold);
    }

    final rawAge = now.difference(observedAt);
    final age = rawAge.isNegative ? Duration.zero : rawAge;
    return PriceFreshness(
      status: age > threshold ? FreshnessStatus.stale : FreshnessStatus.fresh,
      observedAt: observedAt,
      age: age,
      threshold: threshold,
    );
  }
}
