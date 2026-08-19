#!/usr/bin/env bats
#
# gate.bats — every scripts/gate.sh subcommand, one pass and one fail case each.
#
# Hermetic: git repos, state files and test-command stubs are built inside
# $BATS_TEST_TMPDIR and every such test cd's into it first. The read-only plan
# and findings fixtures live in tests/fixtures/ and are never written to.

setup() {
  GATE="$BATS_TEST_DIRNAME/../scripts/gate.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
  # Never let a discovered test command from the developer's environment leak in.
  unset MAD_DREAMER_TEST_CMD
}

# Assert `key=value` appears on its own line in $output.
assert_line_kv() {
  [[ "$output" == *"$1"* ]] || {
    echo "expected line: $1"
    echo "actual output:"
    echo "$output"
    return 1
  }
}

init_repo() {
  cd "$BATS_TEST_TMPDIR" || return 1
  git init -q .
  git config user.email t@example.com
  git config user.name Test
}

# --- preflight ---------------------------------------------------------------

@test "preflight: OK in a clean git repo with tooling present" {
  init_repo
  run bash "$GATE" preflight
  [ "$status" -eq 0 ]
  assert_line_kv "STATUS=OK"
  assert_line_kv "GIT_REPO=yes"
  assert_line_kv "TREE=clean"
  assert_line_kv "TOOLS=ok"
}

@test "preflight: FAIL on a dirty working tree" {
  init_repo
  echo stray >untracked.txt
  run bash "$GATE" preflight
  [ "$status" -eq 1 ]
  assert_line_kv "STATUS=FAIL"
  assert_line_kv "TREE=dirty"
  assert_line_kv "REASON=dirty-tree"
}

@test "preflight: --allow-dirty tolerates a dirty tree" {
  init_repo
  echo stray >untracked.txt
  run bash "$GATE" preflight --allow-dirty
  [ "$status" -eq 0 ]
  assert_line_kv "STATUS=OK"
  assert_line_kv "TREE=dirty"
  assert_line_kv "ALLOW_DIRTY=true"
}

@test "preflight: FAIL outside a git repo" {
  mkdir -p "$BATS_TEST_TMPDIR/bare"
  cd "$BATS_TEST_TMPDIR/bare" || return 1
  # GIT_CEILING_DIRECTORIES stops git walking up out of the tmpdir.
  GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR" run bash "$GATE" preflight
  [ "$status" -eq 1 ]
  assert_line_kv "STATUS=FAIL"
  assert_line_kv "GIT_REPO=no"
  assert_line_kv "REASON=not-a-git-repo"
}

# --- plan-contract -----------------------------------------------------------

@test "plan-contract: OK against the vendored crewforge5 golden template" {
  run bash "$GATE" plan-contract "$FIXTURES/golden-template-1.md"
  [ "$status" -eq 0 ]
  assert_line_kv "STATUS=OK"
  assert_line_kv "PLAN_PATH=OK"
  assert_line_kv "STORIES=6"
  assert_line_kv "NODES=6"
  # 2 declared edges (1<-2, 2<-3) + 1 inferred edge (4<-5); story 6 has no Touches.
  assert_line_kv "EDGES=3"
}

@test "plan-contract: FAIL on a dependency cycle" {
  run bash "$GATE" plan-contract "$FIXTURES/cycle-plan-1.md"
  [ "$status" -eq 1 ]
  assert_line_kv "STATUS=FAIL"
  assert_line_kv "REASON=graph-invalid"
}

@test "plan-contract: FAIL on a plan filename carrying no story id" {
  run bash "$GATE" plan-contract "$FIXTURES/plan.md"
  [ "$status" -eq 1 ]
  assert_line_kv "STATUS=FAIL"
  assert_line_kv "PLAN_PATH=FAIL"
  assert_line_kv "REASON=plan-path-invalid"
}

@test "plan-contract: FAIL when the plan does not exist" {
  run bash "$GATE" plan-contract "$BATS_TEST_TMPDIR/absent-1.md"
  [ "$status" -eq 1 ]
  assert_line_kv "STATUS=FAIL"
  assert_line_kv "REASON=plan-missing"
}

@test "plan-contract: writes nothing — the repo it runs in stays clean" {
  init_repo
  cp "$FIXTURES/golden-template-1.md" .
  git add golden-template-1.md
  git -c commit.gpgsign=false commit -qm seed
  run bash "$GATE" plan-contract golden-template-1.md
  [ "$status" -eq 0 ]
  [ -z "$(git status --porcelain)" ]
}

# --- stamp -------------------------------------------------------------------

@test "stamp: OK on a status=clean stamp carrying mode=dreamer" {
  run bash "$GATE" stamp "$FIXTURES/stamped-plan-1.md"
  [ "$status" -eq 0 ]
  assert_line_kv "STATUS=OK"
  assert_line_kv "REVIEW_STATUS=clean"
  assert_line_kv "ROUNDS=2"
  assert_line_kv "MODE=dreamer"
}

@test "stamp: OK on an unextended upstream stamp (MODE=none)" {
  cd "$BATS_TEST_TMPDIR" || return 1
  printf '# Plan\n<!-- adversarial-review: status=user-override rounds=3 date=2026-08-18 reviewer=team-sprint-planner -->\n' >upstream-1.md
  run bash "$GATE" stamp upstream-1.md
  [ "$status" -eq 0 ]
  assert_line_kv "STATUS=OK"
  assert_line_kv "REVIEW_STATUS=user-override"
  assert_line_kv "MODE=none"
}

@test "stamp: FAIL when no stamp matches the upstream grammar" {
  run bash "$GATE" stamp "$FIXTURES/unstamped-plan-1.md"
  [ "$status" -eq 1 ]
  assert_line_kv "STATUS=FAIL"
  assert_line_kv "REASON=no-adversarial-stamp"
}

@test "stamp: FAIL on a mode= value other than dreamer" {
  run bash "$GATE" stamp "$FIXTURES/badmode-plan-1.md"
  [ "$status" -eq 1 ]
  assert_line_kv "STATUS=FAIL"
  assert_line_kv "REASON=unknown-mode"
}

# --- findings ----------------------------------------------------------------

@test "findings: OK when no CRITICAL or HIGH is open" {
  run bash "$GATE" findings "$FIXTURES/findings-clean.md"
  [ "$status" -eq 0 ]
  assert_line_kv "STATUS=OK"
  assert_line_kv "CRITICAL=0"
  assert_line_kv "HIGH=0"
  assert_line_kv "MEDIUM=1"
  assert_line_kv "LOW=1"
  assert_line_kv "CLOSED=2"
}

@test "findings: FAIL while a CRITICAL or HIGH is open" {
  run bash "$GATE" findings "$FIXTURES/findings-blocking.md"
  [ "$status" -eq 1 ]
  assert_line_kv "STATUS=FAIL"
  assert_line_kv "CRITICAL=1"
  # 1 KEY=VALUE HIGH plus 1 unfolded upstream `<!-- FINDING ... (HIGH) -->` marker.
  assert_line_kv "HIGH=2"
  assert_line_kv "REASON=open-blocking-findings"
}

@test "findings: FAIL closed on an unparseable finding line" {
  run bash "$GATE" findings "$FIXTURES/findings-malformed.md"
  [ "$status" -eq 1 ]
  assert_line_kv "STATUS=FAIL"
  assert_line_kv "MALFORMED=2"
  assert_line_kv "REASON=malformed-finding"
}

@test "findings: FAIL when the findings file is absent" {
  run bash "$GATE" findings "$BATS_TEST_TMPDIR/no-such-findings.md"
  [ "$status" -eq 1 ]
  assert_line_kv "STATUS=FAIL"
  assert_line_kv "REASON=findings-file-missing"
}

# --- tests -------------------------------------------------------------------

@test "tests: OK when the discovered command passes" {
  cd "$BATS_TEST_TMPDIR" || return 1
  printf 'test:\n\t@echo all green\n' >Makefile
  run bash "$GATE" tests
  [ "$status" -eq 0 ]
  assert_line_kv "STATUS=OK"
  assert_line_kv "TEST_CMD=make test"
  assert_line_kv "TEST_SOURCE=makefile"
  assert_line_kv "EXIT_CODE=0"
}

@test "tests: FAIL when the discovered command fails" {
  cd "$BATS_TEST_TMPDIR" || return 1
  printf 'test:\n\t@echo boom; exit 1\n' >Makefile
  run bash "$GATE" tests
  [ "$status" -eq 1 ]
  assert_line_kv "STATUS=FAIL"
  assert_line_kv "REASON=tests-failed"
}

@test "tests: FAIL with REASON=no-test-command when nothing is discoverable" {
  mkdir -p "$BATS_TEST_TMPDIR/empty"
  cd "$BATS_TEST_TMPDIR/empty" || return 1
  run bash "$GATE" tests
  [ "$status" -eq 1 ]
  assert_line_kv "STATUS=FAIL"
  assert_line_kv "REASON=no-test-command"
}

@test "tests: OK when reported coverage meets the threshold" {
  cd "$BATS_TEST_TMPDIR" || return 1
  MAD_DREAMER_TEST_CMD='echo "TOTAL 87.5%"' run bash "$GATE" tests --coverage 80
  [ "$status" -eq 0 ]
  assert_line_kv "STATUS=OK"
  assert_line_kv "COVERAGE=87.5"
  assert_line_kv "COVERAGE_MIN=80"
}

@test "tests: FAIL when reported coverage is below the threshold" {
  cd "$BATS_TEST_TMPDIR" || return 1
  MAD_DREAMER_TEST_CMD='echo "TOTAL 61%"' run bash "$GATE" tests --coverage 80
  [ "$status" -eq 1 ]
  assert_line_kv "STATUS=FAIL"
  assert_line_kv "COVERAGE=61"
  assert_line_kv "REASON=coverage-below-threshold"
}

@test "tests: FAIL when --coverage is asked for and no figure is emitted" {
  cd "$BATS_TEST_TMPDIR" || return 1
  MAD_DREAMER_TEST_CMD='echo "no numbers here"' run bash "$GATE" tests --coverage 80
  [ "$status" -eq 1 ]
  assert_line_kv "STATUS=FAIL"
  assert_line_kv "REASON=no-coverage-figure"
}

# --- report ------------------------------------------------------------------

@test "report: OK and summarises a well-formed state file" {
  cd "$BATS_TEST_TMPDIR" || return 1
  mkdir -p .dreamer
  cat >.dreamer/state.json <<'JSON'
{
  "run_id": "md-0001",
  "plan": "docs/story-1.md",
  "mode": "dreamer",
  "gates": { "preflight": "OK", "plan-contract": "OK", "tests": "FAIL" }
}
JSON
  run bash "$GATE" report
  [ "$status" -eq 0 ]
  assert_line_kv "STATUS=OK"
  assert_line_kv "RUN_ID=md-0001"
  assert_line_kv "PLAN=docs/story-1.md"
  assert_line_kv "MODE=dreamer"
  assert_line_kv "GATES_TOTAL=3"
  assert_line_kv "GATES_OK=2"
  assert_line_kv "GATES_FAIL=1"
}

@test "report: FAIL when the state file is missing" {
  mkdir -p "$BATS_TEST_TMPDIR/nostate"
  cd "$BATS_TEST_TMPDIR/nostate" || return 1
  run bash "$GATE" report
  [ "$status" -eq 1 ]
  assert_line_kv "STATUS=FAIL"
  assert_line_kv "REASON=state-missing"
}

@test "report: FAIL when the state file is malformed" {
  mkdir -p "$BATS_TEST_TMPDIR/badstate/.dreamer"
  cd "$BATS_TEST_TMPDIR/badstate" || return 1
  printf '{ "run_id": ' >.dreamer/state.json
  run bash "$GATE" report
  [ "$status" -eq 1 ]
  assert_line_kv "STATUS=FAIL"
  assert_line_kv "REASON=state-malformed"
}

# --- contract ----------------------------------------------------------------

@test "every subcommand prints exactly one STATUS= line" {
  init_repo
  local sub
  for sub in "preflight --allow-dirty" "plan-contract $FIXTURES/golden-template-1.md" \
             "stamp $FIXTURES/stamped-plan-1.md" "findings $FIXTURES/findings-clean.md" \
             "report"; do
    # shellcheck disable=SC2086  # deliberate word splitting of the subcommand line
    run bash "$GATE" $sub
    [ "$(printf '%s\n' "$output" | grep -c '^STATUS=')" -eq 1 ]
  done
}

@test "unknown subcommand is a usage error, not a verdict" {
  run bash "$GATE" not-a-subcommand
  [ "$status" -eq 2 ]
}
