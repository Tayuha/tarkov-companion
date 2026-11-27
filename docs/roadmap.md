# Roadmap and roadmap issue

The task-level plan lives in
[`openspec/changes/bootstrap-tarkov-companion/tasks.md`](../openspec/changes/bootstrap-tarkov-companion/tasks.md).
This page is the public summary and contains the body for the single pinned
roadmap issue.

## How to use this page

1. Create a new issue titled **`[Roadmap] v0.1 Linux preview → post-1.0`**
   (maintainers only; blank issues are disabled for everyone else).
2. Paste the body below the line.
3. Pin the issue and add the `roadmap` label.
4. Update the checklist when a milestone lands; keep the detail in OpenSpec.

The body is written to be pasted as-is. It deliberately avoids promising dates.

---

## Roadmap issue body

### Goal

A local-first Escape from Tarkov companion that opens instantly, works offline,
and keeps player progress on the user's own device. No accounts, no telemetry,
no cloud sync.

### v0.1 — Linux preview (current gate)

The Linux desktop build is the first release target. Windows and mobile remain
buildable in CI but are not packaged until the Linux artifact is approved.

- [ ] First Linux AppImage and `.deb` artifacts built by CI with checksums
- [ ] Release notes state that the artifacts are unsigned
- [ ] Clean-environment launch, first-run sync, search/filter/browse, and offline restart pass
- [ ] `v0.1.0` tag published after the manual approval checklist
- [ ] Issue, pull-request, and roadmap templates in use

Tracking detail: tasks 8.9, 8.10, 9.6, and 9.7. Packaging instructions:
[`docs/linux-package.md`](https://github.com/Tayuha/tarkov-companion/blob/main/docs/linux-package.md).
Release process: [`docs/release.md`](https://github.com/Tayuha/tarkov-companion/blob/main/docs/release.md).

### Now — finish the v0.1 client

- [ ] Quest tracker: removed-quest handling, available-quest view, game-mode scoping
- [ ] Item detail: acquisition/disposition, prices, image cache, price history, deep links
- [ ] Profiles: editable facts, reset/delete, export, validated import, portability test
- [ ] Desktop shell: offline/error states, window geometry, single instance, keyboard navigation, about screen
- [ ] End-to-end first-run, export, and re-import test

### Next — after the Linux gate

- [ ] Windows installer and portable build
- [ ] Android build and store metadata
- [ ] Accessibility audit with a keyboard-only and screen-reader pass
- [ ] Performance budgets on the full bundle: catalog p95 query and initial render

### Later — needs its own OpenSpec change

- [ ] Interactive maps
- [ ] Hideout and craft calculators
- [ ] Barter profit views
- [ ] A signing and provenance design for release artifacts

### Not planned

- Accounts, cloud sync, or a project-operated backend
- Telemetry, analytics, or crash reporting that uploads player data
- Stash OCR or any automation that reads the game client
- Scraping sources other than the documented tarkov.dev API

### How to help

- Reproduce a bug on a clean Linux install and attach sanitized logs.
- Pick a task from the OpenSpec change and comment on the issue first.
- Review the data bundle contract and the sync failure semantics.
- Test keyboard navigation and narrow windows.

Read [`CONTRIBUTING.md`](https://github.com/Tayuha/tarkov-companion/blob/main/CONTRIBUTING.md)
before opening a pull request. Security issues go through private reporting, not
this issue.
