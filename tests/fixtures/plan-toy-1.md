# plan-toy-1 — validate toy-service config against a schema before start
<!-- adversarial-review: status=clean rounds=2 date=2026-08-18 reviewer=dreamer mode=dreamer -->

The worked end-to-end output of `skills/plan/SKILL.md` run on one toy goal —
"reject a bad config before the service starts" — against the fixture repo at
tests/fixtures/ground-repo. Grounded with:

    scripts/ground.sh --root <ground-repo> --max 6 load_config Service schema port workers

which reported PROVIDER=repomix FILES=4 and located `load_config` (src/config.py:6),
`Service.start` (src/service.py:10) and the untyped `DEFAULTS` (src/config.py:3).
Every story below names a file that grounding actually found.

Read-only fixture: tests/ground.bats copies the repo it plans against, and
tests/gate.bats-style gate runs read this plan without writing to it.

## Assumptions
- Config stays the flat `key: value` text format `load_config` already parses
  (src/config.py:11-19); grounding found no YAML or TOML dependency to adopt.
- The schema lives in the same `src/` package as its two callers — grounding
  found no existing `schema`, `validate` or `models` module to extend.

## Story 1: Declare the config schema

A single declarative table of key -> (type, required) so both the loader and the
service read one definition instead of two copies of the same assumptions.

### Depends On: none
### Touches: src/schema.py, tests/test_schema.py

### Acceptance Criteria
- `SCHEMA` names every key in `DEFAULTS` (`port`, `workers`) with its type.
- `coerce(key, raw)` returns the typed value, and raises `SchemaError` naming the
  key when the raw string cannot be coerced.
- `SchemaError` carries the offending key in `.key`, not only in its message.

### Definition of Done
- Story tests green; typecheck + lint clean.

## Story 2: Validate on load

`load_config` currently merges whatever the file contained over `DEFAULTS` and
returns strings for every key it read (src/config.py:11-19).

### Depends On: 1
### Touches: src/config.py, tests/test_config.py

### Acceptance Criteria
- `load_config` coerces each parsed value through the schema, so `port` is an int.
- An unknown key raises `SchemaError` naming that key, before any value is returned.
- The existing defaults test still passes unchanged: a config that sets only
  `port` still yields `workers == 1`.

### Definition of Done
- Story tests green; typecheck + lint clean.

## Story 3: Fail before listening

`Service.start` casts `self.config["port"]` itself (src/service.py:11) — a cast
that becomes dead once Story 2 lands, and a second place to keep in step.

### Depends On: 2
### Touches: src/service.py, tests/test_service.py

### Acceptance Criteria
- `Service.start` uses `self.config["port"]` as an int, with no cast of its own.
- `main()` propagates `SchemaError` from `load_config` — the service never reaches
  `start()` with a config the schema rejected.

### Definition of Done
- Story tests green; typecheck + lint clean.

## Review notes

MEDIUM and LOW findings from the review pass, applied in place without a loop —
recorded here because only CRITICAL/HIGH re-open the review (2 rounds run).

- MEDIUM — Story 2's original AC said "validates the config", which no test can
  fail. Rewritten as the two observable behaviours (coercion, unknown-key raise).
- MEDIUM — Stories 2 and 3 both touched `src/config.py` in the first draft, which
  would have made the two stories race on one file. Story 3's touch list narrowed
  to `src/service.py` and its test.
- LOW — `SchemaError.key` added to Story 1's AC: Story 2 asserts the key is named,
  which needs a field to assert on rather than a message substring.
- LOW — Story 3 records that the int cast in `Service.start` becomes dead code,
  so the story deletes it rather than leaving two coercion sites.

<!--
Interop cross-check — dev machine, 2026-08-18, crewforge5 0.4.2 from the plugin
cache. This plan passes full crewforge5 execute Phase 0 and Phase 1 gates
unmodified. The gate script derives its own plugin root from its location, so no
environment wiring is needed; it is run in a throwaway git repo outside this
checkout because Phase 0 resolves the sprint dir relative to $PWD.

  CF5="$HOME/.claude/plugins/cache/crewforge5/crewforge5/0.4.2"
  cd "$(mktemp -d)" && git init -q .
  cp <dreamer>/tests/fixtures/plan-toy-1.md .
  mkdir -p .crewforge5/execute
  printf '{"flow":"execute","started_at":"2026-08-18T00:00:00Z","phase":{},"plan":"plan-toy-1.md"}\n' \
    > .crewforge5/execute/state.json
  bash "$CF5/skills/execute/scripts/phase_gate.sh" 0
  bash "$CF5/skills/execute/scripts/phase_gate.sh" 1

Literal output, one line per gate:

  STATUS=PASS
  STATUS=PASS

Phase 0 is the plan-path contract plus sub-skill presence; Phase 1 is the
adversarial stamp (the same status=(clean|user-override) grep gate.sh vendors)
plus a fold-clean findings check. Both gates only read the plan. The state.json
seed replaces the interactive intake that would normally record the plan path —
it is the only step that could not be run non-interactively.
-->
