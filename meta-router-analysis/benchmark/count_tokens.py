#!/usr/bin/env python3
"""
Token-count estimator for meta-skill bundles.

Uses the same char/4 approximation as watching-cost/output-size-monitor.sh
and just-one-more-turn/context-usage-monitor.sh. Treat results as a rough
floor, not a precise ceiling — actual tiktoken counts will vary by up to
~15% depending on content. The point here is relative differences between
loading strategies, which the estimator captures well.
"""

from __future__ import annotations

import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path


FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)


def estimate_tokens(text: str) -> int:
    """char/4 estimator. Matches the repo convention."""
    return math.ceil(len(text) / 4)


def split_frontmatter(text: str) -> tuple[str, str]:
    """Return (frontmatter, body). Frontmatter includes leading/trailing ---."""
    m = FRONTMATTER_RE.match(text)
    if not m:
        return "", text
    return m.group(0), text[m.end():]


@dataclass
class FileMeasure:
    path: Path
    total_chars: int
    total_tokens: int
    stub_chars: int  # frontmatter only (name + description)
    stub_tokens: int
    body_chars: int
    body_tokens: int

    @classmethod
    def from_path(cls, path: Path) -> "FileMeasure":
        text = path.read_text(encoding="utf-8")
        fm, body = split_frontmatter(text)
        return cls(
            path=path,
            total_chars=len(text),
            total_tokens=estimate_tokens(text),
            stub_chars=len(fm),
            stub_tokens=estimate_tokens(fm),
            body_chars=len(body),
            body_tokens=estimate_tokens(body),
        )


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: count_tokens.py <file-or-glob> [<file-or-glob> ...]", file=sys.stderr)
        return 2

    measures: list[FileMeasure] = []
    for arg in argv[1:]:
        p = Path(arg)
        if p.is_file():
            measures.append(FileMeasure.from_path(p))
        else:
            # glob
            for match in sorted(Path().glob(arg)):
                if match.is_file():
                    measures.append(FileMeasure.from_path(match))

    if not measures:
        print("no files matched", file=sys.stderr)
        return 1

    print(f"{'file':<70} {'chars':>8} {'tokens':>8} {'stub tok':>10} {'body tok':>10}")
    print("-" * 110)
    total_chars = total_tokens = total_stub = total_body = 0
    for m in measures:
        print(f"{str(m.path):<70} {m.total_chars:>8} {m.total_tokens:>8} {m.stub_tokens:>10} {m.body_tokens:>10}")
        total_chars += m.total_chars
        total_tokens += m.total_tokens
        total_stub += m.stub_tokens
        total_body += m.body_tokens
    print("-" * 110)
    print(f"{'TOTAL':<70} {total_chars:>8} {total_tokens:>8} {total_stub:>10} {total_body:>10}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
