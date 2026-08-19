# execute-plan-untestable-1 — one story whose AC no test can fail on
<!-- adversarial-review: status=clean rounds=1 date=2026-08-19 reviewer=dreamer mode=dreamer -->

Read-only fixture, and a deliberately bad plan. It is stamped and
contract-valid, so `gate.sh stamp` and `gate.sh plan-contract` both pass it —
which is the point. The only thing wrong with it is that its acceptance
criterion names no observable behaviour, so the strongest honest test anyone can
write for it passes before a line of implementation exists.

`skills/execute/SKILL.md`'s RED gate is what catches that: a test suite that is
already green at RED time means the AC is not observable, and the run STOPs with
`REASON=no-red` — after the worktree exists, before anything is implemented or
committed. `tests/execute.bats` drives exactly that sequence over this plan.

## Assumptions
- The AC below is left unfixable on purpose. Do not sharpen it; sharpening it
  deletes the fixture.

## Story 1: Handle bad input

### Depends On: none
### Touches: src/calc.py, tests/test_calc.py

### Acceptance Criteria
- The calculator handles bad input correctly.

### Definition of Done
- Story tests green.
