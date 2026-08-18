---
description: Turn a goal into a contract-valid, adversarially-stamped plan — batched decisions, thresholded review.
argument-hint: "<goal> [plan-file]"
---

Build a mad-dreamer plan for the goal: $ARGUMENTS

Invoke the Skill tool with skill `mad-dreamer:plan` and follow it exactly.
Every open decision is batched into one `AskUserQuestion` call — never ask the
user one question per turn.
