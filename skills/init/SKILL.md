---
name: init
model: opus
description: Audit and slim a Claude config in one measured pass — measure, one batched skill validator and one batched agent validator, apply CRITICAL/HIGH, re-measure, report. Use on /dreamer:init, "audit my Claude config", "slim my skills".
---

# init

Three steps, two agent spawns, two gates. Measure the config, audit it in one
batch per component kind, apply only the CRITICAL/HIGH fixes, re-measure, report
the delta. Everything you need is on this page; do not go looking for more.

**Budget:** ≤3 agent spawns per run. Two are planned (skills, agents); the third
is a reserve for one re-validation of a component whose fix you are unsure of.
Spending a fourth is a bug, not a judgement call.

`$ROOT` = the config root under audit (default `~/.claude`; a plugin repo or any
tree with `CLAUDE.md`, `skills/`, `agents/` also works). `$MD` = this plugin's
root — `$CLAUDE_PLUGIN_ROOT` if set, otherwise the directory two levels above
this file. Work with `cd "$ROOT"` for every command below.

## Checklist

- [ ] **1. Preflight.** `bash "$MD/scripts/gate.sh" preflight --allow-dirty`.
      A config root is a working directory, so dirty is expected; the gate is
      here to confirm git, `python3` and `jq` exist, which is what makes a revert
      possible. On `REASON=not-a-git-repo`, STOP: say so and offer to continue
      with per-file `.bak` revert only, which has no whole-run undo.
- [ ] **2. Measure (before).** `python3 "$MD/scripts/measure.py" "$ROOT" > .dreamer/init/before.json`
      (`mkdir -p .dreamer/init` first). JSON: per-file `chars`, `lines`,
      `est_tokens`, per-skill `support_chars`, plus `by_kind` and `totals`.
      Token figures are a `chars / 4` estimate, not a tokenizer — quote them as
      estimates and lean on the char delta as the real number.
- [ ] **3. Audit — exactly two spawns.** One agent over **all** skills, one over
      **all** agents. Never one spawn per component. Give each the file list from
      step 2 and this contract: return one block per component with
      `GRADE=A..F`, then `FINDING id=<id> severity=<CRITICAL|HIGH|MEDIUM|LOW>
      file=<path> — <what and the exact fix>`. CLAUDE.md is audited inline by
      you, in the same pass, with no spawn.
- [ ] **4. Triage in one pass.** CRITICAL + HIGH → apply now. MEDIUM + LOW →
      deferred recommendations, listed verbatim in the report, not applied. Do
      not loop: one audit, one triage, one apply.
- [ ] **5. Apply, every edit through the retention gate.** Per file, no
      exceptions, no batching two files into one gate run — see below.
- [ ] **6. Measure (after).** `python3 "$MD/scripts/measure.py" "$ROOT" > .dreamer/init/after.json`.
- [ ] **7. Report and close.** Write `.dreamer/init/report.md` from the
      template below, write `.dreamer/state.json`, then
      `bash "$MD/scripts/gate.sh" report`. `STATUS=OK` closes the run.

## The retention gate is not optional

A slim is judged by how much shorter it got, and the lines worth the most tokens
are usually the ones worth keeping. Every edit runs this exact sequence:

```sh
cp "$f" "$f.bak"                                   # original, before any edit
# ...apply the fix to "$f"...
bash "$MD/scripts/vendor/retention_gate.sh" "$f.bak" "$f"
```

- Exit **0** — every directive, command, path, version and error string survived.
  `rm "$f.bak"`. Record the finding as applied.
- Exit **1** — a breach. `mv "$f.bak" "$f"` immediately: the edit is **reverted**,
  not patched, not re-argued. Record the finding as `REVERTED` in the report with
  the gate's `FAIL:` lines quoted verbatim, and move to the next file. A second
  attempt at the same file costs an agent spawn you have not budgeted.

Never hand the gate a file you have already reverted or overwritten — it compares
two files and cannot know which one you meant.

## `.dreamer/state.json`

```json
{ "run_id": "init-<UTC ISO8601>", "plan": "none", "mode": "init",
  "gates": { "preflight": "OK", "retention": "OK" } }
```

`retention` is `OK` only when zero edits were reverted; otherwise `FAIL`.

## Report template — `.dreamer/init/report.md`

```md
# init report — <UTC ISO8601>

Config root: <$ROOT>   Agent spawns: <n>/3 (skills, agents)

## Size

| | chars | est. tokens (chars/4) | files |
|---|---|---|---|
| before | | | |
| after  | | | |
| delta  | | | |

Per kind (instructions / skill / agent), before → after chars.

## Grades

| component | kind | grade | chars before | chars after |

## Applied (CRITICAL/HIGH)

- `<id>` <severity> `<file>` — <fix>, retention gate PASS.

## Reverted by the retention gate

- `<id>` <severity> `<file>` — <fix attempted>. Gate said:
  `FAIL: directive lost: ...`. File restored from `.bak`; nothing was applied.

## Deferred (MEDIUM/LOW) — recommendations, not applied

- `<id>` <severity> `<file>` — <what and the fix>.
```

## Stop conditions

- Preflight FAIL other than a dirty tree — STOP, report the `REASON=` line.
- A finding whose fix needs a decision only the user can make — leave it deferred
  with the question stated; do not guess and do not open a dialogue mid-run.
- Three spawns used and work remaining — STOP and report what is unaudited.
  Under-reporting coverage is honest; a fourth spawn is not.
