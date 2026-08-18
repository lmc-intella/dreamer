#!/usr/bin/env bash
#
# ground.sh — self-contained repo grounding for the mad-dreamer plan skill.
#
#   ground.sh [--root <dir>] [--max <n>] [--] <term> [<term>...]
#
# Packs the repo ONCE and scans that pack for every term in a single pass, so
# grounding a plan costs one tool call no matter how many keywords the goal has.
#
# The provider is chosen by what is on PATH — never configured, never resolved
# from another repository or plugin:
#   repomix       `repomix` is on PATH: one XML pack of <root>.
#   git-ls-files  otherwise: the tracked files from `git ls-files`, assembled
#                 into the same `<file path="...">` pack shape, so one scanner
#                 serves both providers and both emit identical output.
# With neither a working repomix nor a git work tree the script fails
# (STATUS=FAIL REASON=no-provider) rather than guessing at a file list. It runs
# no skill, no agent and no script outside this repo.
#
# Terms are matched case-insensitively as FIXED strings, never as regexes: a
# goal keyword like `config.load()` must not have to be escaped by the caller.
#
# READ-ONLY on <root>. The pack is built inside a private `mktemp -d` scratch
# directory removed on exit; nothing is written under <root>.
#
# Binary and empty files are skipped by the git-ls-files provider (repomix does
# its own filtering). A source line that itself begins with `<file path="` would
# be read as a pack header — this is a grounding aid, not a parser.
#
# stdout — STATUS, then detail lines, then one block per term:
#   STATUS=OK|FAIL
#   PROVIDER=repomix|git-ls-files
#   ROOT=<abs>  FILES=<n>  TERMS=<n>  MAX=<n>          (one per line)
#   ## <term>
#   HITS=<n>                                   total matches, not just shown
#   <path>:<line>:<text>                       at most MAX lines, text cut at 160
# Exit codes: 0 OK | 1 FAIL | 2 usage error.
set -euo pipefail

MAX=12
ROOT=.
TERMS=()

usage() {
  cat >&2 <<'USAGE'
usage: ground.sh [--root <dir>] [--max <n>] [--] <term> [<term>...]
  --root <dir>   directory to ground in (default: .)
  --max <n>      hit lines shown per term (default: 12; HITS= always totals all)
USAGE
  exit 2
}

have() { command -v "$1" >/dev/null 2>&1; }

fail() {
  printf 'STATUS=FAIL\nREASON=%s\nROOT=%s\n' "$1" "$ROOT"
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-}"; [ -n "$ROOT" ] || usage; shift 2 ;;
    --max)
      MAX="${2:-}"
      case "$MAX" in ''|*[!0-9]*) printf 'ground.sh: --max must be a number\n' >&2; usage ;; esac
      shift 2
      ;;
    --) shift; TERMS+=("$@"); break ;;
    -h|--help) usage ;;
    -*) printf 'ground.sh: unknown option: %s\n' "$1" >&2; usage ;;
    *) TERMS+=("$1"); shift ;;
  esac
done

[ "${#TERMS[@]}" -gt 0 ] || usage
[ -d "$ROOT" ] || fail root-missing
ROOT="$(cd -- "$ROOT" && pwd)"

SCRATCH=""
cleanup() {
  if [ -n "$SCRATCH" ]; then rm -rf -- "$SCRATCH"; fi
}
trap cleanup EXIT

SCRATCH="$(mktemp -d)"
PACK="$SCRATCH/pack.xml"
PROVIDER=""

if have repomix; then
  if repomix --quiet --style xml --no-file-summary --no-directory-structure \
       -o "$PACK" "$ROOT" >/dev/null 2>&1 && [ -s "$PACK" ]; then
    PROVIDER=repomix
  fi
fi

if [ -z "$PROVIDER" ] && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  PROVIDER=git-ls-files
  : >"$PACK"
  while IFS= read -r -d '' f; do
    [ -f "$ROOT/$f" ] || continue
    LC_ALL=C grep -qI '^' -- "$ROOT/$f" 2>/dev/null || continue   # binary or empty
    printf '<file path="%s">\n' "$f"
    awk '{ print }' <"$ROOT/$f"
    printf '</file>\n\n'
  done < <(git -C "$ROOT" ls-files -z) >>"$PACK"
fi

[ -n "$PROVIDER" ] || fail no-provider

FILES="$( { grep -c '^<file path="' "$PACK" || true; } | tail -n1)"

printf 'STATUS=OK\nPROVIDER=%s\nROOT=%s\nFILES=%s\nTERMS=%s\nMAX=%s\n' \
  "$PROVIDER" "$ROOT" "$FILES" "${#TERMS[@]}" "$MAX"

for term in "${TERMS[@]}"; do
  printf '## %s\n' "$term"
  awk -v term="$term" -v max="$MAX" '
    BEGIN { lt = tolower(term); hits = 0; shown = 0 }
    /^<file path="/ {
      path = substr($0, 13)
      sub(/">[[:space:]]*$/, "", path)
      ln = 0
      next
    }
    $0 == "</file>" { path = ""; next }
    {
      ln++
      if (path != "" && index(tolower($0), lt) > 0) {
        hits++
        if (shown < max) { buf[++shown] = path ":" ln ":" substr($0, 1, 160) }
      }
    }
    END {
      printf "HITS=%d\n", hits
      for (i = 1; i <= shown; i++) print buf[i]
    }
  ' "$PACK"
done
