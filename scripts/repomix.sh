#!/usr/bin/env bash
#
# repomix.sh — pack the repo to one XML file, then traverse that file.
#
#   repomix.sh pack    [--root <dir>] [--out <file>]
#   repomix.sh outline [--pack <file>] [--top <n>]
#   repomix.sh show    <path> [--pack <file>] [--max <n>] [--from <line>]
#
# `pack` writes ONE xml pack of the repo — the artefact the plan and execute
# skills read the repo through, instead of re-listing and re-reading it. The
# provider is chosen by what is on PATH, never configured and never resolved
# from another repository or plugin:
#   repomix       `repomix` is on PATH: its xml pack of <root>.
#   git-ls-files  otherwise: the tracked files from `git ls-files`, assembled
#                 into the same `<file path="...">` pack shape.
# Both providers emit the same shape, so one traversal serves both. With
# neither a working repomix nor a git work tree it fails (REASON=no-provider).
#
# `outline` and `show` are the traversal: outline is the map (directories,
# files, line counts), show reads one file straight out of the pack, so
# understanding the repo costs pack-once plus greps, not a re-read per file.
#
# The pack is the ONLY thing written, at --out (default <root>/.dreamer/repo.xml
# — `.dreamer/` is a run-artefact directory, gitignored here and added to
# info/exclude by the execute skill). It is built in a private `mktemp -d` and
# moved into place, and it is never packed into itself.
#
# A source line that itself begins with `<file path="` or is exactly `</file>`
# would be read as a pack marker — this is a grounding aid, not a parser.
#
# stdout — STATUS, then KEY=VALUE detail lines, then the subcommand's body.
# Exit codes: 0 OK | 1 FAIL | 2 usage error.
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: repomix.sh <subcommand> [args]
  pack    [--root <dir>] [--out <file>]        build the xml pack (default:
                                               <root>/.dreamer/repo.xml)
  outline [--pack <file>] [--top <n>]          directory + file map of the pack
                                               (default: 200 files listed)
  show <path> [--pack <file>] [--max <n>] [--from <line>]
                                               one file's text, from the pack
USAGE
  exit 2
}

have() { command -v "$1" >/dev/null 2>&1; }

fail() {
  printf 'STATUS=FAIL\nREASON=%s\n' "$1"
  [ $# -lt 2 ] || printf '%s\n' "$2"
  exit 1
}

DEFAULT_PACK=".dreamer/repo.xml"

SCRATCH=""
cleanup() { [ -z "$SCRATCH" ] || rm -rf -- "$SCRATCH"; }
trap cleanup EXIT
scratch() { SCRATCH="$(mktemp -d)"; }

# --- pack --------------------------------------------------------------------

cmd_pack() {
  local ROOT=. OUT=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --root) ROOT="${2:-}"; [ -n "$ROOT" ] || usage; shift 2 ;;
      --out)  OUT="${2:-}";  [ -n "$OUT" ]  || usage; shift 2 ;;
      -h|--help) usage ;;
      *) printf 'repomix.sh pack: unexpected argument: %s\n' "$1" >&2; usage ;;
    esac
  done

  [ -d "$ROOT" ] || fail root-missing "ROOT=$ROOT"
  ROOT="$(cd -- "$ROOT" && pwd)"
  [ -n "$OUT" ] || OUT="$ROOT/$DEFAULT_PACK"
  case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac

  scratch
  local TMP="$SCRATCH/pack.xml" PROVIDER=""

  if have repomix; then
    if repomix --quiet --style xml --no-file-summary --no-directory-structure \
         --ignore '.dreamer/**' -o "$TMP" "$ROOT" >/dev/null 2>&1 && [ -s "$TMP" ]; then
      PROVIDER=repomix
    fi
  fi

  if [ -z "$PROVIDER" ] && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    PROVIDER=git-ls-files
    : >"$TMP"
    while IFS= read -r -d '' f; do
      case "$f" in .dreamer/*) continue ;; esac
      [ -f "$ROOT/$f" ] || continue
      LC_ALL=C grep -qI '^' -- "$ROOT/$f" 2>/dev/null || continue   # binary or empty
      printf '<file path="%s">\n' "$f"
      awk '{ print }' <"$ROOT/$f"
      printf '</file>\n\n'
    done < <(git -C "$ROOT" ls-files -z) >>"$TMP"
  fi

  [ -n "$PROVIDER" ] || fail no-provider "ROOT=$ROOT"

  mkdir -p -- "$(dirname -- "$OUT")" || fail out-unwritable "OUT=$OUT"
  cp -- "$TMP" "$OUT" || fail out-unwritable "OUT=$OUT"

  local FILES BYTES
  FILES="$( { grep -c '^<file path="' "$OUT" || true; } | tail -n1)"
  BYTES="$(wc -c <"$OUT" | tr -d ' ')"
  printf 'STATUS=OK\nPROVIDER=%s\nROOT=%s\nPACK=%s\nFILES=%s\nBYTES=%s\n' \
    "$PROVIDER" "$ROOT" "$OUT" "$FILES" "$BYTES"
}

# --- outline -----------------------------------------------------------------

cmd_outline() {
  local PACK="$DEFAULT_PACK" TOP=200
  while [ $# -gt 0 ]; do
    case "$1" in
      --pack) PACK="${2:-}"; [ -n "$PACK" ] || usage; shift 2 ;;
      --top)
        TOP="${2:-}"
        case "$TOP" in ''|*[!0-9]*) printf 'repomix.sh: --top must be a number\n' >&2; usage ;; esac
        shift 2
        ;;
      -h|--help) usage ;;
      *) printf 'repomix.sh outline: unexpected argument: %s\n' "$1" >&2; usage ;;
    esac
  done
  [ -s "$PACK" ] || fail pack-missing "PACK=$PACK"

  scratch

  awk -v top="$TOP" -v dirf="$SCRATCH/dirs" -v filef="$SCRATCH/files" '
    /^<file path="/ {
      path = substr($0, 13); sub(/">[[:space:]]*$/, "", path)
      files++
      ln = 0
      dir = path
      if (sub(/\/[^\/]*$/, "", dir) == 0) dir = "."
      next
    }
    $0 == "</file>" {
      if (path != "") {
        total += ln
        dcount[dir]++; dlines[dir] += ln
        if (files <= top) printf "%s LINES=%d\n", path, ln >filef
      }
      path = ""; next
    }
    { if (path != "") ln++ }
    END {
      for (d in dcount) printf "%s FILES=%d LINES=%d\n", d, dcount[d], dlines[d] >dirf
      printf "STATUS=OK\nFILES=%d\nLINES=%d\nSHOWN=%d\n", files, total, (files < top ? files : top)
      if (files > top) printf "TRUNCATED=%d\n", files - top
    }
  ' "$PACK"

  printf '## directories\n'
  if [ -s "$SCRATCH/dirs" ]; then LC_ALL=C sort "$SCRATCH/dirs"; fi
  printf '## files\n'
  if [ -s "$SCRATCH/files" ]; then cat "$SCRATCH/files"; fi
  return 0
}

# --- show --------------------------------------------------------------------

cmd_show() {
  local PACK="$DEFAULT_PACK" MAX=400 FROM=1 TARGET=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --pack) PACK="${2:-}"; [ -n "$PACK" ] || usage; shift 2 ;;
      --max)
        MAX="${2:-}"
        case "$MAX" in ''|*[!0-9]*) printf 'repomix.sh: --max must be a number\n' >&2; usage ;; esac
        shift 2 ;;
      --from)
        FROM="${2:-}"
        case "$FROM" in ''|*[!0-9]*) printf 'repomix.sh: --from must be a number\n' >&2; usage ;; esac
        shift 2 ;;
      -h|--help) usage ;;
      -*) printf 'repomix.sh show: unknown option: %s\n' "$1" >&2; usage ;;
      *) [ -z "$TARGET" ] || usage; TARGET="$1"; shift ;;
    esac
  done
  [ -n "$TARGET" ] || usage
  [ -s "$PACK" ] || fail pack-missing "PACK=$PACK"

  scratch

  awk -v want="$TARGET" -v max="$MAX" -v from="$FROM" -v body="$SCRATCH/body" '
    /^<file path="/ {
      path = substr($0, 13); sub(/">[[:space:]]*$/, "", path)
      hit = (path == want); if (hit) found = 1
      ln = 0; next
    }
    $0 == "</file>" { if (hit) total = ln; hit = 0; next }
    {
      if (!hit) next
      ln++
      if (ln < from) next
      if (shown >= max) { cut++; next }
      shown++
      printf "%d:%s\n", ln, $0 >body
    }
    END {
      if (!found) exit 3
      printf "LINES=%d\nSHOWN=%d\n", total, shown
      if (cut) printf "TRUNCATED=%d\n", cut
    }
  ' "$PACK" >"$SCRATCH/keys" || fail file-not-in-pack "FILE=$TARGET"

  printf 'STATUS=OK\nPACK=%s\nFILE=%s\n' "$PACK" "$TARGET"
  cat "$SCRATCH/keys"
  if [ -s "$SCRATCH/body" ]; then cat "$SCRATCH/body"; fi
  return 0
}

[ $# -gt 0 ] || usage
SUB="$1"; shift
case "$SUB" in
  pack)    cmd_pack "$@" ;;
  outline) cmd_outline "$@" ;;
  show)    cmd_show "$@" ;;
  -h|--help) usage ;;
  *) printf 'repomix.sh: unknown subcommand: %s\n' "$SUB" >&2; usage ;;
esac
