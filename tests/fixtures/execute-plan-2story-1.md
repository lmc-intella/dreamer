# execute-plan-2story-1 — a two-story toy sprint for the execute spine
<!-- adversarial-review: status=clean rounds=1 date=2026-08-19 reviewer=dreamer mode=dreamer -->

Read-only fixture. `tests/execute.bats` copies this plan into a scratch git repo
under `$BATS_TEST_TMPDIR` and drives `skills/execute/SKILL.md`'s mechanical spine
over it: worktree, RED→GREEN per story, the 60% coverage floor, one commit per
story, merge, worktree removal.

Both stories land in a repo whose test command is `make test` → the toy runner at
`tests/fixtures/execute-runner-1.py`, which prints a real line-coverage figure
for `src/*.py`. Story 2 is sized so that shipping `render` without its own test
puts whole-repo coverage under the floor — that is what makes the coverage gate
observable inside the loop rather than only in `tests/gate.bats`.

## Assumptions
- The scratch repo is built by the test, not grounded from a real codebase: this
  plan exists to exercise the execute spine, not to plan real work.
- Coverage is whole-repo, not per-story — the floor is checked after each story,
  so a story that ships untested code fails on the story that shipped it.

## Story 1: Add a guarded sum

The scratch repo starts with no `src/` at all, so this story also proves the RED
gate fires on an import error rather than on an assertion.

### Depends On: none
### Touches: src/calc.py, tests/test_calc.py

### Acceptance Criteria
- `add(2, 3)` returns `5`.
- `add("2", 3)` raises `TypeError` instead of concatenating.

### Definition of Done
- Story tests green; whole-repo coverage at or above the run's floor.

## Story 2: Parse and render config text

Depends on Story 1 only to pin the execution order — the two stories touch
disjoint files, so the contract gate reports one declared edge and no inferred
one.

### Depends On: 1
### Touches: src/config.py, tests/test_config.py

### Acceptance Criteria
- `parse("a = 1\n\nb=2")` returns `{"a": "1", "b": "2"}`: blank lines skipped,
  whitespace trimmed around both key and value.
- `parse("oops")` raises `ValueError` naming the offending line.
- `render({"b": 2, "a": 1, "c": None, "d": True})` returns `"a=1\nb=2\nd=true"`:
  keys sorted, `None` values dropped, booleans lowercased.

### Definition of Done
- Story tests green; whole-repo coverage at or above the run's floor.
