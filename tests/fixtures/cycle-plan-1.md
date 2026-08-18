# Cycle plan fixture — two stories that depend on each other

Fails `gate.sh plan-contract` at the build_graph step: Story 1 and Story 2
declare each other as dependencies, so the work graph has no topological order.

## Story 1: First half of the cycle

### Depends On: 2
### Touches: src/a.py

### Acceptance Criteria
- Does the first thing.

### Definition of Done
- Story tests green.

## Story 2: Second half of the cycle

### Depends On: 1
### Touches: src/b.py

### Acceptance Criteria
- Does the second thing.

### Definition of Done
- Story tests green.
