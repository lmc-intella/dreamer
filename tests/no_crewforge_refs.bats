#!/usr/bin/env bats

# dreamer is standalone: it vendors the plan contract and never reaches
# into a crewforge5 install at runtime. Three strings prove a reach-in, so no
# shipped file may contain them.
#
# Two paths are excluded, and only these two:
#   - this test file, which must name the strings to ban them;
#   - docs/dreamer-launch-1.md, the launch spec, which states the ban.
# Both mention the strings; neither resolves one.

repo_root() {
  cd "${BATS_TEST_DIRNAME}/.." && pwd
}

banned_hits() {
  local pattern="$1"
  cd "$(repo_root)" || return 1
  grep -rIn --exclude-dir=.git --exclude-dir=node_modules \
    --exclude='no_crewforge_refs.bats' \
    --exclude='dreamer-launch-1.md' \
    -e "$pattern" . || true
}

@test "no file references CREWFORGE5_ROOT" {
  run banned_hits 'CREWFORGE5_ROOT'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no file references scripts/flow/" {
  run banned_hits 'scripts/flow/'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no file references subskill_resolve.sh" {
  run banned_hits 'subskill_resolve\.sh'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no file references references/phases/" {
  run banned_hits 'references/phases/'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
