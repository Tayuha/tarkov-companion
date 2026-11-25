/**
 * Typed failures for bundle publication.
 *
 * Every failure the publisher can diagnose has a `kind`, so the CLI can print a
 * stable, greppable line and exit 1 without leaking a stack trace. `not-found`
 * is used internally to map a GitHub 404 onto "no release yet" and is never a
 * user-facing state on its own.
 */

export type ReleaseErrorKind =
  | "invalid-mode"
  | "invalid-tag"
  | "tag-mismatch"
  | "invalid-asset-name"
  | "not-found"
  | "gh-not-found"
  | "unauthenticated"
  | "gh-failed"
  | "manifest-mismatch"
  | "empty-manifest"
  | "dataset-missing"
  | "dataset-mismatch"
  | "remote-manifest-invalid";

export class ReleaseError extends Error {
  readonly kind: ReleaseErrorKind;

  constructor(kind: ReleaseErrorKind, message: string) {
    super(message);
    this.name = "ReleaseError";
    this.kind = kind;
  }
}
