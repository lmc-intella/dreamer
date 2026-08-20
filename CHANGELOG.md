# Changelog

All notable changes to dreamer are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The plan contract is part of the public interface: a change to the stamp grammar,
the story-heading shapes or the work-graph semantics is a version bump, whatever
the diff size says.

## [0.2.0] — 2026-08-21

### Added

- **`scripts/repomix.sh`** — packs a repo into one xml file (`.dreamer/repo.xml`)
  and traverses it: `pack` builds it (repomix when installed, `git ls-files`
  otherwise, same pack shape either way), `outline` maps directories, files and
  line counts, `show` prints one file straight out of the pack. Writes nothing
  but the pack, and never packs the pack into itself.
- **`scripts/ground.sh --pack <file>`** — scan a pack `repomix.sh pack` already
  built (`PROVIDER=pack`) instead of building a second one.

### Changed

- **`/dreamer:plan`** step 1 now packs the repo and reads the outline before any
  plan text exists, grounds against that same pack, and reads its ≤5 files out of
  it with `repomix.sh show`.
- **`/dreamer:execute`** gains step 4: pack the sprint worktree and traverse it
  before a line of code, check every story's `Touches` against the map, and read
  a story's files out of the pack at RED. The execute SKILL.md body budget moved
  from 120 to 130 lines to hold that phase.
- **Dynamic workflows** — `/dreamer:plan`'s adversarial review and
  `/dreamer:execute`'s per-story review now run as one dynamic `Workflow` each
  (parallel reviewer lenses plus an adversarial-verify stage), falling back to
  the previous single-pass review where the Workflow tool is unavailable.
  `.claude/settings.json` pins workflows enabled for the repo
  (`enableWorkflows`, `disableWorkflows: false`, `workflowSizeGuideline`) and
  clears `CLAUDE_CODE_DISABLE_WORKFLOWS` so an inherited shell value cannot
  switch them off.

## [0.1.0] — 2026-08-19

First release.

### Added

- **`/dreamer:init`** — audits and slims a Claude config in one measured
  pass. `scripts/measure.py` takes a before/after character and estimated-token
  reading; exactly two agent spawns audit all skills and all agents in a batch
  each; CRITICAL/HIGH findings are applied and MEDIUM/LOW are reported, not
  applied. Every edit passes through the vendored retention gate, and an edit
  that fails it is reverted from its `.bak`, never patched.
- **`/dreamer:plan`** — turns a goal into a contract-valid, adversarially
  stamped plan. Repo grounding through one `scripts/ground.sh` call (repomix
  when installed, `git ls-files` otherwise), at most two `AskUserQuestion`
  batches for the whole run, and a review loop that re-opens only on
  CRITICAL/HIGH. The plan file is the only artefact.
- **`/dreamer:execute`** — drives a stamped plan to a merged commit. Three
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
  dreamer resolves no plugin root at runtime and does not degrade when
  crewforge5 is absent, upgraded or removed. See `docs/vendor-policy.md`.
- **Interop guarantee** — the adversarial-review stamp grammar is character-for
  character the upstream regex, so a dreamer plan passes a full crewforge5
  execute and a crewforge5 plan runs here. `mode=dreamer` is the only added
  field; upstream ignores trailing fields, and any other `mode=` value fails
  closed as a contract collision. Verified in `docs/benchmark.md`.
- **`docs/benchmark.md`** — measured doc-load and always-on token cost against
  crewforge5-full, gate-parity evidence, and the honest trade-off statement.
- CI on push and pull request: shellcheck over every shell script and `bats
  tests/` on Ubuntu and macOS.

[Unreleased]: https://github.com/lmc-intella/dreamer/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/lmc-intella/dreamer/releases/tag/v0.1.0
