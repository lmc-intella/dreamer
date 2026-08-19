# dreamer-launch-1 — standalone fast-path plugin (new repo)

Goal: a new repository shipping a Claude Code plugin with three commands —
`init`, `plan`, `execute` — that produce the same output artifacts as
crewforge5's full flows (config report, contract-valid stamped plan, merged
commit) at roughly a quarter of the tool calls. Standalone: installs and runs
with no crewforge5 present. Interoperable: its plan files run under full
crewforge5 execute and vice versa, because the plan contract and stamp format
are held identical.

Plugin name: **dreamer** (ratified). Story 0 now covers repo + scaffold only.

Design rules (carried over from the lite design, now standalone):

- **Keep invariant gates, drop process gates.** Invariants: plan-contract
  parse, adversarial stamp, findings closed at threshold, tests green,
  coverage met, clean-tree preflight, retention safety. Dropped: per-phase
  state machine, immutable-baseline re-checks, ledger distillation,
  integration diagram.
- **No flow driver, no phase docs.** One SKILL.md per command (≤120 lines),
  inline checklist, one gate script at ≤3 checkpoints, state in one
  `state.json`.
- **Vendored contract, zero runtime deps on crewforge5.** The scripts that
  define the plan contract (`validate_plan_path.sh`, `parse_stories.sh`,
  `build_graph.sh`) and `retention_gate.sh` are copied in under `scripts/
  vendor/` with a provenance header (source repo, commit, date). A CI check
  optionally diffs vendor against upstream to flag drift — informational, not
  blocking.
- **Batch every human interaction; iterate only on CRITICAL/HIGH.**

## Story 0: name, repo, plugin scaffold

### Acceptance Criteria

- Plugin name `dreamer` recorded in `plugin.json` and README; a quick
  marketplace/GitHub check confirms no collision, noted in the first commit
  message.
- New repo initialised with `.claude-plugin/plugin.json` (name, version
  0.1.0, description, author), `commands/` wiring the three commands,
  `skills/` housing the three SKILL.md files, LICENSE, README.
- `plugin-forge` (from crewforge5, used as a dev tool only) or manual
  scaffold produces a structure that installs cleanly: a fresh Claude Code
  session with only this plugin added lists all three commands and triggers
  the right skill per command.
- README states in ≤10 lines what the plugin is, what it deliberately skips
  vs a full gated flow, and the interop guarantee.
- No file in the repo references `CREWFORGE5_ROOT`, `scripts/flow/`, or
  `subskill_resolve.sh` (grep-enforced in a test).

### Definition of Done

- Clean-clone install test passes on a machine/profile without crewforge5.
- CI (GitHub Actions) runs shellcheck + bats on push.

### Touches:

- .claude-plugin/**
- commands/**
- README.md
- LICENSE
- .github/**

### Depends On: none

## Story 1: vendored contract + gate script

### Acceptance Criteria

- `scripts/vendor/` contains `validate_plan_path.sh`, `parse_stories.sh`,
  `build_graph.sh`, `retention_gate.sh`, each with a provenance header
  naming source repo, commit hash, and vendor date; scripts run unmodified
  except path resolution.
- `scripts/gate.sh` exists with subcommands `preflight`, `plan-contract`,
  `stamp`, `findings`, `tests`, `report`; each prints `STATUS=OK|FAIL` plus
  `KEY=VALUE` detail, exits 0/1, never edits a file.
- `gate.sh plan-contract` passes against a copy of crewforge5's
  `golden-template-1.md` fixture (vendored into `tests/fixtures/`), proving
  contract identity.
- The stamp grammar accepted/emitted is byte-compatible with crewforge5's
  (`<!-- adversarial-review: status=... -->`), extended only by
  `mode=dreamer` — verified by a fixture that full crewforge5's findings
  gate also accepts (dev-machine test, documented, not CI-required).
- `tests/gate.bats` covers every subcommand, one pass and one fail fixture
  each, green.

### Definition of Done

- `bats tests/` green on clean clone; shellcheck clean on all scripts.
- A `docs/vendor-policy.md` states the drift stance: vendor is pinned, drift
  check is informational, contract changes upstream get a deliberate
  re-vendor with a version bump.

### Touches:

- scripts/**
- tests/**
- docs/vendor-policy.md

### Depends On: 0

## Story 2: init command — one measured pass, one fix batch, one report

### Acceptance Criteria

- `/dreamer:init` runs three steps: (1) measure + audit in a single pass —
  a self-contained `measure.py` (char/token counts per skill/agent/CLAUDE.md;
  reimplemented, not vendored, ≤150 lines) plus ONE batched validator agent
  over all skills and ONE over all agents; (2) apply CRITICAL/HIGH fixes,
  list MEDIUM/LOW as recommendations; (3) re-measure, write
  `.dreamer/init/report.md` with the char delta.
- Every edit passes vendored `retention_gate.sh`; a breach reverts the edit
  and records it in the report.
- Agent spawns per run ≤ 3, recorded in the report.
- Only gates: `gate.sh preflight` before, `gate.sh report` after.

### Definition of Done

- Fixture config root (≥5 skills, one carrying a `never` retention line)
  runs end-to-end; the `never` line survives; report contains before/after
  chars, per-component grades, applied vs deferred findings.

### Touches:

- skills/init/**
- scripts/measure.py

### Depends On: 1

## Story 3: plan command — batched decisions, thresholded review

### Acceptance Criteria

- `/dreamer:plan` runs three steps: (1) intake + ground — goal confirmed,
  repo grounding via a self-contained pack-and-grep helper (repomix if
  installed, `git ls-files` + grep fallback; no crewforge5 use-repo-code);
  (2) decide + draft — open decisions framed, ONE `AskUserQuestion` call per
  ≤4 questions, one push-back round on the batch, plan drafted directly in
  contract shape; (3) review + stamp — single adversarial pass applying all
  findings, looping only while CRITICAL/HIGH remain, then stamp with
  `mode=dreamer rounds=<N>`.
- Emitted plan passes `gate.sh plan-contract` with zero errors.
- MEDIUM/LOW findings applied without a loop are listed in a `## Review
  notes` section of the plan.
- No serial one-question-per-turn interaction anywhere.

### Definition of Done

- End-to-end run on a toy goal in a fixture repo; emitted plan parses clean
  through vendored `parse_stories.sh` + `build_graph.sh`.
- Documented dev-machine check: the same plan passes full crewforge5
  execute Phase 0/1 gates.

### Touches:

- skills/plan/**
- scripts/ground.sh

### Depends On: 1

## Story 4: execute command — TDD spine, ceremony stripped

### Acceptance Criteria

- `/dreamer:execute` keeps the load-bearing spine: isolated worktree,
  contract parse at intake, stamp hard-STOP (no override), per-story TDD
  (RED test per AC before implementation), tests-green + coverage gate, one
  commit per story, block-collect-close on every spawned child.
- Rigour defaults to Fast (60% coverage), overridable inline; one combined
  code-review pass per story (security + correctness, single agent) instead
  of a multi-lens fleet; no integration diagram, no distillation phase.
- The whole run loads ≤2 markdown docs (its own SKILL.md and the plan);
  grep-enforced: no `references/phases/` paths exist in the repo.
- No force-push, no main-branch writes without explicit confirmation; on
  green it merges or opens a PR per inline flag, commit shape identical to
  crewforge5's (one commit per story, story id in message).

### Definition of Done

- 2-story fixture plan runs end-to-end in a scratch repo: worktree,
  RED→GREEN per story, 60% coverage enforced, merged, worktree removed.
- Failing fixture (untestable AC) STOPs with a usable message at the right
  point.

### Touches:

- skills/execute/**

### Depends On: 1, 3

## Story 5: benchmark, docs, v0.1.0 launch

### Acceptance Criteria

- `docs/benchmark.md` records, for the same fixture goal run through
  crewforge5-full and `dreamer` (dev machine, both installed): tool-call
  count, wall time, tokens in loaded docs, output-artifact diff. Target:
  ≥60% reduction in tool calls and doc-load tokens, zero invariant-gate
  regressions.
- The doc states the trade-off honestly: thresholded review catches fewer
  MEDIUM/LOW findings than a 6-round loop, and names the escape hatch (run
  crewforge5's full phase-7 review over a `dreamer` plan when stakes
  warrant — interop makes this a one-liner).
- README carries install instructions, a 60-second quickstart (init → plan
  → execute on a toy repo), and the benchmark link.
- Version tagged v0.1.0; CHANGELOG started; marketplace/plugin listing
  entry drafted if publishing beyond personal use.

### Definition of Done

- Benchmark numbers measured from real runs, not estimated.
- A second person (or a fresh Claude Code session with zero prior context)
  can go from clone to a merged fixture sprint using only the README.

### Touches:

- docs/**
- README.md
- CHANGELOG.md

### Depends On: 2, 3, 4
