<!-- Keep pull requests small and honest. Delete sections that do not apply. -->

## Summary

<!-- What changes, and why? Link the issue or OpenSpec task. -->

- Closes #
- OpenSpec change / task:

## Type

- [ ] Feature
- [ ] Bug fix
- [ ] Documentation
- [ ] CI, packaging or tooling
- [ ] Refactor with no behaviour change

## Verification

<!-- Paste the commands you ran and their result. "CI will check it" is not verification. -->

```bash
# Example
cd app && flutter analyze && flutter test
cd pipeline && npm run lint && npm test
bash -n scripts/*.sh
```

- [ ] App analyze and tests pass
- [ ] Pipeline lint and tests pass
- [ ] `bash -n scripts/*.sh` passes (when scripts changed)
- [ ] Workflow YAML parses (when `.github/` changed)
- [ ] Packaging or launch checked, or the manual step is written down

## Screenshots or artifact notes

<!-- UI changes: before/after at 1440 and 1920. Packaging changes: artifact names and sizes. -->

## Checklist

- [ ] No telemetry, analytics, accounts, or new network destinations outside `docs/network.md`
- [ ] No player data, database, export, or log with personal paths is committed
- [ ] No secrets, signing keys, tokens, or `.env` files are added
- [ ] Docs and OpenSpec tasks are updated in the same pull request
- [ ] Conventional Commit title (`feat:`, `fix:`, `docs:`, `ci:`, ...)
- [ ] I did not reformat unrelated files

## Release impact

<!-- Does this change app/pubspec.yaml, the bundle schema, a workflow, or the Linux package? -->
