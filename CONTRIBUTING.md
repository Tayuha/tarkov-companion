# Contributing

Thanks for helping build Tarkov Companion. The project is in the planning phase, so the most useful
contributions right now are reviews of the specifications and spikes that de-risk the architecture.

## Ground rules

- Be respectful. See [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).
- Keep player data private. Never commit a database, an export, or logs containing progress.
- Do not add telemetry, analytics, accounts, or third-party tracking.
- Game data comes only from the documented upstream source. Do not scrape the game client.

## Workflow

This project uses [OpenSpec](https://github.com/Fission-AI/OpenSpec) for spec-driven development.

```bash
openspec list                     # in-flight changes
openspec list --specs             # durable capabilities
openspec show bootstrap-tarkov-companion
openspec validate bootstrap-tarkov-companion --strict
```

1. Open or claim an issue.
2. For behavior changes, propose an OpenSpec change before writing code.
3. Implement against `tasks.md`, keeping each task's verification honest.
4. Run the checks below before opening a pull request.

## Checks

```bash
# Pipeline
cd pipeline && npm ci && npm run lint && npm test && npm run build

# App
cd app && flutter analyze && flutter test
```

Windows packaging changes also require a debug build:

```bash
cd app && flutter build windows --debug
```

## Commits and pull requests

- Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`).
- One logical change per pull request; include the verification you ran.
- Reference the OpenSpec change and task id when applicable.
- Update specs and docs in the same pull request as the behavior change.

## Data pipeline contributions

Pipeline changes must run offline against `test/fixtures/`. Do not require contributor credentials; CI
uses the default `GITHUB_TOKEN`. If an upstream field changes, update the schema, the fixture, and the
golden files together.

## Reporting security issues

See [`SECURITY.md`](SECURITY.md). Do not open a public issue for a vulnerability.
