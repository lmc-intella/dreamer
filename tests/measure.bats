#!/usr/bin/env bats
#
# measure.bats — scripts/measure.py, and the retention-gate contract that
# skills/init/SKILL.md makes every edit pass through.
#
# Hermetic by construction. `tests/fixtures/init-config/` is a read-only
# template: every test copies it into $BATS_TEST_TMPDIR and works on the copy.
# Nothing here reads or writes $HOME, ~/.claude, or the repo outside
# tests/fixtures/. No test depends on another test's leftovers.

setup() {
  MEASURE="$BATS_TEST_DIRNAME/../scripts/measure.py"
  RETENTION="$BATS_TEST_DIRNAME/../scripts/vendor/retention_gate.sh"
  FIXTURE="$BATS_TEST_DIRNAME/fixtures/init-config"
  ROOT="$BATS_TEST_TMPDIR/config"
  cp -R "$FIXTURE" "$ROOT"
  GUARD="$ROOT/skills/retention-guard/SKILL.md"
  BLOAT="$ROOT/skills/bloated-notes/SKILL.md"
  # The one line the whole fixture exists to protect.
  NEVER_LINE='Never delete a line marked as never-remove'
}

measure() { python3 "$MEASURE" "$1"; }

# chars of one component, by its path key in the JSON report.
chars_of() {
  measure "$1" | jq -r --arg p "$2" '.components[] | select(.path == $p) | .chars'
}

# --- measure.py: shape ------------------------------------------------------

@test "measure: emits parseable JSON with the documented top-level keys" {
  run python3 "$MEASURE" "$ROOT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '
    has("root") and has("chars_per_token") and has("components")
    and has("by_kind") and has("totals")' >/dev/null
}

@test "measure: finds every skill, agent and instruction file in the fixture" {
  local json
  json="$(measure "$ROOT")"
  [ "$(echo "$json" | jq '[.components[] | select(.kind == "skill")] | length')" -ge 5 ]
  [ "$(echo "$json" | jq '[.components[] | select(.kind == "agent")] | length')" -eq 2 ]
  [ "$(echo "$json" | jq '[.components[] | select(.kind == "instructions")] | length')" -eq 1 ]
}

@test "measure: per-file chars match the file on disk" {
  local reported actual
  reported="$(chars_of "$ROOT" "skills/retention-guard/SKILL.md")"
  actual="$(python3 -c 'import sys;print(len(open(sys.argv[1],encoding="utf-8").read()))' "$GUARD")"
  [ "$reported" = "$actual" ]
}

@test "measure: est_tokens is ceil(chars / 4) for every component" {
  run bash -c "python3 '$MEASURE' '$ROOT' | jq -e '
    [.components[] | select(.est_tokens != (((.chars + 3) / 4) | floor))] | length == 0'"
  [ "$status" -eq 0 ]
}

@test "measure: skill support files are counted separately from SKILL.md" {
  local json
  json="$(measure "$ROOT")"
  local entry
  entry="$(echo "$json" | jq -c '.components[] | select(.name == "bloated-notes")')"
  [ "$(echo "$entry" | jq '.support_files')" -eq 1 ]
  [ "$(echo "$entry" | jq '.support_chars')" -gt 0 ]
  # SKILL.md's own figure must not have absorbed the support file.
  local skill_chars actual
  skill_chars="$(echo "$entry" | jq '.chars')"
  actual="$(python3 -c 'import sys;print(len(open(sys.argv[1],encoding="utf-8").read()))' "$BLOAT")"
  [ "$skill_chars" = "$actual" ]
}

@test "measure: totals equal the sum of components plus support files" {
  run bash -c "python3 '$MEASURE' '$ROOT' | jq -e '
    .totals.chars == ([.components[] | .chars + (.support_chars // 0)] | add)'"
  [ "$status" -eq 0 ]
}

@test "measure: skips .git and other noise directories" {
  mkdir -p "$ROOT/.git" "$ROOT/skills/deploy-check/node_modules"
  printf 'x%.0s' $(seq 1 500) >"$ROOT/.git/CLAUDE.md"
  printf 'y%.0s' $(seq 1 500) >"$ROOT/skills/deploy-check/node_modules/blob.md"
  local json
  json="$(measure "$ROOT")"
  [ -z "$(echo "$json" | jq -r '.components[] | select(.path | test("\\.git|node_modules"))')" ]
  [ "$(echo "$json" | jq '[.components[] | select(.name == "deploy-check")][0].support_chars')" -eq 0 ]
}

@test "measure: an empty root is a valid report, not a crash" {
  mkdir -p "$BATS_TEST_TMPDIR/bare"
  run python3 "$MEASURE" "$BATS_TEST_TMPDIR/bare"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.totals.files == 0 and .totals.chars == 0' >/dev/null
}

@test "measure: a non-directory argument exits 2" {
  run python3 "$MEASURE" "$BATS_TEST_TMPDIR/does-not-exist"
  [ "$status" -eq 2 ]
}

# --- the retention contract -------------------------------------------------

@test "fixture: the never-remove line is present before anything runs" {
  grep -qF "$NEVER_LINE" "$GUARD"
}

@test "retention: a filler-only trim passes the gate and shrinks the config" {
  local before after
  before="$(measure "$ROOT" | jq '.totals.chars')"

  cp "$BLOAT" "$BLOAT.bak"
  grep -v '^Filler paragraph' "$BLOAT.bak" >"$BLOAT"

  run bash "$RETENTION" "$BLOAT.bak" "$BLOAT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS:"* ]]

  rm "$BLOAT.bak"
  after="$(measure "$ROOT" | jq '.totals.chars')"
  [ "$after" -lt "$before" ]
}

# This is the load-bearing test of Story 2. A trim that deletes a never-remove
# line must be REVERTED and REPORTED, never silently applied. It runs the exact
# sequence skills/init/SKILL.md mandates: back up, edit, gate, restore on FAIL.
@test "retention: an edit deleting a never-remove line is reverted, not applied" {
  local original_sum
  original_sum="$(md5sum <"$GUARD" | cut -d' ' -f1)"

  # 1. back up the original, then apply the proposed trim in place
  cp "$GUARD" "$GUARD.bak"
  grep -vF "$NEVER_LINE" "$GUARD.bak" >"$GUARD"
  if grep -qF "$NEVER_LINE" "$GUARD"; then   # the edit really did remove it
    echo "the proposed edit did not remove the never-remove line"
    return 1
  fi

  # 2. the gate rejects it, and names the loss so the report can quote it
  run bash "$RETENTION" "$GUARD.bak" "$GUARD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: directive lost:"* ]]
  [[ "$output" == *"$NEVER_LINE"* ]]
  [[ "$output" == *"not safe to apply"* ]]

  # 3. the mandated revert: restore, byte for byte
  mv "$GUARD.bak" "$GUARD"
  grep -qF "$NEVER_LINE" "$GUARD"
  [ "$(md5sum <"$GUARD" | cut -d' ' -f1)" = "$original_sum" ]
  [ ! -e "$GUARD.bak" ]
}

@test "retention: the gate refuses a missing file rather than passing it" {
  run bash "$RETENTION" "$GUARD" "$BATS_TEST_TMPDIR/nope.md"
  [ "$status" -eq 2 ]
}

# --- end to end -------------------------------------------------------------

# One measured pass over the fixture root: measure, apply one safe fix, attempt
# one unsafe fix and revert it, re-measure. Asserts what the report must carry.
@test "end to end: safe fix applied, unsafe fix reverted, never-line survives" {
  local before_json after_json
  before_json="$BATS_TEST_TMPDIR/before.json"
  after_json="$BATS_TEST_TMPDIR/after.json"
  measure "$ROOT" >"$before_json"

  # applied: filler removal from the padded skill
  cp "$BLOAT" "$BLOAT.bak"
  grep -v '^Filler paragraph' "$BLOAT.bak" >"$BLOAT"
  run bash "$RETENTION" "$BLOAT.bak" "$BLOAT"
  [ "$status" -eq 0 ]
  rm "$BLOAT.bak"

  # reverted: a trim of the guard skill that drops the never-remove line
  cp "$GUARD" "$GUARD.bak"
  grep -vF "$NEVER_LINE" "$GUARD.bak" >"$GUARD"
  run bash "$RETENTION" "$GUARD.bak" "$GUARD"
  [ "$status" -eq 1 ]
  mv "$GUARD.bak" "$GUARD"

  measure "$ROOT" >"$after_json"

  # the never line survived the whole pass
  grep -qF "$NEVER_LINE" "$GUARD"

  # before/after chars: the config got smaller, and only the safe fix moved
  local before_chars after_chars guard_before guard_after
  before_chars="$(jq '.totals.chars' "$before_json")"
  after_chars="$(jq '.totals.chars' "$after_json")"
  [ "$after_chars" -lt "$before_chars" ]

  guard_before="$(jq -r '.components[] | select(.name == "retention-guard") | .chars' "$before_json")"
  guard_after="$(jq -r '.components[] | select(.name == "retention-guard") | .chars' "$after_json")"
  [ "$guard_before" = "$guard_after" ]

  # per-component figures are available for every component, so the report's
  # grade table has a char column for each.
  [ "$(jq '[.components[] | select(.chars == null)] | length' "$after_json")" -eq 0 ]

  # no backup files left behind by either path
  [ -z "$(find "$ROOT" -name '*.bak')" ]
}
