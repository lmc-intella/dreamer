g_session:
    @gemini --approval-mode yolo

# interactive Claude shell on Opus, permissions off
opus:
    @claude --dangerously-skip-permissions --model opus "/caveman"

# interactive Claude shell on Fable, permissions off
fable:
    @claude --dangerously-skip-permissions --model fable "/caveman"