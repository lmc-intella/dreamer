#!/usr/bin/env bash
#
# gate.sh — dreamer quality gates.
#
#   gate.sh preflight [--allow-dirty]
#   gate.sh plan-contract <plan.md>
#   gate.sh stamp <plan.md>
#   gate.sh findings <findings-file>
#   gate.sh tests [--coverage <pct>]
#   gate.sh report
#
# Every subcommand prints `STATUS=OK` or `STATUS=FAIL` on its own line followed
# by one or more `KEY=VALUE` detail lines, and exits 0 on OK / 1 on FAIL.
# Usage errors (unknown subcommand, bad flag) print to stderr and exit 2 —
# a malformed invocation is not a verdict.
#
# READ-ONLY BY CONSTRUCTION. No subcommand creates, edits or deletes a file in
# the repository or any file named on the command line. `plan-contract` runs the
# vendored build_graph.sh, which must write its graph somewhere: it is given a
# private `mktemp -d` scratch directory outside the repo that is removed on exit.
# `report` only reads `.dreamer/state.json`.
#
# Vendored dependencies live in scripts/vendor/ and are resolved relative to this
# script's own directory — there is no runtime dependency on any upstream repo.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VENDOR_DIR="$SCRIPT_DIR/vendor"
STATE_FILE=".dreamer/state.json"

# The adversarial-review stamp grammar, byte-compatible with the upstream gate.
# See docs/vendor-policy.md for the provenance of this regex — it must stay
# character-for-character identical to the upstream check.
STAMP_RE='^<!-- adversarial-review: status=(clean|user-override) '

DETAILS=()

have() { command -v "$1" >/dev/null 2>&1; }
detail() { DETAILS+=("$1=$2"); }

emit() {
  # emit <OK|FAIL> — print the verdict, then the buffered detail lines, then
  # exit 0/1. Terminal by design: no caller has anything left to do after it.
  printf 'STATUS=%s\n' "$1"
  local d
  for d in ${DETAILS[@]+"${DETAILS[@]}"}; do
    printf '%s\n' "$d"
  done
  if [ "$1" = OK ]; then
    exit 0
  fi
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
usage: gate.sh <subcommand> [args]
  preflight [--allow-dirty]      git repo, clean tree, required tooling
  plan-contract <plan.md>        vendored plan-path + story parse + work graph
  stamp <plan.md>                adversarial-review stamp present and clean
  findings <findings-file>       no CRITICAL/HIGH finding left open
  tests [--coverage <pct>]       repo-discovered test command (+ coverage floor)
  report                         summarise .dreamer/state.json
USAGE
  exit 2
}

# --- preflight ---------------------------------------------------------------
cmd_preflight() {
  local allow_dirty=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --allow-dirty) allow_dirty=true; shift ;;
      *) printf 'gate.sh: preflight: unknown argument: %s\n' "$1" >&2; usage ;;
    esac
  done

  local verdict=OK t
  local missing=()
  for t in git python3 jq; do
    have "$t" || missing+=("$t")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    verdict=FAIL
    detail TOOLS missing
    detail MISSING_TOOLS "$(IFS=,; printf '%s' "${missing[*]}")"
  else
    detail TOOLS ok
  fi

  if have git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    detail GIT_REPO yes
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
      detail TREE dirty
      if [ "$allow_dirty" != true ]; then
        verdict=FAIL
        detail REASON dirty-tree
      fi
    else
      detail TREE clean
    fi
  else
    detail GIT_REPO no
    detail TREE unknown
    verdict=FAIL
    detail REASON not-a-git-repo
  fi

  detail ALLOW_DIRTY "$allow_dirty"
  emit "$verdict"
}

# --- plan-contract -----------------------------------------------------------
cmd_plan_contract() {
  [ $# -eq 1 ] || { printf 'gate.sh: plan-contract takes exactly one plan path\n' >&2; usage; }
  local plan="$1"
  detail PLAN "$plan"

  if [ ! -f "$plan" ]; then
    detail REASON plan-missing
    emit FAIL
  fi

  local out rc=0
  out="$(bash "$VENDOR_DIR/validate_plan_path.sh" "$plan")" || rc=$?
  local path_status
  path_status="$(printf '%s\n' "$out" | sed -n 's/^STATUS=//p' | tail -n1)"
  detail PLAN_PATH "${path_status:-UNKNOWN}"
  if [ "$rc" -ne 0 ]; then
    detail REASON plan-path-invalid
    emit FAIL
  fi

  local scratch
  scratch="$(mktemp -d)"
  # shellcheck disable=SC2064  # expand $scratch now, not at trap time
  trap "rm -rf -- '$scratch'" EXIT

  rc=0
  bash "$VENDOR_DIR/parse_stories.sh" "$plan" >"$scratch/stories.json" || rc=$?
  if [ "$rc" -ne 0 ]; then
    detail REASON parse-error
    detail PARSE_EXIT "$rc"
    emit FAIL
  fi
  local stories
  stories="$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$scratch/stories.json")"
  detail STORIES "$stories"

  rc=0
  TS_WORKTREE_NAME="${TS_WORKTREE_NAME:-dreamer}" \
    bash "$VENDOR_DIR/build_graph.sh" "$scratch/stories.json" "$scratch/graph.json" >/dev/null || rc=$?
  if [ "$rc" -ne 0 ]; then
    detail REASON graph-invalid
    detail GRAPH_EXIT "$rc"
    emit FAIL
  fi
  local edges
  edges="$(python3 -c 'import json,sys;g=json.load(open(sys.argv[1]));print(sum(len(n["depends_on"]) for n in g["nodes"]))' "$scratch/graph.json")"
  detail NODES "$stories"
  detail EDGES "$edges"
  emit OK
}

# --- stamp -------------------------------------------------------------------
cmd_stamp() {
  [ $# -eq 1 ] || { printf 'gate.sh: stamp takes exactly one plan path\n' >&2; usage; }
  local plan="$1"
  detail PLAN "$plan"

  if [ ! -f "$plan" ]; then
    detail REASON plan-missing
    emit FAIL
  fi

  local stamp
  if ! stamp="$(grep -m1 -E "$STAMP_RE" "$plan")"; then
    detail REASON no-adversarial-stamp
    emit FAIL
  fi

  local review_status rounds mode
  review_status="$(printf '%s' "$stamp" | sed -n 's/.*[[:space:]]status=\([^[:space:]]*\).*/\1/p')"
  rounds="$(printf '%s' "$stamp" | sed -n 's/.*[[:space:]]rounds=\([^[:space:]]*\).*/\1/p')"
  mode="$(printf '%s' "$stamp" | sed -n 's/.*[[:space:]]mode=\([^[:space:]]*\).*/\1/p')"

  detail REVIEW_STATUS "$review_status"
  detail ROUNDS "${rounds:-unknown}"
  detail MODE "${mode:-none}"

  # The only permitted local extension to the upstream grammar is mode=dreamer.
  if [ -n "$mode" ] && [ "$mode" != dreamer ]; then
    detail REASON unknown-mode
    emit FAIL
  fi
  emit OK
}

# --- findings ----------------------------------------------------------------
# Two accepted finding grammars, counted together:
#   FINDING id=<id> severity=<CRITICAL|HIGH|MEDIUM|LOW> status=<open|resolved|waived>
#   <!-- FINDING <id> (<severity>): <text> -->        (upstream marker; always open)
# Reported counts are OPEN findings per severity. Anything else on a FINDING
# line — unknown severity, missing status — is malformed and fails the gate
# closed: a findings file the gate cannot parse is never reported clean.
cmd_findings() {
  [ $# -eq 1 ] || { printf 'gate.sh: findings takes exactly one findings file\n' >&2; usage; }
  local file="$1"
  detail FINDINGS_FILE "$file"

  if [ ! -f "$file" ]; then
    detail REASON findings-file-missing
    emit FAIL
  fi

  local counts
  counts="$(awk '
    function bump(sev, st) {
      if (sev !~ /^(CRITICAL|HIGH|MEDIUM|LOW)$/) { bad++; return }
      if (st == "open") open[sev]++; else closed++
    }
    /^[[:space:]]*<!-- FINDING / {
      sev = "?"
      if (match($0, /\([A-Za-z]+\)/)) sev = toupper(substr($0, RSTART + 1, RLENGTH - 2))
      bump(sev, "open"); next
    }
    /^[[:space:]]*FINDING[[:space:]]/ {
      sev = ""; st = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^severity=/) sev = toupper(substr($i, 10))
        if ($i ~ /^status=/)   st  = tolower(substr($i, 8))
      }
      if (sev == "" || st !~ /^(open|resolved|waived)$/) { bad++; next }
      bump(sev, st); next
    }
    END {
      printf "%d %d %d %d %d %d\n", open["CRITICAL"], open["HIGH"], open["MEDIUM"], open["LOW"], closed, bad
    }
  ' "$file")"

  local crit high med low closed bad
  read -r crit high med low closed bad <<<"$counts"

  detail CRITICAL "$crit"
  detail HIGH "$high"
  detail MEDIUM "$med"
  detail LOW "$low"
  detail OPEN_TOTAL "$((crit + high + med + low))"
  detail CLOSED "$closed"
  detail MALFORMED "$bad"

  if [ "$bad" -gt 0 ]; then
    detail REASON malformed-finding
    emit FAIL
  fi
  if [ "$((crit + high))" -gt 0 ]; then
    detail REASON open-blocking-findings
    emit FAIL
  fi
  emit OK
}

# --- tests -------------------------------------------------------------------
# The test command is discovered from the repo, never assumed. MAD_DREAMER_TEST_CMD
# overrides discovery. Each candidate is skipped unless its runner is on PATH.
discover_test_cmd() {
  if [ -n "${MAD_DREAMER_TEST_CMD:-}" ]; then
    printf '%s\t%s\n' "$MAD_DREAMER_TEST_CMD" env
  elif [ -f justfile ] && have just && grep -qE '^test:' justfile; then
    printf '%s\t%s\n' 'just test' justfile
  elif [ -f Makefile ] && have make && grep -qE '^test:' Makefile; then
    printf '%s\t%s\n' 'make test' makefile
  elif [ -f package.json ] && have npm && have jq && jq -e '.scripts.test' package.json >/dev/null 2>&1; then
    printf '%s\t%s\n' 'npm test' package.json
  elif [ -f Cargo.toml ] && have cargo; then
    printf '%s\t%s\n' 'cargo test' cargo
  elif [ -f go.mod ] && have go; then
    printf '%s\t%s\n' 'go test ./...' go
  elif { [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f tox.ini ]; } && have python3; then
    printf '%s\t%s\n' 'python3 -m pytest' python
  elif have bats && compgen -G 'tests/*.bats' >/dev/null; then
    printf '%s\t%s\n' 'bats tests' bats
  else
    return 1
  fi
}

cmd_tests() {
  local threshold=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --coverage)
        threshold="${2:-}"
        [ -n "$threshold" ] || { printf 'gate.sh: tests: --coverage needs a percentage\n' >&2; usage; }
        case "$threshold" in
          ''|*[!0-9.]*) printf 'gate.sh: tests: --coverage must be numeric: %s\n' "$threshold" >&2; usage ;;
        esac
        shift 2
        ;;
      *) printf 'gate.sh: tests: unknown argument: %s\n' "$1" >&2; usage ;;
    esac
  done

  local found
  if ! found="$(discover_test_cmd)"; then
    detail REASON no-test-command
    emit FAIL
  fi
  local cmd source
  cmd="${found%%$'\t'*}"
  source="${found##*$'\t'}"
  detail TEST_CMD "$cmd"
  detail TEST_SOURCE "$source"

  local out rc=0
  out="$(bash -c "$cmd" 2>&1)" || rc=$?
  detail EXIT_CODE "$rc"
  if [ "$rc" -ne 0 ]; then
    printf '%s\n' "$out" >&2
    detail REASON tests-failed
    emit FAIL
  fi

  if [ -n "$threshold" ]; then
    detail COVERAGE_MIN "$threshold"
    local pct
    # `|| true`: no coverage figure is a verdict (REASON=no-coverage-figure),
    # not a reason for `set -o pipefail` to abort the gate before it reports.
    pct="$(printf '%s\n' "$out" | { grep -oE '[0-9]+(\.[0-9]+)?%' || true; } | tail -n1 | tr -d '%')"
    if [ -z "$pct" ]; then
      detail COVERAGE unknown
      detail REASON no-coverage-figure
      emit FAIL
    fi
    detail COVERAGE "$pct"
    if ! awk -v a="$pct" -v b="$threshold" 'BEGIN { exit !(a + 0 >= b + 0) }'; then
      detail REASON coverage-below-threshold
      emit FAIL
    fi
  fi
  emit OK
}

# --- report ------------------------------------------------------------------
cmd_report() {
  [ $# -eq 0 ] || { printf 'gate.sh: report takes no arguments\n' >&2; usage; }
  detail STATE_FILE "$STATE_FILE"

  if [ ! -f "$STATE_FILE" ]; then
    detail REASON state-missing
    emit FAIL
  fi
  if ! have jq; then
    detail REASON jq-missing
    emit FAIL
  fi
  if ! jq -e 'type == "object" and ((.gates // {}) | type == "object")' "$STATE_FILE" >/dev/null 2>&1; then
    detail REASON state-malformed
    emit FAIL
  fi

  detail RUN_ID "$(jq -r '.run_id // "none"' "$STATE_FILE")"
  detail PLAN "$(jq -r '.plan // "none"' "$STATE_FILE")"
  detail MODE "$(jq -r '.mode // "none"' "$STATE_FILE")"
  detail GATES_TOTAL "$(jq -r '(.gates // {}) | length' "$STATE_FILE")"
  detail GATES_OK "$(jq -r '[(.gates // {})[] | select(. == "OK")] | length' "$STATE_FILE")"
  detail GATES_FAIL "$(jq -r '[(.gates // {})[] | select(. != "OK")] | length' "$STATE_FILE")"
  emit OK
}

main() {
  [ $# -ge 1 ] || usage
  local sub="$1"; shift
  case "$sub" in
    preflight)     cmd_preflight "$@" ;;
    plan-contract) cmd_plan_contract "$@" ;;
    stamp)         cmd_stamp "$@" ;;
    findings)      cmd_findings "$@" ;;
    tests)         cmd_tests "$@" ;;
    report)        cmd_report "$@" ;;
    -h|--help)     usage ;;
    *)             printf 'gate.sh: unknown subcommand: %s\n' "$sub" >&2; usage ;;
  esac
}

main "$@"
