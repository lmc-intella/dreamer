---
description: Audit and slim this Claude config in one measured pass — measure, batch-fix CRITICAL/HIGH, re-measure, report.
argument-hint: "[config-root]"
---

Run the mad-dreamer init flow over $ARGUMENTS (default: this repo's `.claude/`
plus the user config root).

Invoke the Skill tool with skill `mad-dreamer:init` and follow it exactly. Do
not substitute a different audit flow, and do not expand the pass count — the
whole point of this command is one measured pass, one fix batch, one report.
