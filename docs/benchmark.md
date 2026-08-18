# Benchmark — mad-dreamer vs a full crewforge5 flow

Dev machine, 2026-08-19. Claude Code 2.1.234, mad-dreamer 0.1.0 loaded with
`--plugin-dir`, crewforge5 0.4.2 from the plugin cache. Both flows were pointed
at the same fixture plan, `tests/fixtures/plan-toy-1.md`, over the same toy repo,
`tests/fixtures/ground-repo`.

**Every number below is labelled with how it was obtained.** Doc-load bytes and
always-on cost are measurements. Tool-call count and wall time were attempted as
real end-to-end runs; read the caveat before quoting them.

## Summary

| Metric | crewforge5-full | mad-dreamer | Change | Provenance |
| --- | --- | --- | --- | --- |
| Doc-load, `execute` flow (chars) | 94,605 | 11,868 | **−87.5%** | measured, `wc -c` |
| Doc-load, `execute` flow (est. tokens) | ~23,652 | ~2,967 | **−87.5%** | derived, `ceil(chars/4)` |
| Doc-load, `plan` flow (chars) | 18,689 | 5,564 | **−70.2%** | measured, `wc -c` |
| Doc-load, `init` flow (chars) | 20,702 | 5,333 | **−74.2%** | measured, `wc -c` |
| Always-on plugin cost (est. tokens) | ~3,335 | ~269 | **−91.9%** | measured, `claude plugin details` |
| Tool calls, end-to-end `execute` | 58 (run unfinished) | 72 (run finished) | **not comparable** | measured, but see below |
| Wall time, end-to-end `execute` | 900 s (timed out) | 727.5 s (merged) | **not comparable** | measured, but see below |
| Invariant-gate regressions | — | **0** | — | measured, gates re-run |

> **The ≥60% tool-call reduction target is NOT VERIFIED.** Tool calls were
> measured for both flows, but the two runs are not like-for-like: mad-dreamer
> finished the sprint and merged; crewforge5-full hit the 900-second cap still
> inside Phase 0 of 10, with zero commits. A count taken from a run that did not
> finish cannot be divided by one that did. The ≥60% doc-load target **is** met
> and exceeded; the tool-call half of the target stands unproven. The exact
> procedure to close it is in [Filling the gap](#filling-the-gap).

## 1. Doc-load tokens — measured

Both flows are markdown. This section counts the bytes a single `execute` run
actually pulls into the context window, and converts with the same estimator
`scripts/measure.py` uses: `est_tokens = ceil(chars / 4)`.

**What the estimator is and is not.** Four characters per token is a rule of
thumb for English prose under byte-pair encodings. No tokenizer is run and no
vocabulary is consulted, so an absolute count carries no accuracy guarantee —
tables, code fences and JSON all tokenize worse than prose, and both sides here
are full of them. The *ratio* between two markdown corpora measured the same way
is the trustworthy number; the absolute token figures are indicative only. The
underlying `wc -c` character counts are exact.

### mad-dreamer `execute`

Its SKILL.md says so in its own first line: "Two documents load for the whole
run: this page and the plan."

| File | chars | est. tokens |
| --- | ---: | ---: |
| `skills/execute/SKILL.md` | 6,761 | 1,691 |
| the plan (`tests/fixtures/plan-toy-1.md`) | 5,107 | 1,277 |
| **total** | **11,868** | **~2,967** |

### crewforge5 `execute` — the flow spine

Read off `skills/execute/SKILL.md` and the `phases.json` manifest it calls "the
authority on what runs". Phases 0–7 resolve to team-sprint's own phase docs in
`skills/team-sprint/references/phases`; phases 8 and 9 to `skills/execute/phases`.
Every one of these is loaded by the driver loop, one at a time, as
`flow_next.sh` names it.

| File | Directory | chars | est. tokens |
| --- | --- | ---: | ---: |
| `SKILL.md` | `skills/execute` | 5,257 | 1,315 |
| `phases.json` | `skills/execute` | 1,665 | 417 |
| `phase-0.md` | `skills/team-sprint/references/phases` | 18,022 | 4,506 |
| `phase-1.md` | ″ | 5,044 | 1,261 |
| `phase-2.md` | ″ | 14,793 | 3,699 |
| `phase-3.md` | ″ | 7,818 | 1,955 |
| `phase-4.md` | ″ | 8,318 | 2,080 |
| `phase-5.md` | ″ | 6,770 | 1,693 |
| `phase-6.md` | ″ | 6,096 | 1,524 |
| `phase-7.md` | ″ | 11,138 | 2,785 |
| `phase-8.md` | `skills/execute/phases` | 2,694 | 674 |
| `phase-9.md` | `skills/execute/phases` | 1,883 | 471 |
| **spine total** | | **89,498** | **~22,375** |
| the same plan | | 5,107 | 1,277 |
| **spine + plan** | | **94,605** | **~23,652** |

**11,868 vs 94,605 chars — an 87.5% reduction.**

### crewforge5 `execute` — the shared reference docs on top

The phase docs do not stand alone: each ends with a "read these" list, and
phases 3–7 each defer their node-executor contract to a shared doc. These are
the ones the phase docs above actually send you to, all under
`skills/team-sprint/references`.

| File | chars | est. tokens | pulled in by |
| --- | ---: | ---: | --- |
| `phases/phase-execute.md` | 10,717 | 2,680 | phases 3, 4, 5, 6, 7 |
| `state-schema.md` | 17,584 | 4,396 | phases 0, 2, 3, 5, 6, 7 |
| `sendmessage-protocol.md` | 10,115 | 2,529 | phases 0, 2, 3, 4, 5, 7 |
| `subskill-hooks.md` | 8,228 | 2,057 | phases 0, 1, 2, 3, 4, 5, 6, 7 |
| `plan-path-convention.md` | 2,588 | 647 | phase 0 |
| `reviewer-contract.md` | 2,246 | 562 | phases 1, 2 |
| **total** | **51,478** | **~12,870** | |

With these, crewforge5's `execute` corpus is **146,083 chars ≈ 36,521 est.
tokens**, and the reduction is **91.9%**. The 87.5% figure in the summary table
is the conservative one: it counts only what the manifest names outright.

Not counted on either side, because they are conditional on the run: the
`adversarial-review` skill body (23,764 chars) that phase 1's loop reaches for,
the crew agent definitions phase 2 generates, and the four `rules/*.md` files a
session hook injects. Counting them would widen the gap, not narrow it.

### The other two commands

Same method, whole-flow doc set against the single SKILL.md that replaces it.

| Flow | crewforge5 (SKILL.md + manifest + phase docs) | mad-dreamer (SKILL.md) | Change |
| --- | ---: | ---: | ---: |
| `plan` | 18,689 chars (10 files) | 5,564 chars (1 file) | −70.2% |
| `init` | 20,702 chars (10 files) | 5,333 chars (1 file) | −74.2% |
| `execute` | 89,498 chars (12 files) | 6,761 chars (1 file) | −92.4% |

### Reproducing this

```sh
CF5="$HOME/.claude/plugins/cache/crewforge5/crewforge5/0.4.2"
MD="$HOME/mad-dreamer"
tok() { python3 -c 'import math,sys;print(math.ceil(int(sys.argv[1])/4))' "$1"; }

c=$(cat "$MD/skills/execute/SKILL.md" "$MD/tests/fixtures/plan-toy-1.md" | wc -c)
echo "mad-dreamer  chars=$c tokens=$(tok "$c")"

c=$(cat "$CF5/skills/execute/SKILL.md" "$CF5/skills/execute/phases.json" \
        "$CF5"/skills/team-sprint/references/phase?/phase-[0-7].md \
        "$CF5"/skills/execute/phases/phase-[89].md \
        "$MD/tests/fixtures/plan-toy-1.md" | wc -c)
echo "crewforge5   chars=$c tokens=$(tok "$c")"
```

## 2. Always-on plugin cost — measured

Literal output of `claude --plugin-dir <repo> plugin details mad-dreamer`, run
2026-08-19:

```
mad-dreamer 0.1.0
Component inventory
  Skills (3)  execute, init, plan
  Agents (0)
  Hooks (0)
  MCP servers (0)
  LSP servers (0)

Projected token cost
  Always-on:   ~269 tok   added to every session

Per-component (rounded)
  component  always-on  on-invoke
  execute          ~80      ~2.7k
  plan             ~80      ~2.2k
  init            ~100      ~2.1k
```

Literal output of `claude plugin details crewforge5`, same machine, same day
(per-component table elided; the inventory and the projection are the point):

```
crewforge5 0.4.2
Component inventory
  Skills (32)  ac-validate, adhd, adversarial-review, agent-rectifier,
               agent-validator, claude-config, code-reviewer, context-hygiene,
               drawio, execute, graphify, grill-me, init, master-plan, plan,
               playwright-cli, plugin-forge, pre-commit-review-fleet,
               self-improve, skill-rectifier, skill-validator, sprint-init,
               sprint-watchdog, team-feature, team-sprint, team-sprint-planner,
               team-sprint-pm-lense, team-sprint-sa-lense, tech-debt-audit,
               token-slim, ui-polish-loop, use-repo-code
  Agents (7)  architect-reviewer, crew-factory, stack-surveyor, code-reviewer,
              scrum-master, boundary-reviewer, sprint-watchdog
  Hooks (3)  SessionStart, PreToolUse, PostToolUse  (harness-only — no model context cost)
  MCP servers (0)
  LSP servers (0)

Projected token cost
  Always-on:   ~3,335 tok   added to every session
```

**~3,335 → ~269 always-on tokens, a 91.9% reduction**, paid in every session
whether or not a sprint runs. The comparison is not apples-to-apples in scope:
crewforge5 ships 32 skills, and only three of them are the flows benchmarked
here. What the number does say is what a machine pays to *have* each plugin
installed, which is the cost that never shows up in a run transcript.

Both figures are the harness's own estimates and the tool says so.

## 3. Gate parity — measured

"Zero invariant-gate regressions" means: for every gate upstream enforces
mechanically, mad-dreamer enforces the same thing, and the process gates it drops
were dropped on purpose. Upstream's mechanical gates live in
`skills/execute/scripts/phase_gate.sh` — only phases 0, 1, 8 and 9 have one;
2–7 are judgment gates the phase docs state and no script decides.

| Upstream mechanical gate | mad-dreamer equivalent | Verdict |
| --- | --- | --- |
| Phase 0 — plan-path contract (`validate_plan_path.sh`) | `gate.sh plan-contract` (same vendored script) | **kept** |
| Phase 0 — required sub-skills present | — | **dropped**: mad-dreamer has no sub-skills to be absent |
| Phase 1 — adversarial stamp grep | `gate.sh stamp`, the identical regex | **kept** |
| Phase 1 — unfolded-findings check | `gate.sh stamp` + `plan` forbidding a leftover marker | **kept** |
| Phase 8 — integration diagram artefact | — | **dropped**: process gate, named in the README |
| Phase 9 — learning-ledger ceiling | — | **dropped**: process gate, named in the README |
| Phase 3 — tests + coverage (judgment) | `gate.sh tests [--coverage]`, mechanical | **kept and hardened** |
| Phase 5/7 — findings closed (judgment) | `gate.sh findings`, mechanical | **kept and hardened** |
| — | `gate.sh preflight` (git, tooling, clean tree) | **added** |
| — | `gate.sh report` (state readback) | **added** |

Two of upstream's judgment gates became scripts here, which is the opposite of a
regression: `tests`, `coverage` and `findings` are decided by exit code rather
than by an agent's assurance.

### mad-dreamer's gates, run against the shipped fixtures

Literal output, `bash scripts/gate.sh …` from the repo root:

```
$ gate.sh preflight --allow-dirty        STATUS=OK  TOOLS=ok GIT_REPO=yes TREE=clean
$ gate.sh plan-contract  plan-toy-1.md   STATUS=OK  PLAN_PATH=OK STORIES=3 NODES=3 EDGES=2
$ gate.sh plan-contract  golden-template-1.md
                                         STATUS=OK  PLAN_PATH=OK STORIES=6 NODES=6 EDGES=3
$ gate.sh stamp          plan-toy-1.md   STATUS=OK  REVIEW_STATUS=clean ROUNDS=2 MODE=mad-dreamer
$ gate.sh stamp          unstamped-plan-1.md
                                         STATUS=FAIL REASON=no-adversarial-stamp
$ gate.sh findings       findings-clean.md
                                         STATUS=OK  CRITICAL=0 HIGH=0 MEDIUM=1 LOW=1 MALFORMED=0
$ gate.sh findings       findings-blocking.md
                                         STATUS=FAIL CRITICAL=1 HIGH=2 REASON=open-blocking-findings
$ gate.sh tests                          STATUS=OK  TEST_CMD='bats tests' EXIT_CODE=0
$ gate.sh report                         STATUS=FAIL REASON=state-missing   (no run in progress)
```

`golden-template-1.md` is upstream's own contract fixture, vendored unmodified.
It asserts 6 stories, 6 graph nodes and 3 edges; the vendored chain returns
exactly that. The negative cases matter as much as the positive ones: a gate
that only ever prints OK is not a gate.

### The same fixture plan through upstream's gates

Re-run 2026-08-19 in a throwaway `mktemp -d` git repo, with crewforge5's root
environment variable pointed at the pinned 0.4.2 cache, the plan seeded into
execute's state through its own state driver, then:

```
$ phase_gate.sh 0     STATUS=PASS   (exit 0)
$ phase_gate.sh 1     STATUS=PASS   (exit 0)
```

A plan written by `/mad-dreamer:plan`, carrying `mode=mad-dreamer`, passes
upstream's plan-path contract and its adversarial-stamp gate unmodified. The
interop guarantee is not a design intention; it is a re-run.

## 4. End-to-end runs — attempted, one finished, one did not

Both flows were given the same instruction in a headless session, in separate
`mktemp -d` scratch repos seeded from `tests/fixtures/ground-repo` with the
fixture plan at `docs/plan-toy-1.md`:

```sh
/usr/bin/time -f 'WALL_SECONDS=%e' -o wall.txt \
  timeout 900 claude --dangerously-skip-permissions \
    [--plugin-dir <mad-dreamer>] --output-format stream-json --verbose \
    -p 'Run /<plugin>:execute on docs/plan-toy-1.md. Coverage 60, merge into main when green.' \
    > run.jsonl
```

Tool calls counted as `"type":"tool_use"` blocks in `run.jsonl`, split by whether
the emitting event carried a `parent_tool_use_id` (i.e. came from a sub-agent).

| | crewforge5-full | mad-dreamer |
| --- | --- | --- |
| Outcome | **timed out at 900 s, inside Phase 0 of 10** | **completed: 3 story commits merged** |
| Wall seconds | 900.5 (cap) | **727.5** |
| Tool calls, lead session | 24 | 34 |
| Tool calls, inside sub-agents | 34 | 38 |
| Tool calls, total | 58 | 72 |
| Agent spawns | 3 (1 lead + 2 nested) | 3 (one review per story) |
| Turns | 26 | 36 |
| API cost, USD | 4.95 | 3.59 |
| Commits produced | 0 | 4 (3 stories + merge) |

**Why these do not divide into a percentage.** The crewforge5 run spent its
entire budget on Phase 0 — tooling probes, repomix pack, code-graph build, and a
`crew-factory` spawn that was still re-validating its generated developer agent
toward grade A when the clock ran out. It never reached the worktree, let alone a
test. mad-dreamer's 72 calls bought three RED-GREEN-review-commit cycles and a
merge; crewforge5's 58 bought a configured but unstarted sprint. Dividing one by
the other would produce a number that means nothing, and reporting it as "−60%"
would be a lie in the flattering direction.

What can be said honestly from these two runs:

- mad-dreamer reached a merged commit on this fixture in **12 minutes for $3.59**.
- crewforge5-full had not reached its first test after **15 minutes and $4.95**,
  and was still in setup. Its full run would plainly cost several multiples of
  mad-dreamer's, but *several multiples* is an observation, not a measurement.
- No `AskUserQuestion` call blocked either run: both flows read their run-shape
  answers ("Coverage 60, merge into main when green") straight out of the prompt,
  which is what their own skills tell them to do. The headless blocker anticipated
  before the runs did not materialise. One honest caveat follows from that: in
  headless mode mad-dreamer treated the prompt's "merge into main when green" as
  the explicit merge confirmation its step 6 requires. Interactively that step is
  a real question, and the run is one turn longer.

### Filling the gap

To turn the tool-call row into a measurement, a human needs to let the
crewforge5 run finish. In a scratch repo prepared exactly as above:

```sh
cd "$(mktemp -d)" && git init -q -b main .
cp -r <mad-dreamer>/tests/fixtures/ground-repo/. . && mkdir -p docs
cp <mad-dreamer>/tests/fixtures/plan-toy-1.md docs/
printf '[tool.pytest.ini_options]\npythonpath = ["src"]\naddopts = "--cov=src --cov-report=term"\n' > pyproject.toml
git add -A && git commit -qm "toy service"

/usr/bin/time -f 'WALL_SECONDS=%e' -o wall.txt \
  timeout 7200 claude --dangerously-skip-permissions \
    --output-format stream-json --verbose \
    -p 'Run /crewforge5:execute on docs/plan-toy-1.md. Coverage 60, merge into main when green.' \
    > run.jsonl

grep -o '"type":"tool_use"' run.jsonl | wc -l   # tool-call count
cat wall.txt                                    # wall time
git log --oneline main                          # proof it actually finished
```

Only a run that ends in three story commits on `main` counts. Until then this
row stays **UNMEASURED** and the ≥60% tool-call target stays unverified.

## 5. Output-artifact diff — measured

What each run left behind in the user's checkout.

| | crewforge5-full (partial run) | mad-dreamer (complete run) |
| --- | --- | --- |
| Commits on the target branch | none | `2d84a26` feat(1), `8187184` feat(2), `ea7359f` refactor(3), `4302ee3` merge |
| Sprint state | `.crewforge5/execute/state.json` + `.team-sprint/sprints/sprint-plan-toy-1/state.json` | `.mad-dreamer/state.json`, inside the worktree, removed with it |
| Generated crew | `.claude/agents/`, `.claude/crews/`, `.claude/rules/` (20 KB) | none |
| Recon caches | `.repomix-output.xml` (196 KB), `.codegraph/` (160 KB), `.recon/` | none |
| Per-story artefacts | *not reached in the timed-out run.* Its phase docs declare `diff-<id>.patch`, `reviews-<id>-round-<N>.md`, `commit-msg-<id>.txt`, `stories.json`, `graph.json`, `plan-final.md`, `sprint-report.md` under the sprint dir | `findings-<id>.md`, `commit-msg-<id>.txt` under the worktree's `.mad-dreamer/execute`, removed on clean finish |
| Sprint-level artefacts | *not reached.* Declared: `diff-sprint.patch`, `reviews-sprint-round-<N>-<reviewer>.md`, integration diagram, learning ledger | none |
| Left in the tree after a clean finish | the sprint directory — its own docs make it the resume contract, so it is meant to persist | **nothing** — measured: the worktree was removed and the run artefacts went with it |

Rows marked *not reached* are read off crewforge5's phase docs, not off the
timed-out run. Everything in the mad-dreamer column is what the completed run
actually left on disk.

The two shapes that must match, and do:

**The plan file.** One markdown file, the same contract, the same stamp line.
Proved in §3 by running upstream's phase 0 and 1 gates over it.

**The story commit.** `git log` reads identically either side. Literal
`git log -1 --format=%B 8187184` from the mad-dreamer run:

```
feat(2): Validate on load

Story: 2 — Validate on load
Plan: docs/plan-toy-1.md

Acceptance criteria met:
- `load_config` coerces each parsed value through the schema, so `port` is an int.
- An unknown key raises `SchemaError` naming that key, before any value is returned.
- The existing defaults test still passes unchanged: a config that sets only `port` still yields `workers == 1`.

Gates: tests ✓ | coverage ✓ | review ✓

Co-Authored-By: Claude <noreply@anthropic.com>
```

`git log --oneline --grep '^Story: 2'` finds it, which is the lookup upstream's
per-story tooling depends on.

**What mad-dreamer does not produce:** the sprint report, the integration
diagram, the distilled learning ledger, the per-round review transcripts, and
the durable sprint directory. If you need a paper trail after the fact rather
than a merge, that absence is the cost.

## 6. The trade-off, stated plainly

**Thresholded review catches fewer MEDIUM and LOW findings than a six-round
loop.** mad-dreamer re-opens a review only while a CRITICAL or HIGH finding is
open — at most two fix rounds in `execute`, at most three review rounds in
`plan`. MEDIUM and LOW findings are reported and deferred, never applied and
never re-checked. A full crewforge5 phase-7 fleet runs several reviewers over the
sprint diff and iterates until the round gate is satisfied, so it surfaces a
longer tail. On the run above, mad-dreamer's per-story reviewer raised a MEDIUM
worth taking — a test asserting on `inspect.getsource(...)`, which the reviewer
demonstrated was gameable — and by protocol it was reported, not fixed. That is
the shape of what you give up: real findings, correctly classified as
non-blocking, that nobody comes back to.

Two further asymmetries, so the trade is not undersold:

- **No fresh crew.** crewforge5 generates and grade-A validates a
  language-matched agent crew for the repo. mad-dreamer spawns one general
  reviewer per story. On an unusual stack that difference will show.
- **No durable trail.** Everything in §5's right-hand column that says "removed
  with the worktree" is evidence that no longer exists after a green run.

### The escape hatch

The interop guarantee makes the trade reversible after the fact, because a
mad-dreamer plan *is* a crewforge5 plan. Both cases are one line:

```
# stakes rose before the sprint: run the full adversarial loop over the plan
/crewforge5:plan review docs/<id>-<slug>.md

# stakes rose after the sprint: run the full phase-7 review fleet over the branch
/crewforge5:execute docs/<id>-<slug>.md
```

Nothing needs converting, re-stamping or re-formatting: §3 shows the plan passing
upstream's phase 0 and phase 1 gates unmodified, and §5 shows the story commits
already carry the `Story: <id> — ` line upstream's tooling greps for. The
default is fast; the expensive path is available per-plan, on the days it is
worth it.

## Appendix — marketplace listing entry (draft, not published)

Drafted here rather than in the README, deliberately: a listing is a claim made
to strangers, and it should sit next to the evidence that backs it. Nothing in
it may outrun this file. **Not published — this is copy for review.**

```json
{
  "name": "mad-dreamer",
  "source": "https://github.com/linusamcm-source/mad-dreamer",
  "description": "Three commands — init, plan, execute — that take a goal to a merged commit. Keeps every invariant gate: plan-contract parse, adversarial stamp, findings closed at threshold, tests green, coverage met, clean-tree preflight, retention safety. Drops the process ceremony: no per-phase state machine, no ledger distillation, no integration diagram. ~269 always-on tokens; the execute flow loads one page instead of twelve.",
  "version": "0.1.0",
  "license": "MIT",
  "keywords": ["agents", "sprint", "tdd", "planning", "orchestration"]
}
```

Listing blurb, ~60 words:

> A fast-path sprint plugin. `/mad-dreamer:plan` turns a goal into a
> contract-valid, adversarially stamped plan with two question batches, not
> twenty. `/mad-dreamer:execute` drives it to a merged commit through an isolated
> worktree, per-story TDD and a coverage floor. `/mad-dreamer:init` slims your
> Claude config in one measured pass. Interoperable with crewforge5 plans in both
> directions; no runtime dependency on it.

Claims in that copy and where each is substantiated: "one page instead of twelve"
— §1. "~269 always-on tokens" — §2. "keeps every invariant gate" — §3.
"interoperable in both directions" — §3, upstream gates re-run. Deliberately
absent: any tool-call or speed percentage, because §4 does not support one yet.
