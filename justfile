g_session:
    @gemini --approval-mode yolo

# interactive Claude shell on Opus, permissions off
opus:
    @claude --dangerously-skip-permissions --model opus "/caveman"

# interactive Claude shell on Fable, permissions off
fable:
    @claude --dangerously-skip-permissions --model fable "/caveman"
# validate the plugin manifest, run the gates, then tag the release and push it.
# `just publish --dry-run` prints the tag it would create and pushes nothing.
publish FLAGS='--push':
    #!/usr/bin/env bash
    set -euo pipefail
    claude plugin validate --strict .claude-plugin/plugin.json
    find scripts -name '*.sh' -type f -print0 | sort -z | xargs -0 shellcheck
    bats tests/
    claude plugin tag {{FLAGS}} .
