#!/usr/bin/env python3
"""
Meta-skill loading-strategy benchmark.

Compares three strategies against two real public meta-skill bundles from
zivtech/drupal-meta-skills and zivtech/a11y-meta-skills:

  A. Preload all                — every SKILL.md body in system context at turn 1.
  B. Router + lazy              — frontmatter stubs at turn 1; one skill body
                                  loaded when the router picks a match.
  C. Router + lazy + subagent   — router still only sees stubs; matched skill
                                  body lives in a delegated subagent and never
                                  touches the parent context.

Each scenario reports:
  - turn-1 parent-context tokens
  - turn-10 parent-context tokens (one skill invoked at turn 2; rest unused)
  - % of the 300K rot-zone threshold (from just-one-more-turn/)
  - file-count contribution toward the 50-file subagent-isolation threshold
    (from subagent-isolation/)
  - cache-cold exposure: how many bytes of the "loaded" content are volatile
    enough that a 5-min cache TTL wipe would force re-cache at 1.25× base cost
    (from idle-tax/). Volatile = skill bodies; stubs are treated as stable.

The benchmark auto-clones the two repos to /tmp/meta-skills-bench/ if they
are not already cloned. Pass --cache-dir to override.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

from count_tokens import FileMeasure

DEFAULT_CACHE = Path("/tmp/meta-skills-bench")
REPOS = {
    "drupal-meta-skills": "https://github.com/zivtech/drupal-meta-skills.git",
    "a11y-meta-skills": "https://github.com/zivtech/a11y-meta-skills.git",
}

# Thresholds drawn from this repo's helpers.
ROT_ZONE_TOKENS = 300_000           # just-one-more-turn/
SUBAGENT_FILE_THRESHOLD = 50        # subagent-isolation/
CACHE_TTL_SECONDS = 300             # idle-tax/ (informational; we just flag volatility)


def ensure_cloned(cache_dir: Path) -> dict[str, Path]:
    cache_dir.mkdir(parents=True, exist_ok=True)
    paths: dict[str, Path] = {}
    for name, url in REPOS.items():
        target = cache_dir / name
        if target.exists():
            paths[name] = target
            continue
        print(f"[clone] {url} -> {target}", file=sys.stderr)
        result = subprocess.run(
            ["git", "clone", "--depth", "1", url, str(target)],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            print(result.stderr, file=sys.stderr)
            raise SystemExit(f"clone failed for {name}")
        paths[name] = target
    return paths


def discover_skills(repo_root: Path) -> list[Path]:
    """Find every SKILL.md inside .claude/skills/."""
    skills_dir = repo_root / ".claude" / "skills"
    if not skills_dir.is_dir():
        return []
    return sorted(skills_dir.rglob("SKILL.md"))


@dataclass
class Scenario:
    name: str
    turn_1_tokens: int
    turn_10_tokens: int
    parent_files: int
    subagent_files: int
    volatile_tokens: int           # tokens subject to idle-tax penalty on cold cache

    @property
    def rot_zone_pct(self) -> float:
        return 100.0 * self.turn_10_tokens / ROT_ZONE_TOKENS


@dataclass
class BundleReport:
    bundle: str
    skill_count: int
    total_body_tokens: int
    stub_tokens: int
    largest_body_tokens: int
    scenarios: dict[str, Scenario] = field(default_factory=dict)


def measure_bundle(bundle: str, skill_paths: list[Path]) -> BundleReport:
    measures = [FileMeasure.from_path(p) for p in skill_paths]
    if not measures:
        raise SystemExit(f"no SKILL.md files found in {bundle}")

    total_body = sum(m.body_tokens for m in measures)
    total_stub = sum(m.stub_tokens for m in measures)
    total_all = sum(m.total_tokens for m in measures)
    largest = max(m.body_tokens for m in measures)
    # "mid" skill: pick the median body by token count as the "one skill invoked" case
    sorted_bodies = sorted(m.body_tokens for m in measures)
    median_body = sorted_bodies[len(sorted_bodies) // 2]

    # Router prompt itself costs something. Estimate a compact router
    # prompt at ~500 tokens (name + description table + routing rules).
    ROUTER_OVERHEAD_TOKENS = 500

    # Scenario A: preload all SKILL.md (body + frontmatter) into parent.
    # On turn 10 everything is still there; cache is warm but every byte
    # is "volatile" relative to the rot zone and the idle-tax.
    preload = Scenario(
        name="A. Preload all",
        turn_1_tokens=total_all,
        turn_10_tokens=total_all,
        parent_files=len(measures),
        subagent_files=0,
        volatile_tokens=total_all,
    )

    # Scenario B: router + lazy. Turn 1 loads router + all stubs (frontmatter
    # only). Turn 2 loads the matched skill's full body into parent. Turn 10
    # parent still carries that body plus the stubs.
    lazy = Scenario(
        name="B. Router + lazy",
        turn_1_tokens=ROUTER_OVERHEAD_TOKENS + total_stub,
        turn_10_tokens=ROUTER_OVERHEAD_TOKENS + total_stub + median_body,
        parent_files=len(measures) + 1,  # router file + stubs (all stubs counted as one read per file)
        subagent_files=0,
        volatile_tokens=median_body,     # only the loaded body is volatile
    )

    # Scenario C: router + lazy + subagent. Matched skill runs in an Agent
    # tool call — its body never contaminates parent. Parent only holds
    # router + stubs + the subagent's summary (estimate 500 tokens).
    SUBAGENT_SUMMARY_TOKENS = 500
    isolated = Scenario(
        name="C. Router + lazy + subagent",
        turn_1_tokens=ROUTER_OVERHEAD_TOKENS + total_stub,
        turn_10_tokens=ROUTER_OVERHEAD_TOKENS + total_stub + SUBAGENT_SUMMARY_TOKENS,
        parent_files=2,                   # router + one stub file chosen
        subagent_files=1,
        volatile_tokens=SUBAGENT_SUMMARY_TOKENS,
    )

    return BundleReport(
        bundle=bundle,
        skill_count=len(measures),
        total_body_tokens=total_body,
        stub_tokens=total_stub,
        largest_body_tokens=largest,
        scenarios={"A": preload, "B": lazy, "C": isolated},
    )


def format_report(report: BundleReport) -> str:
    out: list[str] = []
    out.append(f"## {report.bundle}")
    out.append("")
    out.append(f"- Skills: **{report.skill_count}**")
    out.append(f"- Bundle body tokens (sum of all SKILL.md bodies): **{report.total_body_tokens:,}**")
    out.append(f"- Bundle stub tokens (sum of frontmatter only): **{report.stub_tokens:,}**")
    out.append(f"- Largest single skill body: **{report.largest_body_tokens:,}**")
    out.append("")
    out.append("| Scenario | Turn-1 parent | Turn-10 parent | % of 300K rot | Parent files | Volatile tokens |")
    out.append("|---|---:|---:|---:|---:|---:|")
    for key in ("A", "B", "C"):
        s = report.scenarios[key]
        out.append(
            f"| {s.name} | {s.turn_1_tokens:,} | {s.turn_10_tokens:,} "
            f"| {s.rot_zone_pct:.2f}% | {s.parent_files} | {s.volatile_tokens:,} |"
        )
    out.append("")
    # Savings.
    a = report.scenarios["A"].turn_10_tokens
    b = report.scenarios["B"].turn_10_tokens
    c = report.scenarios["C"].turn_10_tokens
    if a > 0:
        out.append(f"- Lazy saves **{100 * (a - b) / a:.0f}%** of parent context at turn 10 vs preload.")
        out.append(f"- Lazy+subagent saves **{100 * (a - c) / a:.0f}%** of parent context at turn 10 vs preload.")
    out.append("")
    return "\n".join(out)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE,
                        help="where to clone the reference repos (default: /tmp/meta-skills-bench)")
    parser.add_argument("--markdown", action="store_true",
                        help="emit markdown suitable for pasting into results.md")
    args = parser.parse_args(argv[1:])

    paths = ensure_cloned(args.cache_dir)
    reports: list[BundleReport] = []
    for bundle, root in paths.items():
        skills = discover_skills(root)
        reports.append(measure_bundle(bundle, skills))

    if args.markdown:
        print("# Meta-skill loading-strategy benchmark")
        print("")
        print("Generated by `meta-router-analysis/benchmark/scenarios.py`.")
        print(f"Thresholds: rot-zone={ROT_ZONE_TOKENS:,} tokens (just-one-more-turn), "
              f"subagent-isolation={SUBAGENT_FILE_THRESHOLD} files, "
              f"cache TTL={CACHE_TTL_SECONDS}s (idle-tax).")
        print("")
    for r in reports:
        print(format_report(r))

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
