# Agent guide (dcs-packages)

Melos monorepo of the DCS device / protocol packages (see [`README.md`](README.md)). Consumer: the DCS Flutter app
(`../dcs`).

- [`docs/ROBUSTNESS_RULES.md`](docs/ROBUSTNESS_RULES.md) applies to every change (`.cursor/` is git-ignored in this
  repo; a local copy lives at `.cursor/rules/dcs-packages-robustness.mdc`).
- Several packages are consumed from `ref: main` — work on a branch, add a test, bump the version and CHANGELOG.
- Open work from the 2026-11 system audit: [`docs/AUDIT_2026-11_HANDOFF.md`](docs/AUDIT_2026-11_HANDOFF.md).

| Task | Command |
| --- | --- |
| Bootstrap | `melos bootstrap` |
| Analyze | `melos run analyze` |
| Tests | `melos run test` · `melos run test:flutter` |
