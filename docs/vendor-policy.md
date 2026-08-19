# Vendor policy

dreamer owns the plan contract it enforces. It does not read a crewforge5
install at runtime, does not resolve a plugin root, and does not degrade if
crewforge5 is absent or a different version. The contract logic is **vendored**:
copied into `scripts/vendor/` and pinned to one upstream commit.

## What is vendored

| Vendored file | Upstream path |
| --- | --- |
| `scripts/vendor/validate_plan_path.sh` | `skills/team-sprint/scripts/validate_plan_path.sh` |
| `scripts/vendor/parse_stories.sh` | `skills/team-sprint/scripts/parse_stories.sh` |
| `scripts/vendor/build_graph.sh` | `skills/team-sprint/scripts/build_graph.sh` |
| `scripts/vendor/retention_gate.sh` | `scripts/retention_gate.sh` |
| `tests/fixtures/golden-template-1.md` | `skills/team-sprint/scripts/fixtures/golden-template-1.md` |

Source repo: `crewforge5`
Source commit: `a9d48ac538d2fd55f02b4c9ce082055b50485a33` (plugin cache 0.4.2)
Vendored: 2026-08-18

Every vendored script carries that provenance in a header directly under its
shebang. The header is the record — do not edit a vendored script in place; see
[Re-vendoring](#re-vendoring) instead.

## Local modifications

**Path resolution only.** No executable line of any vendored script differs from
upstream. None of the four resolved a plugin root, sourced a shared library, or
referenced a sibling script, so no path-resolution rewrite was needed at all —
they were already self-contained, which is why they were the ones chosen.

One non-executable deviation exists, recorded here in full:

- `scripts/vendor/build_graph.sh` — a comment pointed at an upstream `references/`
  phase document that does not ship in this repo. The pointer was replaced with a
  pointer to this file. Nothing else on that line or any other changed.

To confirm that claim against the upstream copy (`$CF5` = the pinned checkout),
strip each header and diff:

```sh
diff <(tail -n +8 scripts/vendor/parse_stories.sh) \
     <(tail -n +2 "$CF5/skills/team-sprint/scripts/parse_stories.sh")
```

`build_graph.sh` has an 8-line header (6 mandated + 2 recording the comment
deviation), so use `tail -n +10` for it; the only diff is the comment line above.

## The adversarial-review stamp

`gate.sh stamp` accepts and dreamer emits the same stamp line upstream
writes, on the line directly under the plan's `#` title:

```
<!-- adversarial-review: status=<clean|user-override> rounds=<N> date=<YYYY-MM-DD> reviewer=<name> -->
```

### How the contract identity was verified

The upstream gate does not parse the stamp with a library; it greps it. The
authoritative check is in `skills/execute/scripts/phase_gate.sh`, `gate_1()`:

```sh
grep -qm1 -E '^<!-- adversarial-review: status=(clean|user-override) ' "$plan" \
  || fail no-adversarial-stamp
```

A second reader, `skills/team-sprint-planner/scripts/plan_readback.sh`, matches
the same prefix (`l.startswith("<!-- adversarial-review: ")`), and
`skills/team-sprint-planner/references/plan-contract.md` documents the field
order the planner emits.

`scripts/gate.sh` holds that regex character-for-character:

```sh
STAMP_RE='^<!-- adversarial-review: status=(clean|user-override) '
```

Three properties follow from copying the regex rather than re-deriving it:

1. **`status` stays first.** The upstream pattern requires `status=` immediately
   after `adversarial-review: `, and a literal space immediately after the status
   value. Any dreamer extension must therefore be appended, never prepended.
2. **Both upstream statuses pass.** `clean` and `user-override` are accepted here
   exactly as upstream accepts them; `gate.sh stamp` reports which one it found as
   `REVIEW_STATUS=`.
3. **An upstream-stamped plan passes unmodified**, and a dreamer-stamped plan
   passes an upstream gate unmodified. The extension is additive by construction.

### The one permitted extension

```
<!-- adversarial-review: status=clean rounds=2 date=2026-08-18 reviewer=dreamer mode=dreamer -->
```

`mode=dreamer` is the only field dreamer adds. Upstream's regex ignores
trailing fields, so the extended stamp still matches it byte-for-byte through the
anchored prefix. `gate.sh stamp` reports `MODE=dreamer` when present and
`MODE=none` for an unextended upstream stamp, and **fails** on any other `mode=`
value — an unrecognised mode means some third tool has claimed the same stamp,
which is a contract collision, not a pass.

Regression cover: `tests/gate.bats` pins all four cases — extended stamp, plain
upstream stamp (`status=user-override`, `MODE=none`), a status outside the
grammar (`status=dirty` → `no-adversarial-stamp`), and a foreign
`mode=` (→ `unknown-mode`).

## Contract identity proof

`gate.sh plan-contract` is run in CI against an unmodified copy of upstream's own
golden fixture, `tests/fixtures/golden-template-1.md`. Passing it means the
vendored chain — plan-path validation, story parse, work-graph synthesis —
produces the result upstream's fixture was written to assert: 6 stories, 6 graph
nodes, 3 edges (2 declared, 1 inferred). If a future edit to the vendored scripts
changed the contract, that test fails.

## Drift stance

**The vendor is pinned. Drift is informational. Re-vendoring is deliberate.**

- The pinned copy is what runs. dreamer's behaviour never changes because
  someone upgraded, downgraded or removed their crewforge5 plugin.
- A drift check — diffing `scripts/vendor/` against a newer upstream — is a
  **report, not a gate**. It never fails a build, never blocks a release, and is
  never run automatically as part of `gate.sh`. Upstream moving is news, not a
  defect in this repo.
- When upstream changes the contract in a way worth adopting, the response is a
  **deliberate re-vendor with a version bump**, not a silent sync.

`tests/no_crewforge_refs.bats` enforces the other half of the stance: no shipped
file may name an upstream root variable, an upstream script path, or an upstream
document path. A vendored copy that still points home is not vendored.

## Re-vendoring

1. Decide the change is worth adopting — read the upstream diff first. A
   contract change (stamp grammar, story-heading shapes, graph semantics) is the
   only reason that qualifies; upstream refactors that leave the contract intact
   are not.
2. Re-copy the affected script(s) verbatim, re-apply the provenance header with
   the new `source-commit` and `vendored-date`, and re-record any deviation in
   the [Local modifications](#local-modifications) section above.
3. Re-vendor `tests/fixtures/golden-template-1.md` from the same commit, so the
   contract-identity proof tests the contract you actually adopted.
4. Run `bats tests/` and `shellcheck scripts/*.sh scripts/vendor/*.sh`. Both must
   be green before the re-vendor lands.
5. Bump dreamer's version. A changed plan contract is a changed public
   interface, whatever the diff size says.
