# mad-dreamer

A Claude Code plugin: three commands, one repo, roughly a quarter of the tool
calls of a fully gated sprint flow.

- `/mad-dreamer:init` — audit and slim a Claude config: one measured pass, one
  batched fix round, one report.
- `/mad-dreamer:plan` — a goal to a contract-valid, adversarially-stamped plan:
  batched decisions, review that loops only on CRITICAL/HIGH.
- `/mad-dreamer:execute` — that plan to a merged commit: isolated worktree,
  per-story TDD, tests-green and coverage gates.

## What it keeps, what it skips

It keeps every **invariant** gate — plan-contract parse, adversarial stamp,
findings closed at threshold, tests green, coverage met, clean-tree preflight,
retention safety. It drops the **process** ceremony — the per-phase state
machine, immutable-baseline re-checks, ledger distillation, and the integration
diagram. Review is thresholded, not exhaustive: it catches fewer MEDIUM/LOW
findings than a multi-round loop, which is the trade you are making.

**Interop guarantee:** the plan contract and the stamp grammar are byte-identical
to crewforge5's, so a mad-dreamer plan runs under a full crewforge5 execute and a
crewforge5 plan runs here. mad-dreamer has no runtime dependency on crewforge5 —
the contract scripts are vendored under `scripts/vendor/`.

## Install

Add this repo as a plugin to Claude Code, then run `/mad-dreamer:plan <goal>`.

Full quickstart and benchmark numbers: see `docs/` (Story 5).

## Licence

MIT — see `LICENSE`.
