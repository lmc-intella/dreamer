#!/usr/bin/env bats
#
# repomix.bats — scripts/repomix.sh: pack the repo to one xml file, then
# traverse that file.
#
# Hermetic: every test builds its own git repo from tests/fixtures/ground-repo
# inside $BATS_TEST_TMPDIR. Nothing reads or writes $HOME, the developer's real
# repositories, or the dreamer checkout itself.
#
# Provider selection is exercised through PATH only, exactly as ground.bats does
# it: `no_repomix_path` drops every PATH entry holding a repomix binary, and the
# real binary is used too when installed, so the two providers are held to the
# same pack shape.

setup() {
  RMX="$BATS_TEST_DIRNAME/../scripts/repomix.sh"
  GROUND="$BATS_TEST_DIRNAME/../scripts/ground.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  cp -R "$BATS_TEST_DIRNAME/fixtures/ground-repo/." "$REPO/"
  git -C "$REPO" init -q
  git -C "$REPO" add -A
  PACK="$REPO/.dreamer/repo.xml"
}

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

assert_has() {
  [[ "$output" == *"$1"* ]] || {
    echo "expected to find: $1"
    echo "actual output:"
    echo "$output"
    return 1
  }
}

# Pack with the fallback provider, so the pack exists on any machine.
pack_fallback() {
  PATH="$(no_repomix_path)" bash "$RMX" pack --root "$REPO" >/dev/null
}

# --- pack --------------------------------------------------------------------

@test "pack: writes one xml file at the default .dreamer/repo.xml path" {
  PATH="$(no_repomix_path)" run bash "$RMX" pack --root "$REPO"
  [ "$status" -eq 0 ]
  assert_has 'STATUS=OK'
  assert_has 'PROVIDER=git-ls-files'
  assert_has 'FILES=4'
  [ -s "$PACK" ]
  grep -q '^<file path="src/config.py">' "$PACK"
}

@test "pack: --out puts the pack where it is asked to" {
  PATH="$(no_repomix_path)" run bash "$RMX" pack --root "$REPO" --out "$BATS_TEST_TMPDIR/elsewhere/p.xml"
  [ "$status" -eq 0 ]
  assert_has "PACK=$BATS_TEST_TMPDIR/elsewhere/p.xml"
  [ -s "$BATS_TEST_TMPDIR/elsewhere/p.xml" ]
  [ ! -e "$PACK" ]
}

@test "pack: the real repomix, when installed, packs the same files" {
  command -v repomix >/dev/null 2>&1 || skip "repomix not installed"
  run bash "$RMX" pack --root "$REPO"
  [ "$status" -eq 0 ]
  assert_has 'PROVIDER=repomix'
  assert_has 'FILES=4'
  grep -q '^<file path="src/config.py">' "$PACK"
}

@test "pack: re-packing does not pack the pack into itself" {
  pack_fallback
  PATH="$(no_repomix_path)" run bash "$RMX" pack --root "$REPO"
  [ "$status" -eq 0 ]
  assert_has 'FILES=4'
  ! grep -q '^<file path=".dreamer/repo.xml">' "$PACK"
}

@test "pack: no repomix and no git work tree fails closed" {
  mkdir -p "$BATS_TEST_TMPDIR/bare"
  echo hi >"$BATS_TEST_TMPDIR/bare/a.txt"
  PATH="$(no_repomix_path)" run bash "$RMX" pack --root "$BATS_TEST_TMPDIR/bare"
  [ "$status" -eq 1 ]
  assert_has 'STATUS=FAIL'
  assert_has 'REASON=no-provider'
}

@test "pack: a missing root fails closed" {
  PATH="$(no_repomix_path)" run bash "$RMX" pack --root "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 1 ]
  assert_has 'REASON=root-missing'
}

# --- outline -----------------------------------------------------------------

@test "outline: maps directories and files with line counts" {
  pack_fallback
  run bash "$RMX" outline --pack "$PACK"
  [ "$status" -eq 0 ]
  assert_has 'STATUS=OK'
  assert_has 'FILES=4'
  assert_has '## directories'
  assert_has 'src FILES=2'
  assert_has '## files'
  assert_has 'src/config.py LINES=19'
}

@test "outline: --top caps the file list and reports what it dropped" {
  pack_fallback
  run bash "$RMX" outline --pack "$PACK" --top 2
  [ "$status" -eq 0 ]
  assert_has 'FILES=4'
  assert_has 'SHOWN=2'
  assert_has 'TRUNCATED=2'
}

@test "outline: a missing pack fails closed" {
  run bash "$RMX" outline --pack "$BATS_TEST_TMPDIR/nope.xml"
  [ "$status" -eq 1 ]
  assert_has 'REASON=pack-missing'
}

# --- show --------------------------------------------------------------------

@test "show: prints one file out of the pack, numbered" {
  pack_fallback
  run bash "$RMX" show src/config.py --pack "$PACK"
  [ "$status" -eq 0 ]
  assert_has 'STATUS=OK'
  assert_has 'FILE=src/config.py'
  assert_has 'LINES=19'
  assert_has '6:def load_config(path):'
}

@test "show: --from and --max window a file" {
  pack_fallback
  run bash "$RMX" show src/config.py --pack "$PACK" --from 6 --max 2
  [ "$status" -eq 0 ]
  assert_has 'SHOWN=2'
  assert_has '6:def load_config(path):'
  [[ "$output" != *'1:"""Config loading'* ]]
}

@test "show: a path that is not in the pack fails closed" {
  pack_fallback
  run bash "$RMX" show src/nosuch.py --pack "$PACK"
  [ "$status" -eq 1 ]
  assert_has 'REASON=file-not-in-pack'
}

# --- usage -------------------------------------------------------------------

@test "usage: an unknown subcommand is a usage error, not a verdict" {
  run bash "$RMX" bogus
  [ "$status" -eq 2 ]
  [[ "$output" != *STATUS=* ]]
}

@test "usage: show with no path is a usage error" {
  run bash "$RMX" show
  [ "$status" -eq 2 ]
}

# --- ground.sh reuses the pack -----------------------------------------------

@test "ground: --pack scans the existing pack instead of building one" {
  pack_fallback
  run bash "$GROUND" --root "$REPO" --pack "$PACK" load_config
  [ "$status" -eq 0 ]
  assert_has 'PROVIDER=pack'
  assert_has 'FILES=4'
  assert_has 'HITS=7'
  assert_has 'src/config.py:6:def load_config(path):'
}

@test "ground: --pack on a missing pack fails closed" {
  run bash "$GROUND" --root "$REPO" --pack "$BATS_TEST_TMPDIR/nope.xml" load_config
  [ "$status" -eq 1 ]
  assert_has 'REASON=pack-missing'
}
