# Security Policy

## Supported versions

Tarkov Companion is pre-1.0. Only the latest release receives security fixes.

## Reporting a vulnerability

Do not open a public issue. Use GitHub's private vulnerability reporting on this repository
(**Security → Report a vulnerability**), or contact the maintainers directly if that is unavailable.

Please include:

- Affected version and platform
- Reproduction steps or a proof of concept
- Impact assessment, especially anything involving local progress data or update integrity

You can expect an acknowledgement within 7 days and a status update within 30 days.

## Scope

In scope:

- Bundle or installer tampering and update-path integrity
- Local database or exported progress disclosure
- Path traversal or arbitrary file write through import/export
- Crashes caused by malicious or malformed bundle or progress files
- Dependency vulnerabilities reachable from app or pipeline code

Out of scope:

- Issues in the upstream API or `assets.tarkov.dev` (report them to the tarkov.dev project)
- Game-client modifications, cheats, or anti-cheat bypasses
- Social engineering against players

## Design guarantees

The application has no accounts, no telemetry, and no backend. Player progress is stored only on the
device. Network access is limited to the documented allowlist, and downloaded datasets are verified by
SHA-256 before they are applied.

The full threat model, data-at-rest notes, and recovery guarantees are in [`docs/security.md`](docs/security.md).
The host allowlist and request rules are in [`docs/network.md`](docs/network.md).
