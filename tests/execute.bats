#!/usr/bin/env bats
#
# execute.bats — the mechanical spine of skills/execute/SKILL.md.
#
# Proven here, by running it: the intake gate sequence, the stamp hard-STOP, the
# worktree isolation recipe (extracted from SKILL.md itself, so the documented
# commands are the ones that run), RED→GREEN per story, the coverage floor
# biting inside the story loop, the review-closure gate, one commit per story in
# the documented shape, the merge, and worktree removal.
#
# NOT proven here, because it needs a live agent: the per-story review spawn and
# its block-collect-close. What the test drives is the gate the collected report
# has to pass (`gate.sh findings`), standing in for the agent that writes it.
#
# Hermetic: every repo, worktree and source file lives under $BATS_TEST_TMPDIR,
# and git identity is passed per-invocation rather than read from the machine.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  GATE="$REPO_ROOT/scripts/gate.sh"
  SKILL="$REPO_ROOT/skills/execute/SKILL.md"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
  # A discovered test command from the developer's environment must never leak
  # into the scratch repo's gate runs.
  unset MAD_DREAMER_TEST_CMD
}

assert_line_kv() {
  [[ "$output" == *"$1"* ]] || {
    echo "expected line: $1"
    echo "actual output:"
    echo "$output"
    return 1
  }
}

# Fail the test if SKILL.md matches a banned pattern. A bare `! grep` would not:
# bats exempts a negated command from errexit unless it is the test's last one.
refute_skill_match() {
  if grep -qiE -- "$1" "$SKILL"; then
    echo "SKILL.md matches a pattern it must not: $1"
    grep -niE -- "$1" "$SKILL"
    return 1
  fi
}

# git with a local identity — the scratch repos never read the machine's config.
g() {
  git -c user.email=bats@example.invalid -c user.name='bats fixture' \
      -c commit.gpgsign=false "$@"
}

# Emit the Nth ```sh block of SKILL.md, de-indented. The point is that the test
# runs the skill's own commands: a recipe that drifts from what works fails here.
sh_block() {
  awk -v want="$1" '
    /^ *```sh$/  { n++; if (n == want) { inb = 1; next } }
    inb && /^ *```$/ { exit }
    inb { sub(/^[[:space:]]+/, ""); print }
  ' "$SKILL"
}

# A scratch repo whose test command is `make test` -> the toy runner, which
# prints a real line-coverage figure for src/*.py. $1 = plan fixture filename.
scratch_repo() {
  MAIN="$BATS_TEST_TMPDIR/proj"
  PLAN="$1"
  # shellcheck disable=SC2034  # consumed by the SKILL.md block the tests eval.
  TARGET=main
  mkdir -p "$MAIN/tools" "$MAIN/tests"
  cp "$FIXTURES/execute-runner-1.py" "$MAIN/tools/run_tests.py"
  : >"$MAIN/tests/__init__.py"
  printf 'test:\n\t@python3 tools/run_tests.py\n' >"$MAIN/Makefile"
  printf '__pycache__/\n*.pyc\n' >"$MAIN/.gitignore"
  cp "$FIXTURES/$PLAN" "$MAIN/$PLAN"
  cd "$MAIN" || return 1
  g init -q -b main .
  g add .gitignore Makefile tools/run_tests.py tests/__init__.py "$PLAN"
  g commit -qm 'seed the scratch repo'
  SEED="$(g rev-parse HEAD)"
}

# --- the skill's own shape ---------------------------------------------------

@test "SKILL.md body is at most 120 lines" {
  local total body
  total="$(wc -l <"$SKILL")"
  # 5 lines of frontmatter (--- name model description ---).
  body=$((total - 5))
  [ "$body" -le 120 ] || {
    echo "body is $body lines (total $total); budget is 120"
    return 1
  }
}

@test "SKILL.md loads no second document: no references dir, no third markdown" {
  [ ! -d "$REPO_ROOT/skills/execute/references" ]
  refute_skill_match 'references/'
  # Every markdown path in the skill is either the plan (the one doc the run
  # loads besides this page) or findings-$SID.md, which the run writes and the
  # findings gate reads back. A third markdown path would be a doc to load.
  local token
  while IFS= read -r token; do
    case "$token" in
      '${PLAN%.md}'|'$PLAN'|'findings-$SID.md') ;;
      *) echo "SKILL.md names a markdown path that is neither the plan nor its findings file: $token"
         return 1 ;;
    esac
  done < <(grep -oE '[^ `"/]*\.md|\$\{PLAN%\.md\}' "$SKILL" | sort -u)
}

@test "SKILL.md wires only gate.sh subcommands that exist" {
  local sub
  while IFS= read -r sub; do
    case "$sub" in
      preflight|plan-contract|stamp|findings|tests|report) ;;
      *) echo "SKILL.md invokes an unknown gate.sh subcommand: $sub"; return 1 ;;
    esac
  done < <(grep -oE 'gate\.sh"? [a-z-]+' "$SKILL" | sed 's/.*[ "]//' | sort -u)
  # The coverage floor is passed with the real flag, on the real subcommand.
  grep -q 'gate\.sh" tests --coverage "\$COV"' "$SKILL"
  # A dirty tree is never waved through at intake.
  refute_skill_match '--allow-dirty'
}

@test "SKILL.md prescribes no force-push and no history rewrite" {
  refute_skill_match '--force|push -f|git rebase|--amend|reset --hard'
}

@test "SKILL.md offers no override path around the stamp gate" {
  refute_skill_match 'override'
  grep -q 'no escape' "$SKILL"
  grep -q 'REASON=no-red' "$SKILL"
}

# --- the stamp hard-STOP -----------------------------------------------------

@test "stamp gate: passes the stamped fixture, fails the unstamped one" {
  run bash "$GATE" stamp "$FIXTURES/execute-plan-2story-1.md"
  [ "$status" -eq 0 ]
  assert_line_kv "STATUS=OK"
  assert_line_kv "MODE=dreamer"

  run bash "$GATE" stamp "$FIXTURES/unstamped-plan-1.md"
  [ "$status" -eq 1 ]
  assert_line_kv "STATUS=FAIL"
  assert_line_kv "REASON=no-adversarial-stamp"
}

@test "intake: the SKILL.md gate block runs all three gates green" {
  scratch_repo execute-plan-2story-1.md
  run env MD="$REPO_ROOT" PLAN="$PLAN" bash -c "$(sh_block 1)"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^STATUS=OK$' <<<"$output")" -eq 3 ]
  assert_line_kv "STORIES=2"
  assert_line_kv "EDGES=1"
}

# --- worktree isolation ------------------------------------------------------

@test "worktree: the SKILL.md recipe isolates the run from the user's checkout" {
  scratch_repo execute-plan-2story-1.md
  eval "$(sh_block 2)"
  # Compare resolved paths: on macOS $MAIN sits under /var, a symlink to
  # /private/var, and `git rev-parse --show-toplevel` returns the resolved form,
  # so the two spellings of the same directory differ as strings.
  [ "$(cd "$WORKTREE_PATH" && pwd -P)" = "$(cd "$MAIN/.." && pwd -P)/proj-execute-plan-2story-1" ]
  [ -d "$WORKTREE_PATH" ]
  [ "$(g -C "$WORKTREE_PATH" rev-parse --abbrev-ref HEAD)" = sprint/execute-plan-2story-1 ]
  # The user's checkout is untouched: same branch, same commit, clean tree.
  [ "$(g -C "$MAIN" rev-parse --abbrev-ref HEAD)" = main ]
  [ "$(g -C "$MAIN" rev-parse main)" = "$SEED" ]
  [ -z "$(g -C "$MAIN" status --porcelain)" ]
  # Run artefacts written in the worktree stay out of git.
  mkdir -p "$WORKTREE_PATH/.dreamer/execute"
  echo scratch >"$WORKTREE_PATH/.dreamer/execute/note.txt"
  [ -z "$(g -C "$WORKTREE_PATH" status --porcelain)" ]
}

# --- Definition of Done: the 2-story plan, end to end ------------------------

@test "DoD: 2-story plan runs end to end — worktree, RED/GREEN, 60% floor, merge, removal" {
  scratch_repo execute-plan-2story-1.md

  # 1. Intake.
  run bash "$GATE" preflight
  [ "$status" -eq 0 ]
  assert_line_kv "TREE=clean"
  run bash "$GATE" plan-contract "$PLAN"
  [ "$status" -eq 0 ]
  assert_line_kv "STORIES=2"
  run bash "$GATE" stamp "$PLAN"
  [ "$status" -eq 0 ]

  # 3. Isolated worktree, straight from the skill.
  eval "$(sh_block 2)"
  ART=".dreamer/execute"
  mkdir -p "$ART"

  # --- Story 1 -------------------------------------------------------------
  # RED: a test per AC, before any implementation. src/ does not exist yet.
  cat >tests/test_calc.py <<'PY'
import unittest
from src.calc import add


class AddTest(unittest.TestCase):
    def test_sums_two_numbers(self):
        self.assertEqual(add(2, 3), 5)

    def test_rejects_a_non_numeric_operand(self):
        with self.assertRaises(TypeError):
            add("2", 3)
PY
  run bash "$GATE" tests
  [ "$status" -eq 1 ]
  assert_line_kv "TEST_CMD=make test"
  assert_line_kv "REASON=tests-failed"

  # GREEN.
  mkdir -p src
  cat >src/calc.py <<'PY'
def add(a, b):
    if not isinstance(a, (int, float)) or not isinstance(b, (int, float)):
        raise TypeError("add: numeric operands only")
    return a + b
PY
  run bash "$GATE" tests --coverage 60
  [ "$status" -eq 0 ]
  assert_line_kv "COVERAGE=100.0"
  assert_line_kv "COVERAGE_MIN=60"

  # Review: the gate the collected agent report has to pass.
  cat >"$ART/findings-1.md" <<'MD'
FINDING id=s1-f1 severity=LOW status=open — `add` accepts bool operands.
MD
  run bash "$GATE" findings "$ART/findings-1.md"
  [ "$status" -eq 0 ]
  assert_line_kv "CRITICAL=0"
  assert_line_kv "HIGH=0"

  # Commit: exactly one, in the documented shape.
  cat >"$ART/commit-msg-1.txt" <<'MSG'
feat(1): Add a guarded sum

Story: 1 — Add a guarded sum
Plan: execute-plan-2story-1.md

Acceptance criteria met:
- `add(2, 3)` returns `5`.
- `add("2", 3)` raises `TypeError` instead of concatenating.

Gates: tests ✓ | coverage ✓ | review ✓
MSG
  g add src/calc.py tests/test_calc.py
  g commit -q -F "$ART/commit-msg-1.txt"
  [ "$(g log -1 --pretty=%s)" = 'feat(1): Add a guarded sum' ]
  [ "$(g log --grep '^Story: 1 ' --pretty=%H | wc -l)" -eq 1 ]

  # --- Story 2 -------------------------------------------------------------
  # RED: only two of the three ACs get a test here — the omission is what the
  # coverage floor is about to catch.
  cat >tests/test_config.py <<'PY'
import unittest
from src.config import parse


class ParseTest(unittest.TestCase):
    def test_reads_pairs_and_skips_blank_lines(self):
        self.assertEqual(parse("a = 1\n\nb=2"), {"a": "1", "b": "2"})

    def test_rejects_a_line_without_a_separator(self):
        with self.assertRaises(ValueError):
            parse("oops")
PY
  run bash "$GATE" tests
  [ "$status" -eq 1 ]
  assert_line_kv "REASON=tests-failed"

  # GREEN for the code, but `render` ships without its AC test.
  cat >src/config.py <<'PY'
def parse(text):
    out = {}
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        if "=" not in line:
            raise ValueError("parse: expected k=v, got %r" % line)
        key, value = line.split("=", 1)
        out[key.strip()] = value.strip()
    return out


def render(cfg):
    if not isinstance(cfg, dict):
        raise TypeError("render: cfg must be a dict")
    lines = []
    for key in sorted(cfg):
        value = cfg[key]
        if value is None:
            continue
        if isinstance(value, bool):
            value = "true" if value else "false"
        text = "%s=%s" % (key, value)
        lines.append(text)
    if not lines:
        return ""
    return "\n".join(lines)
PY
  run bash "$GATE" tests --coverage 60
  [ "$status" -eq 1 ]
  assert_line_kv "COVERAGE=53.3"
  assert_line_kv "REASON=coverage-below-threshold"
  # Tests themselves passed: the story is blocked by the floor, nothing else.
  assert_line_kv "EXIT_CODE=0"

  # The fix is the missing test, never a lower floor.
  cat >>tests/test_config.py <<'PY'


class RenderTest(unittest.TestCase):
    def test_renders_sorted_pairs_dropping_none_and_lowercasing_bools(self):
        from src.config import render
        self.assertEqual(
            render({"b": 2, "a": 1, "c": None, "d": True}), "a=1\nb=2\nd=true")
PY
  run bash "$GATE" tests --coverage 60
  [ "$status" -eq 0 ]
  assert_line_kv "COVERAGE=93.3"

  cat >"$ART/findings-2.md" <<'MD'
FINDING id=s2-f1 severity=MEDIUM status=open — `render` has no guard test for a
non-dict argument.
MD
  run bash "$GATE" findings "$ART/findings-2.md"
  [ "$status" -eq 0 ]

  cat >"$ART/commit-msg-2.txt" <<'MSG'
feat(2): Parse and render config text

Story: 2 — Parse and render config text
Plan: execute-plan-2story-1.md

Acceptance criteria met:
- `parse` skips blank lines and trims whitespace.
- `parse("oops")` raises `ValueError` naming the offending line.
- `render` sorts keys, drops `None`, lowercases booleans.

Gates: tests ✓ | coverage ✓ | review ✓
MSG
  g add src/config.py tests/test_config.py
  g commit -q -F "$ART/commit-msg-2.txt"

  # One commit per story, story id in the message, nothing else on the branch.
  [ "$(g rev-list --count "$SEED"..HEAD)" -eq 2 ]
  [ "$(g log --grep '^Story: ' --pretty=%H | wc -l)" -eq 2 ]
  [ -z "$(g log --oneline --grep '^wip' "$SEED"..HEAD)" ]

  # 5. Full suite plus the run record, from the worktree.
  run bash "$GATE" tests --coverage 60
  [ "$status" -eq 0 ]
  mkdir -p .dreamer
  cat >.dreamer/state.json <<'JSON'
{ "run_id": "execute-2026-08-19T00:00:00Z",
  "plan": "execute-plan-2story-1.md",
  "mode": "execute",
  "gates": { "preflight": "OK", "plan-contract": "OK", "stamp": "OK",
             "tests": "OK", "coverage": "OK", "review": "OK" } }
JSON
  run bash "$GATE" report
  [ "$status" -eq 0 ]
  assert_line_kv "GATES_OK=6"
  assert_line_kv "GATES_FAIL=0"

  # Up to here the user's checkout has not been written to at all.
  [ "$(g -C "$MAIN" rev-parse main)" = "$SEED" ]
  [ ! -e "$MAIN/src/calc.py" ]

  # 6. Land: merge is the only step that touches the target branch.
  cd "$MAIN" || return 1
  g merge -q --no-ff -m 'merge sprint/execute-plan-2story-1' "$SPRINT_BRANCH"
  [ "$(g log --grep '^Story: ' --pretty=%H main | wc -l)" -eq 2 ]
  [ -f "$MAIN/src/calc.py" ]
  [ -f "$MAIN/src/config.py" ]

  # 7. Close: the worktree is removed on a clean finish.
  g worktree remove "$WORKTREE_PATH"
  [ ! -d "$WORKTREE_PATH" ]
  [ "$(g worktree list --porcelain | grep -c '^worktree ')" -eq 1 ]
  [ -z "$(g -C "$MAIN" status --porcelain)" ]
}

# --- Definition of Done: the untestable-AC plan STOPs ------------------------

@test "DoD: an untestable AC STOPs at the RED gate with the worktree intact" {
  scratch_repo execute-plan-untestable-1.md

  # The plan is stamped and contract-valid, so neither intake gate is what stops
  # it — the STOP has to come from the RED gate, one step later.
  run bash "$GATE" stamp "$PLAN"
  [ "$status" -eq 0 ]
  run bash "$GATE" plan-contract "$PLAN"
  [ "$status" -eq 0 ]
  assert_line_kv "STORIES=1"

  eval "$(sh_block 2)"

  # The strongest honest test for "handles bad input correctly": it names no
  # observable, so it cannot fail, and there is nothing to implement against.
  cat >tests/test_calc.py <<'PY'
import unittest


class BadInputTest(unittest.TestCase):
    def test_handles_bad_input_correctly(self):
        self.assertTrue(True)
PY
  run bash "$GATE" tests
  # Green at RED time. Per SKILL.md this is REASON=no-red: STOP here.
  [ "$status" -eq 0 ]
  assert_line_kv "STATUS=OK"

  # The STOP lands in the right place: after the worktree exists, before a line
  # of implementation and before any commit.
  [ ! -e "$WORKTREE_PATH/src" ]
  [ "$(g -C "$WORKTREE_PATH" rev-list --count HEAD)" -eq 1 ]
  # The worktree is left in place, so the stop message has a path to report.
  [ -d "$WORKTREE_PATH" ]
  [ "$(g -C "$MAIN" rev-parse main)" = "$SEED" ]
}
