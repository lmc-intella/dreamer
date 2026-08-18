# Changelog

All notable changes to mad-dreamer are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The plan contract is part of the public interface: a change to the stamp grammar,
the story-heading shapes or the work-graph semantics is a version bump, whatever
the diff size says.

## [Unreleased]

## [0.1.0] — 2026-08-19

First release.

### Added

- **`/mad-dreamer:init`** — audits and slims a Claude config in one measured
  pass. `scripts/measure.py` takes a before/after character and estimated-token
  reading; exactly two agent spawns audit all skills and all agents in a batch
  each; CRITICAL/HIGH findings are applied and MEDIUM/LOW are reported, not
  applied. Every edit passes through the vendored retention gate, and an edit
  that fails it is reverted from its `.bak`, never patched.
- **`/mad-dreamer:plan`** — turns a goal into a contract-valid, adversarially
  stamped plan. Repo grounding through one `scripts/ground.sh` call (repomix
  when installed, `git ls-files` otherwise), at most two `AskUserQuestion`
  batches for the whole run, and a review loop that re-opens only on
  CRITICAL/HIGH. The plan file is the only artefact.
- **`/mad-dreamer:execute`** — drives a stamped plan to a merged commit. Three
  intake gates, an isolated worktree, one RED-then-GREEN TDD cycle per story,
  one combined security-and-correctness review spawn per story, and exactly one
  commit per story in the same shape a crewforge5 story commit carries.
- **`scripts/gate.sh`** — the six gates the three commands share: `preflight`,
  `plan-contract`, `stamp`, `findings`, `tests` (with an optional coverage
  floor), `report`. Each prints `STATUS=OK` or `STATUS=FAIL` plus `KEY=VALUE`
  detail lines and is read-only by construction.
- **Vendored plan contract** — `validate_plan_path.sh`, `parse_stories.sh`,
  `build_graph.sh` and `retention_gate.sh` are copied into `scripts/vendor/`
  from one pinned upstream commit, each carrying its provenance in a header.
  mad-dreamer resolves no plugin root at runtime and does not degrade when
  crewforge5 is absent, upgraded or removed. See `docs/vendor-policy.md`.
- **Interop guarantee** — the adversarial-review stamp grammar is character-for
  character the upstream regex, so a mad-dreamer plan passes a full crewforge5
  execute and a crewforge5 plan runs here. `mode=mad-dreamer` is the only added
  field; upstream ignores trailing fields, and any other `mode=` value fails
  closed as a contract collision. Verified in `docs/benchmark.md`.
- **`docs/benchmark.md`** — measured doc-load and always-on token cost against
  crewforge5-full, gate-parity evidence, and the honest trade-off statement.
- CI on push and pull request: shellcheck over every shell script and `bats
  tests/` on Ubuntu and macOS.

[Unreleased]: https://github.com/linusamcm-source/mad-dreamer/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/linusamcm-source/mad-dreamer/releases/tag/v0.1.0
