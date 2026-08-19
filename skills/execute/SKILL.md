---
name: execute
model: opus
description: Stamped plan in, merged commit out — isolated worktree, per-story TDD, tests and coverage gate, one commit per story. Use on /dreamer:execute, "run this plan", "execute the sprint".
---

# execute — stamped plan in, merged commit out

Two documents load for the whole run: this page and the plan. No phase doc, no
integration diagram, no distillation pass — a third markdown file is the bug.

`$MD` = this plugin's root (`$CLAUDE_PLUGIN_ROOT`, else two levels above this
file). `$PLAN` = the plan path. `$COV` = the coverage floor, **60 by default**.
`$TARGET` = the landing branch, `main` by default. Flags are read off the
invocation, never asked for in a dialogue: `--coverage <pct>` moves the floor,
`--target <branch>` the branch, `--merge` (default) lands, `--pr` opens a PR.

**Budget: one agent spawn per story** — a single combined security + correctness
review, not a lens fleet and not one agent per concern. Every spawn is
block-collect-close: spawn it, wait for it, read its report, act on it, say what
you did. A child whose report you never read did not run. **Never** force-push,
rewrite history, or touch `$TARGET` without the explicit confirmation in step 6.

## Checklist

- [ ] **1. Intake — three gates, this order, from the user's checkout.**
      ```sh
      bash "$MD/scripts/gate.sh" preflight
      bash "$MD/scripts/gate.sh" plan-contract "$PLAN"
      bash "$MD/scripts/gate.sh" stamp "$PLAN"
      ```
      Any `STATUS=FAIL` stops the run: quote the `REASON=` line and stop. The
      stamp gate is a hard STOP with **no escape** — no flag, no prompt, no "the
      user says it is fine". An unstamped or unclean plan goes back to
      `/dreamer:plan`; it does not run here.
- [ ] **2. Read the plan once** for story ids, titles, acceptance criteria,
      `Depends On`, `Touches`. `plan-contract` already proved the graph acyclic,
      so run the stories in plan order — no scheduler, no waves.
- [ ] **3. Isolated worktree** — sibling directory, branch `sprint/<name>`, the
      shape a crewforge5 sprint uses. Nothing after this writes to the user's
      checkout until step 6; the exclude line keeps run artefacts uncommitted.
      ```sh
      MAIN_TREE="$(git rev-parse --show-toplevel)"
      WT_NAME="$(basename "${PLAN%.md}")"
      WORKTREE_PATH="$MAIN_TREE/../$(basename "$MAIN_TREE")-$WT_NAME"
      SPRINT_BRANCH="sprint/$WT_NAME"
      git worktree add -b "$SPRINT_BRANCH" "$WORKTREE_PATH" "$TARGET"
      cd "$WORKTREE_PATH"
      EX="$(git rev-parse --git-common-dir)/info/exclude"
      grep -qxF '.dreamer/' "$EX" || printf '.dreamer/\n' >>"$EX"
      ```
- [ ] **4. Per-story loop** (below), once per story, in order. Do not open a
      story until the one before it is committed.
- [ ] **5. Full suite, then the record.** `gate.sh tests --coverage "$COV"` over
      the whole worktree must print `STATUS=OK`. Write `.dreamer/state.json`
      — `{"run_id":"execute-<UTC ISO8601>","plan":"<$PLAN>","mode":"execute",`
      `"gates":{"preflight":"OK","plan-contract":"OK","stamp":"OK","tests":"OK",`
      `"coverage":"OK","review":"OK"}}` — and run
      `bash "$MD/scripts/gate.sh" report` from the worktree.
- [ ] **6. Land.** `--pr`: `git push -u origin "$SPRINT_BRANCH"`, then open the
      PR; `$TARGET` is never written. `--merge`: state the branch, its commit
      count and the target, get an explicit yes, then `git merge --no-ff
      "$SPRINT_BRANCH"` from `$MAIN_TREE`. No confirmation, no merge.
- [ ] **7. Close** — `git worktree remove "$WORKTREE_PATH"`, then report the
      per-story commits, final coverage, deferred MEDIUM/LOW findings and the
      spawn count.

## The per-story loop

`$SID` = the story id the plan contract reports (`1`, `mech-9`).
`$ART` = `.dreamer/execute` inside the worktree.

1. **RED — one failing test per AC, before a line of implementation.** Write a
   test for every acceptance criterion into the story's `Touches` test files,
   then `bash "$MD/scripts/gate.sh" tests`. It **must** print `STATUS=FAIL` with
   `REASON=tests-failed`. `STATUS=OK` here means the tests you just wrote cannot
   fail — the AC is not observable. STOP with `REASON=no-red`, naming the story,
   the AC and `$WORKTREE_PATH`. Do not implement your way past it, and do not
   soften the AC until it is testable.
2. **GREEN — implement the story and nothing else**, inside its `Touches` paths,
   then `bash "$MD/scripts/gate.sh" tests --coverage "$COV"`. `STATUS=OK`, or the
   story is not done. `REASON=coverage-below-threshold` is a missing test, never
   a floor to lower — `$COV` is fixed at intake. `REASON=no-coverage-figure`
   means the repo's test command prints no percentage: say so and re-run without
   `--coverage` rather than invent a number.
3. **Review — one spawn, blocked on, collected, closed.** One agent, security and
   correctness in the same pass, over this story's diff only. It writes
   `FINDING id=<id> severity=<CRITICAL|HIGH|MEDIUM|LOW> status=<open|resolved>`
   lines to `$ART/findings-$SID.md`. Wait for it, read the report, then
   `bash "$MD/scripts/gate.sh" findings "$ART/findings-$SID.md"`. Fix every
   CRITICAL/HIGH and re-run step 2's gate and this one. MEDIUM/LOW are reported,
   not applied. Two fix rounds is the cap; at a third, STOP with the open findings.
4. **Commit — exactly one per story**, staging only that story's paths:
   `git add <Touches paths>` then `git commit -F "$ART/commit-msg-$SID.txt"`,
   holding a crewforge5 story commit's shape so `git log` reads the same either
   side:
   ```
   <type>(<SID>): <story title>

   Story: <SID> — <story title>
   Plan: <$PLAN>

   Acceptance criteria met:
   - <ac bullet, verbatim from the plan>

   Gates: tests ✓ | coverage ✓ | review ✓

   Co-Authored-By: Claude <noreply@anthropic.com>
   ```
   `<type>` is a Conventional Commits type — `feat` unless the story is plainly a
   `fix`/`refactor`/`docs`/`chore`. The `Story: <SID> — ` line is load-bearing:
   `git log --grep '^Story: <SID>'` is how a story commit is found. One commit
   per story; no `wip` commits left behind on the branch.

## Stop conditions

Each ends the run where it stands. The worktree is removed **only** on a clean
finish; on any STOP it stays as it is and `$WORKTREE_PATH` goes in the stop
message's first line, so the work is inspectable.

- Any intake gate `STATUS=FAIL` — the worktree does not exist yet.
- `REASON=no-red` — an AC no test can fail on. Stop before implementing it.
- Tests or coverage still failing after the story's fixes.
- CRITICAL/HIGH findings open after two fix rounds.
- The user declines the merge, or `$TARGET` would be written without one.
