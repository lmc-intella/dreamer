---
name: execute
model: opus
description: Stamped plan in, merged commit out — isolated worktree, per-story TDD, tests and coverage gate, one commit per story. Use on /dreamer:execute, "run this plan", "execute the sprint".
---

# execute — stamped plan in, merged commit out

Two documents load for the whole run: this page and the plan; the repo itself
arrives as one xml pack (step 4). No phase doc, no integration diagram, no
distillation pass — a third markdown file is the bug.

`$MD` = the plugin root (`$CLAUDE_PLUGIN_ROOT`, else two levels up). `$PLAN` =
the plan path. `$COV` = the coverage floor (**60**). `$TARGET` = the landing
branch (`main`). Flags come off the invocation, never a dialogue: `--coverage
<pct>`, `--target <branch>`, `--merge` (default) lands, `--pr` opens a PR.

**Budget: one agent spawn per story** — one combined security + correctness
review, never a lens fleet. Every spawn is block-collect-close: spawn, wait,
read the report, act, say what you did; an unread report did not run. **Never**
force-push, rewrite history, or touch `$TARGET` without step 7's confirmation.

## Checklist

- [ ] **1. Intake — three gates, this order, from the user's checkout.**
      ```sh
      bash "$MD/scripts/gate.sh" preflight
      bash "$MD/scripts/gate.sh" plan-contract "$PLAN"
      bash "$MD/scripts/gate.sh" stamp "$PLAN"
      ```
      Any `STATUS=FAIL` stops the run: quote the `REASON=` line. The stamp gate
      is a hard STOP with **no escape** — no flag, no prompt, no "the user says
      it is fine". An unstamped plan goes back to `/dreamer:plan`.
- [ ] **2. Read the plan once** for story ids, titles, ACs, `Depends On`,
      `Touches`. `plan-contract` proved the graph acyclic, so run the stories in
      plan order — no scheduler, no waves.
- [ ] **3. Isolated worktree** — sibling directory, branch `sprint/<name>`, the
      shape a crewforge5 sprint uses. Nothing writes to the user's checkout until
      step 7; the exclude line keeps run artefacts, the pack included, out of git.
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
- [ ] **4. Pack the worktree, traverse it, and only then write code.**
      `bash "$MD/scripts/repomix.sh" pack --root "$WORKTREE_PATH"` writes the
      whole tree to one xml file, `.dreamer/repo.xml`, and `repomix.sh outline
      --pack .dreamer/repo.xml` maps it. From that map say, in two lines, where source and tests live and
      what the test command is, then check every story's `Touches` against it —
      a path the map lacks is a file the story creates, or a plan error; say
      which before story 1. `REASON=no-provider` (no repomix, no git) is not a
      stop: say so and read the files direct.
- [ ] **5. Per-story loop** (below), once per story, in order. Do not open a
      story until the one before it is committed.
- [ ] **6. Full suite, then the record.** `gate.sh tests --coverage "$COV"` over
      the whole worktree must print `STATUS=OK`. Write `.dreamer/state.json` —
      `{"run_id":"execute-<UTC ISO8601>","plan":"<$PLAN>","mode":"execute",`
      `"gates":{"preflight":"OK","plan-contract":"OK","stamp":"OK","tests":"OK",`
      `"coverage":"OK","review":"OK"}}` — then `gate.sh report` from the
      worktree.
- [ ] **7. Land.** `--pr`: `git push -u origin "$SPRINT_BRANCH"`, then open the
      PR; `$TARGET` is never written. `--merge`: state branch, commit count and
      target, get an explicit yes, then `git merge --no-ff "$SPRINT_BRANCH"`
      from `$MAIN_TREE`. No confirmation, no merge.
- [ ] **8. Close** — `git worktree remove "$WORKTREE_PATH"` takes `.dreamer/`
      and the pack with it; then report the per-story commits, final coverage,
      deferred MEDIUM/LOW findings and the spawn count.

## The per-story loop

`$SID` = the story id the plan contract reports (`1`, `mech-9`); `$ART` =
`.dreamer/execute` inside the worktree.

1. **RED — one failing test per AC, before a line of implementation.** Read the
   story's `Touches` out of the pack first — `repomix.sh show <path> --pack
   .dreamer/repo.xml`, a step-4 snapshot, so an earlier story's work reads off
   disk — then write a test per AC into its `Touches` test files and run `bash
   "$MD/scripts/gate.sh" tests`. It **must** print `STATUS=FAIL
   REASON=tests-failed`. `STATUS=OK` means the tests you just wrote cannot fail
   — the AC is not observable. STOP with `REASON=no-red`, naming story, AC and
   `$WORKTREE_PATH`; do not implement your way past it, and do not soften the AC
   until it is testable.
2. **GREEN — implement the story and nothing else**, inside its `Touches` paths,
   then `bash "$MD/scripts/gate.sh" tests --coverage "$COV"`. `STATUS=OK`, or
   the story is not done. `REASON=coverage-below-threshold` is a missing test,
   never a floor to lower — `$COV` is fixed at intake.
   `REASON=no-coverage-figure` means the test command prints no percentage: say
   so and re-run without `--coverage` rather than invent a number.
3. **Review — one spawn, blocked on, collected, closed.** One agent, security
   and correctness in one pass, over this story's diff only. It writes `FINDING
   id=<id> severity=<CRITICAL|HIGH|MEDIUM|LOW> status=<open|resolved>` lines to
   `$ART/findings-$SID.md`. Wait, read the report, then `bash
   "$MD/scripts/gate.sh" findings "$ART/findings-$SID.md"`. Fix every
   CRITICAL/HIGH and re-run step 2's gate and this one; MEDIUM/LOW are reported,
   not applied. Two fix rounds is the cap; at a third, STOP with what is open.
4. **Commit — exactly one per story**, staging only that story's paths: `git add
   <Touches paths>` then `git commit -F "$ART/commit-msg-$SID.txt"`, in a
   crewforge5 story commit's shape so `git log` reads the same either side:
   ```
   <type>(<SID>): <story title>

   Story: <SID> — <story title>
   Plan: <$PLAN>

   Acceptance criteria met:
   - <ac bullet, verbatim from the plan>

   Gates: tests ✓ | coverage ✓ | review ✓

   Co-Authored-By: Claude <noreply@anthropic.com>
   ```
   `<type>` is a Conventional Commits type — `feat` unless the story is plainly
   `fix`/`refactor`/`docs`/`chore`. The `Story: <SID> — ` line is load-bearing:
   `git log --grep '^Story: <SID>'` finds a story's commit. One commit per story;
   no `wip` commits left on the branch.

## Stop conditions

Each ends the run where it stands. The worktree is removed **only** on a clean
finish; on any STOP it stays as it is, with `$WORKTREE_PATH` in the stop
message's first line, so the work stays inspectable.

- Any intake gate `STATUS=FAIL` — the worktree does not exist yet.
- `REASON=no-red` — an AC no test can fail on. Stop before implementing it.
- Tests or coverage still failing after the story's fixes.
- CRITICAL/HIGH findings open after two fix rounds.
- The user declines the merge, or `$TARGET` would be written without one.
