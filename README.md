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

Needs `git`, `bash`, `python3` and `jq` on `PATH` — `gate.sh preflight` checks
all four and names whatever is missing. `bats` and `shellcheck` are dev-only.

```sh
git clone https://github.com/lmc-intella/mad-dreamer.git ~/mad-dreamer
```

Load it per session, which is the easiest thing to undo:

```sh
claude --plugin-dir ~/mad-dreamer
```

Or add it permanently with `/plugin marketplace add ~/mad-dreamer` followed by
`/plugin install mad-dreamer`. Either way `/plugin` lists three commands and
nothing else; the whole plugin costs ~269 always-on tokens (`claude
--plugin-dir ~/mad-dreamer plugin details mad-dreamer`).

## 60-second quickstart

A toy sprint, start to merge, using the fixture plan this repo ships. Run it in
a throwaway directory, not in a project you care about.

```sh
# 1 — a toy repo, from the fixture the shipped plan was written against
TOY="$(mktemp -d)/toy-service"
mkdir -p "$TOY/docs"
cp -r ~/mad-dreamer/tests/fixtures/ground-repo/. "$TOY/"
cp ~/mad-dreamer/tests/fixtures/plan-toy-1.md "$TOY/docs/"
cd "$TOY"

# 2 — the toy's one existing test is pytest-shaped, so say so. This file is also
#     what makes `gate.sh tests` discover `python3 -m pytest` on its own.
cat > pyproject.toml <<'TOML'
[tool.pytest.ini_options]
pythonpath = ["src"]
addopts = "--cov=src --cov-report=term"
TOML

git init -q -b main . && git add -A && git commit -qm "toy service"

# 3 — pytest + pytest-cov, somewhere `python3 -m pytest` resolves
uv venv -q && uv pip install -q pytest pytest-cov && . .venv/bin/activate
# no uv? `python3 -m pip install pytest pytest-cov` does the same job.

# 4 — the three gates execute runs at intake, before any session opens
bash ~/mad-dreamer/scripts/gate.sh preflight                      # STATUS=OK
bash ~/mad-dreamer/scripts/gate.sh plan-contract docs/plan-toy-1.md  # STORIES=3 NODES=3 EDGES=2
bash ~/mad-dreamer/scripts/gate.sh stamp docs/plan-toy-1.md          # MODE=mad-dreamer

# 5 — the sprint
claude --plugin-dir ~/mad-dreamer
```

Then, in that session:

```
/mad-dreamer:execute docs/plan-toy-1.md
```

The toy starts at 50% coverage against a 60% floor, so the sprint has to earn
its way past the gate. It builds a worktree beside `$TOY`, runs the plan's three
stories RED-then-GREEN, commits one per story, asks you once before merging into
`main`, and removes the worktree. `git log --oneline main` afterwards shows the
three story commits; `git log --grep '^Story: 2'` finds one by id.

To go the other way — a goal instead of a plan — start at
`/mad-dreamer:plan <goal>` in any repo and feed the file it writes to
`/mad-dreamer:execute`.

## Benchmark

Measured doc-load and always-on token cost against a full crewforge5 flow, the
gate-parity evidence behind "zero invariant-gate regressions", and what the
thresholded review actually costs you: [`docs/benchmark.md`](docs/benchmark.md).

## Licence

MIT — see `LICENSE`.
