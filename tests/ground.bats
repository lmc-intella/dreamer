#!/usr/bin/env bats
#
# ground.bats — scripts/ground.sh, both providers.
#
# Hermetic: every test builds its own git repo from tests/fixtures/ground-repo
# inside $BATS_TEST_TMPDIR. Nothing reads or writes $HOME, the developer's real
# repositories, or the dreamer checkout itself.
#
# Provider selection is exercised through PATH only — no install, no uninstall,
# no flag. `no_repomix_path` drops every PATH entry that holds a repomix binary;
# `stub_repomix` prepends a directory holding a fake one that writes the pack
# shape the real tool writes. The real binary is used too, when present, so the
# stub cannot silently drift from it.

setup() {
  GROUND="$BATS_TEST_DIRNAME/../scripts/ground.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  cp -R "$BATS_TEST_DIRNAME/fixtures/ground-repo/." "$REPO/"
  git -C "$REPO" init -q
  git -C "$REPO" add -A
}

# PATH with every directory that contains a repomix binary removed.
no_repomix_path() {
  local out="" d
  local -a dirs
  IFS=: read -ra dirs <<<"$PATH"
  for d in "${dirs[@]}"; do
    [ -n "$d" ] || continue
    [ -x "$d/repomix" ] && continue
    out="${out:+$out:}$d"
  done
  printf '%s' "$out"
}

# A fake repomix on the front of PATH. Writes the XML pack shape the real tool
# writes (`<file path="...">` … `</file>`), so the repomix code path is covered
# on a machine that has never installed it. $1 = exit code (default 0).
stub_repomix() {
  local rc="${1:-0}"
  mkdir -p "$BATS_TEST_TMPDIR/stub"
  cat >"$BATS_TEST_TMPDIR/stub/repomix" <<STUB
#!/usr/bin/env bash
[ "$rc" -eq 0 ] || exit "$rc"
out=""; root="."
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) out="\$2"; shift 2 ;;
    --*) shift ;;
    *) root="\$1"; shift ;;
  esac
done
{
  echo "<files>"
  echo "This section contains the contents of the repository's files."
  echo
  cd "\$root" || exit 1
  find . -type f -not -path './.git/*' | sed 's|^\./||' | sort | while read -r f; do
    printf '<file path="%s">\n' "\$f"
    cat "\$f"
    printf '</file>\n\n'
  done
  echo "</files>"
} >"\$out"
STUB
  chmod +x "$BATS_TEST_TMPDIR/stub/repomix"
  printf '%s' "$BATS_TEST_TMPDIR/stub"
}

assert_has() {
  [[ "$output" == *"$1"* ]] || {
    echo "expected to find: $1"
    echo "actual output:"
    echo "$output"
    return 1
  }
}

# --- fallback provider -------------------------------------------------------

@test "fallback: git ls-files provider grounds a repo with no repomix on PATH" {
  PATH="$(no_repomix_path)" run bash "$GROUND" --root "$REPO" load_config
  [ "$status" -eq 0 ]
  assert_has 'STATUS=OK'
  assert_has 'PROVIDER=git-ls-files'
  assert_has 'FILES=4'
  assert_has 'HITS=7'
  assert_has 'src/config.py:6:def load_config(path):'
}

@test "fallback: only tracked files are grounded" {
  printf 'load_config load_config\n' >"$REPO/untracked.py"
  PATH="$(no_repomix_path)" run bash "$GROUND" --root "$REPO" load_config
  [ "$status" -eq 0 ]
  [[ "$output" != *untracked.py* ]] || {
    echo "untracked file leaked into the pack:"; echo "$output"; return 1
  }
}

@test "fallback: a binary tracked file is skipped, not scanned" {
  printf 'load_config\000\001\002binary\n' >"$REPO/blob.bin"
  git -C "$REPO" add blob.bin
  PATH="$(no_repomix_path)" run bash "$GROUND" --root "$REPO" load_config
  [ "$status" -eq 0 ]
  assert_has 'FILES=4'
  [[ "$output" != *blob.bin* ]] || { echo "binary scanned:"; echo "$output"; return 1; }
}

# --- repomix provider --------------------------------------------------------

@test "repomix: a repomix on PATH is used and reports the same hits" {
  PATH="$(stub_repomix):$(no_repomix_path)" run bash "$GROUND" --root "$REPO" load_config
  [ "$status" -eq 0 ]
  assert_has 'PROVIDER=repomix'
  assert_has 'FILES=4'
  assert_has 'HITS=7'
  assert_has 'src/config.py:6:def load_config(path):'
}

@test "repomix: the real binary, when installed, agrees with the fallback" {
  command -v repomix >/dev/null 2>&1 || skip "repomix not installed"
  run bash "$GROUND" --root "$REPO" load_config
  [ "$status" -eq 0 ]
  assert_has 'PROVIDER=repomix'
  assert_has 'HITS=7'
  assert_has 'src/config.py:6:def load_config(path):'
}

@test "repomix: a failing repomix falls back to git ls-files instead of failing" {
  PATH="$(stub_repomix 1):$(no_repomix_path)" run bash "$GROUND" --root "$REPO" load_config
  [ "$status" -eq 0 ]
  assert_has 'PROVIDER=git-ls-files'
  assert_has 'HITS=7'
}

# --- matching semantics ------------------------------------------------------

@test "terms match case-insensitively" {
  PATH="$(no_repomix_path)" run bash "$GROUND" --root "$REPO" defaults
  [ "$status" -eq 0 ]
  assert_has 'src/config.py:3:DEFAULTS = {"port": 8080, "workers": 1}'
}

@test "terms are fixed strings, not regexes" {
  PATH="$(no_repomix_path)" run bash "$GROUND" --root "$REPO" 'dict(DEFAULTS)'
  [ "$status" -eq 0 ]
  assert_has 'HITS=1'
  assert_has 'src/config.py:11:    values = dict(DEFAULTS)'
}

@test "every term is scanned in one pass and gets its own block" {
  PATH="$(no_repomix_path)" run bash "$GROUND" --root "$REPO" load_config Service nosuchterm
  [ "$status" -eq 0 ]
  assert_has 'TERMS=3'
  assert_has '## load_config'
  assert_has '## Service'
  assert_has '## nosuchterm'
  assert_has 'HITS=0'
}

@test "--max caps the lines shown but never the reported total" {
  PATH="$(no_repomix_path)" run bash "$GROUND" --root "$REPO" --max 2 load_config
  [ "$status" -eq 0 ]
  assert_has 'MAX=2'
  assert_has 'HITS=7'
  [ "$(printf '%s\n' "$output" | grep -c 'load_config')" -le 4 ]
}

# --- failure and usage -------------------------------------------------------

@test "no provider: not a git repo and no repomix fails closed" {
  mkdir -p "$BATS_TEST_TMPDIR/bare"
  printf 'load_config\n' >"$BATS_TEST_TMPDIR/bare/x.py"
  PATH="$(no_repomix_path)" run bash "$GROUND" --root "$BATS_TEST_TMPDIR/bare" load_config
  [ "$status" -eq 1 ]
  assert_has 'STATUS=FAIL'
  assert_has 'REASON=no-provider'
}

@test "a missing root fails, it does not ground the current directory" {
  PATH="$(no_repomix_path)" run bash "$GROUND" --root "$BATS_TEST_TMPDIR/nope" load_config
  [ "$status" -eq 1 ]
  assert_has 'REASON=root-missing'
}

@test "usage errors exit 2: no terms, bad --max, unknown option" {
  run bash "$GROUND" --root "$REPO"
  [ "$status" -eq 2 ]
  run bash "$GROUND" --root "$REPO" --max abc load_config
  [ "$status" -eq 2 ]
  run bash "$GROUND" --root "$REPO" --nope load_config
  [ "$status" -eq 2 ]
}

@test "-- ends option parsing so a term may start with a dash" {
  PATH="$(no_repomix_path)" run bash "$GROUND" --root "$REPO" -- --nope
  [ "$status" -eq 0 ]
  assert_has '## --nope'
  assert_has 'HITS=0'
}

# --- read-only ---------------------------------------------------------------

@test "grounding writes nothing under the root" {
  before="$(cd "$REPO" && find . -not -path './.git/*' | sort)"
  PATH="$(no_repomix_path)" run bash "$GROUND" --root "$REPO" load_config
  [ "$status" -eq 0 ]
  after="$(cd "$REPO" && find . -not -path './.git/*' | sort)"
  [ "$before" = "$after" ] || { echo "root changed:"; diff <(echo "$before") <(echo "$after"); return 1; }
}
