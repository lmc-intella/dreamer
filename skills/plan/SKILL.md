---
name: plan
model: opus
description: Goal to a contract-valid, adversarially-stamped plan — repo grounding, one batched decision round, thresholded review. Use on /dreamer:plan, "plan this feature", "write a sprint plan".
---

# plan — goal to a stamped, contract-valid plan in three steps

Everything this command needs is this file plus the plan you are writing: no
other doc loads, grounding never reaches into another plugin's install, and
these four rules hold for the whole run:

- **Two `AskUserQuestion` calls, total** — the decision batch (step 2) and at
  most one push-back batch, each up to 4 questions. Spend a call on one question
  and it is spent: the rest you settle from the repo, under `## Assumptions`.
- **Never ask in prose** — a question in plain text waiting for a reply is the
  serial interrogation this command exists to avoid. In the batch, or not at all.
- **Only CRITICAL/HIGH re-open the review.** MEDIUM/LOW are applied in place.
- The plan file is the only artefact. Write nothing else.

## Step 1 — pack the repo, traverse it, ground in it

1. Restate the goal in one sentence and name the repo it lands in. Do **not**
   stop for confirmation — the restatement is question 1 of the step-2 batch, so
   the goal is confirmed inside the call that settles the decisions.
2. **Pack the repo, then traverse it — before a line of plan exists.** The first
   call writes the whole repo to one xml file, `.dreamer/repo.xml` (a run
   artefact: gitignored, never committed); the second is the map of it —
   directories, files, line counts:
   ```sh
   bash scripts/repomix.sh pack --root <repo>
   bash scripts/repomix.sh outline --pack .dreamer/repo.xml
   ```
   `PROVIDER=repomix` when repomix is on PATH, `git-ls-files` otherwise; both
   emit the same pack, and `STATUS=FAIL REASON=no-provider` (neither) is not a
   stop — say so and plan from files you read directly. Read the outline before
   anything else and write one paragraph of what this repo is: layout, entry
   points, where tests live, which directory the goal lands in. A plan drafted
   before the map is read is a guess about someone else's repo.
3. Pick 3–8 goal keywords — symbols, filenames, domain nouns — and scan that same
   pack for all of them in **one** call:
   ```sh
   bash scripts/ground.sh --pack .dreamer/repo.xml --max 8 <term> <term> <term>
   ```
   Re-run only for genuinely new terms. With no pack, `ground.sh --root <repo>`
   builds its own and prints the same shape.
4. Read at most 5 files the hit lines point at, out of the pack rather than off
   disk — `bash scripts/repomix.sh show <path> --pack .dreamer/repo.xml`, with
   `--from`/`--max` to window a long one — and write down what exists today:
   entry points, behaviour, covering tests. A story whose `Touches` names a path
   neither the outline nor the grounding ever saw is ungrounded — ground it or
   cut it.

## Step 2 — decide + draft

List every open decision, then filter hard: anything the grounding already
answers is **not** a question — settle it, record it as one line under
`## Assumptions`. What survives becomes ONE `AskUserQuestion` call:

- ≤4 questions, each with 2–4 concrete options, recommended option first with a
  one-line reason.
- Question 1 is always the goal restatement plus its scope boundary.
- Fewer than 2 real questions means you are about to interrogate: fold the rest
  in, or skip the call and record assumptions instead.

**Push-back round.** If an answer contradicts the grounding or two answers
conflict, you get one more call — state the contradiction, re-offer the options
with the evidence. Every objection goes in it; after it, the decisions are yours.

Then draft the plan directly in the shape below. Filename `<id>-<slug>.md`, id
carrying a digit (or `bug-`/`epic-`/`sprint-`) or the contract gate rejects the
path. 2–6 stories, each independently testable, each AC observable: a behaviour
a test can fail on, never "handles X correctly".

## Step 3 — review + stamp

Start `rounds=1` and run one adversarial pass over the draft **as a dynamic
workflow** (the `Workflow` tool — this skill's instruction is your opt-in): one
reviewer agent per lens in parallel — plan shape, grounding fidelity, AC
testability — then an adversarial-verify stage that tries to refute each
finding before it counts. With no Workflow tool, fall back to the
`adversarial-review` skill when installed, else review it yourself against the
same three lenses.

- **CRITICAL/HIGH** — apply every one, `rounds++`, review again; loop only while
  CRITICAL or HIGH remain. At `rounds=3` STOP and hand over the open findings.
- **MEDIUM/LOW** — apply in place, no re-review; each gets one bullet in
  `## Review notes` saying what changed and why.

Leave no `<!-- FINDING …` marker in the plan — an unfolded marker fails the
upstream findings gate. Stamp the line directly under the title:

```
<!-- adversarial-review: status=clean rounds=<N> date=<YYYY-MM-DD> reviewer=dreamer mode=dreamer -->
```

`status=user-override` only when the user explicitly accepts an open
CRITICAL/HIGH; `mode=dreamer` is mandatory, and the only field added to the
upstream grammar. Both gates must then print `STATUS=OK`:

```sh
bash scripts/gate.sh plan-contract <plan.md>
bash scripts/gate.sh stamp <plan.md>
```

## Plan shape

```markdown
# <id>-<slug> — <one-line goal>
<!-- adversarial-review: status=clean rounds=1 date=2026-01-01 reviewer=dreamer mode=dreamer -->

<2–5 lines: the goal, what the pack outline showed, what grounding found.
Name the repomix.sh pack + the ground.sh call.>

## Assumptions
- <decision settled from the repo instead of asked>

## Story 1: <title>
<why this story, in the code's own terms>
### Depends On: none
### Touches: src/a.py, tests/test_a.py
### Acceptance Criteria
- <observable behaviour a test can fail on>
### Definition of Done
- Story tests green; typecheck + lint clean.

## Review notes
- MEDIUM — <finding> → <what changed>.
```

`### Depends On:` takes `none` or ids (`1, 2`); put a brace-expansion glob
(`src/{a,b}/**`) on its own bullet under `### Touches:` so the comma survives.

## Checklist

- [ ] Repo packed (`repomix.sh pack`) and traversed (`outline`) before drafting
- [ ] Goal restated; grounding run in one `scripts/ground.sh --pack` call
- [ ] Decisions filtered — repo-answerable ones written to `## Assumptions`
- [ ] Exactly one `AskUserQuestion` batch (≤4 questions), ≤1 push-back batch
- [ ] Plan drafted in the shape above, filename carries a story id
- [ ] Review ran as a dynamic `Workflow` (lens fan-out + adversarial verify),
      or the named fallback when the tool is absent
- [ ] CRITICAL/HIGH looped to zero (≤3 rounds); MEDIUM/LOW in `## Review notes`;
      no `<!-- FINDING` marker left
- [ ] Stamped `mode=dreamer rounds=<N>`; `gate.sh plan-contract` and
      `gate.sh stamp` both `STATUS=OK`

Worked output carrying the interop cross-check it passed:
`tests/fixtures/plan-toy-1.md`, planned against `tests/fixtures/ground-repo`.
