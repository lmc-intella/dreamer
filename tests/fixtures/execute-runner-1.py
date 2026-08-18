#!/usr/bin/env python3
# Toy test runner for the scratch repo tests/execute.bats builds. Stands in for
# the story implementation's real test command so the execute spine can be
# driven mechanically: it runs every tests/test_*.py under unittest and prints a
# line-coverage figure that gate.sh's `--coverage` floor can bite on.
#
# Coverage definition, deliberately simple and dependency-free: executed lines
# over executable lines across src/*.py, where an executable line is any
# non-blank line that is not a comment. The fixture sources therefore carry no
# docstrings and no multi-line statements, either of which would be counted as
# executable while emitting no line event.
#
# Exit 0 when every test passes, 1 otherwise. The coverage figure is the last
# thing printed, which is the token gate.sh reads.
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
EXECUTED = set()


def tracer(frame, event, arg):
    path = frame.f_code.co_filename
    if not path.startswith(SRC + os.sep):
        return None
    if event == "line":
        EXECUTED.add((path, frame.f_lineno))
    return tracer


def executable_lines(path):
    found = set()
    with open(path) as handle:
        for number, raw in enumerate(handle, 1):
            stripped = raw.strip()
            if stripped and not stripped.startswith("#"):
                found.add(number)
    return found


def main():
    sys.path.insert(0, ROOT)
    sys.settrace(tracer)
    try:
        suite = unittest.defaultTestLoader.discover(
            os.path.join(ROOT, "tests"), top_level_dir=ROOT)
        result = unittest.TextTestRunner(stream=sys.stdout, verbosity=2).run(suite)
    finally:
        sys.settrace(None)

    total = 0
    covered = 0
    for name in sorted(os.listdir(SRC)) if os.path.isdir(SRC) else []:
        if not name.endswith(".py"):
            continue
        path = os.path.join(SRC, name)
        lines = executable_lines(path)
        total += len(lines)
        covered += len(lines & set(n for f, n in EXECUTED if f == path))
    percent = 100.0 if total == 0 else 100.0 * covered / total
    print("COVERAGE %d/%d %.1f%%" % (covered, total, percent))
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main())
