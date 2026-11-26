/// The outcome of an operation that can fail without throwing.
///
/// Used at boundaries where a failure is expected data (parsing, validation,
/// I/O) rather than a programming error.
sealed class Result<T> {
  const Result();

  /// Whether this is a success.
  bool get isOk => this is Ok<T>;

  /// Whether this is a failure.
  bool get isErr => this is Err<T>;

  /// The success value, or `null` for a failure.
  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };

  /// Transforms a success value, leaving a failure untouched.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Ok<T>(:final value) => Ok(transform(value)),
    Err<T>(:final error, :final stackTrace) => Err(error, stackTrace),
  };
}

/// A successful [Result].
final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;
}

/// A failed [Result].
final class Err<T> extends Result<T> {
  const Err(this.error, [this.stackTrace]);

  final Object error;
  final StackTrace? stackTrace;
}
