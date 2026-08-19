#!/usr/bin/env python3
"""measure.py — context-load measurement for one Claude config root.

    measure.py <config-root>          # JSON report on stdout

Walks a config root — a `.claude` directory, a plugin repo, or any tree holding
`CLAUDE.md`, `skills/` and `agents/` — and reports per component and in total how
many characters it costs and roughly how many tokens that is. Standard library
only; reads files, writes nothing, makes no network call.

TOKEN ESTIMATE — AN ESTIMATE, NOT A TOKENIZER.
`est_tokens = ceil(chars / 4)`. Four characters per token is the common rule of
thumb for English prose under byte-pair encodings, and it is the whole basis of
the number: no tokenizer is run and no vocabulary is consulted, so it carries no
accuracy guarantee for code, tables or non-Latin text. A delta between two runs
of this script is meaningful; an absolute count is not.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

CHARS_PER_TOKEN = 4
SKIP_DIRS = {".git", ".hg", "node_modules", "__pycache__", ".venv", ".dreamer"}
INSTRUCTION_FILES = ("CLAUDE.md", "CLAUDE.local.md")


def est_tokens(chars: int) -> int:
    return math.ceil(chars / CHARS_PER_TOKEN)


def skipped(path: Path, base: Path) -> bool:
    return any(part in SKIP_DIRS for part in path.relative_to(base).parts)


def chars_of(path: Path) -> int:
    return len(path.read_text(encoding="utf-8", errors="replace"))


def component(path: Path, base: Path, kind: str, name: str) -> dict:
    text = path.read_text(encoding="utf-8", errors="replace")
    return {
        "path": path.relative_to(base).as_posix(),
        "kind": kind,
        "name": name,
        "chars": len(text),
        "lines": len(text.splitlines()),
        "est_tokens": est_tokens(len(text)),
    }


def collect(base: Path) -> list[dict]:
    """Every measured component, in report order: instructions, skills, agents."""
    found: list[dict] = []

    for name in INSTRUCTION_FILES:
        if (base / name).is_file():
            found.append(component(base / name, base, "instructions", name))

    skills_dir = base / "skills"
    if skills_dir.is_dir():
        for skill_md in sorted(skills_dir.rglob("SKILL.md")):
            if skipped(skill_md, base):
                continue
            skill_dir = skill_md.parent
            entry = component(
                skill_md, base, "skill", skill_dir.relative_to(skills_dir).as_posix()
            )
            # Support files are context the skill can pull in, counted separately
            # rather than folded into the SKILL.md figure — a skill hiding 40k of
            # prose behind a reference file is not a small skill.
            extras = [
                p
                for p in sorted(skill_dir.rglob("*"))
                if p.is_file() and p.name != "SKILL.md" and not skipped(p, base)
            ]
            entry["support_files"] = len(extras)
            entry["support_chars"] = sum(chars_of(p) for p in extras)
            entry["support_est_tokens"] = est_tokens(entry["support_chars"])
            found.append(entry)

    agents_dir = base / "agents"
    if agents_dir.is_dir():
        for agent_md in sorted(agents_dir.rglob("*.md")):
            if skipped(agent_md, base):
                continue
            name = agent_md.relative_to(agents_dir).with_suffix("").as_posix()
            found.append(component(agent_md, base, "agent", name))

    return found


def summarise(components: list[dict]) -> dict:
    by_kind: dict[str, dict] = {}
    for entry in components:
        bucket = by_kind.setdefault(
            entry["kind"], {"files": 0, "chars": 0, "est_tokens": 0}
        )
        bucket["files"] += 1
        bucket["chars"] += entry["chars"] + entry.get("support_chars", 0)
        bucket["est_tokens"] = est_tokens(bucket["chars"])
    total_chars = sum(b["chars"] for b in by_kind.values())
    return {
        "by_kind": by_kind,
        "totals": {
            "files": len(components),
            "chars": total_chars,
            "est_tokens": est_tokens(total_chars),
        },
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Measure a Claude config root.")
    parser.add_argument("root", help="config root to measure")
    args = parser.parse_args(argv)

    base = Path(args.root)
    if not base.is_dir():
        print(f"measure.py: not a directory: {base}", file=sys.stderr)
        return 2

    base = base.resolve()
    report: dict = {"root": base.as_posix(), "chars_per_token": CHARS_PER_TOKEN}
    report["components"] = collect(base)
    report.update(summarise(report["components"]))
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
