# Fixture config root

A deliberately imperfect Claude config, used by `tests/measure.bats` to exercise
`scripts/measure.py` and the retention gate. Nothing here is loaded by the plugin.

## Rules

- Run `just test` before pushing.
- Never run a destructive command against the production database.
- Version pin: the toolchain is `>=1.10`.
