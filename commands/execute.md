---
description: Drive a stamped plan to a merged commit — isolated worktree, per-story TDD, tests + coverage gate.
argument-hint: "<plan-file> [--rigour fast|standard] [--pr]"
---

Execute the plan named in $ARGUMENTS.

Invoke the Skill tool with skill `mad-dreamer:execute` and follow it exactly.
The stamp check is a hard STOP with no override: an unstamped or unclean plan
does not run.
