#!/usr/bin/env python3
"""
Meta-skill loading-strategy benchmark.

Compares three strategies against two real public meta-skill bundles from
zivtech/drupal-meta-skills and zivtech/a11y-meta-skills.

Each bundle has two layers:
  - SKILL.md files (.claude/skills/<name>/SKILL.md) — the entry point the
    agent client reads first.
  - Agent files (.claude/agents/<name>.md) — the full protocol the SKILL.md
    can hand off to via `Agent(subagent_type="<name>")`.

The three strategies:

  F. Flattened (straw-man)      — every SKILL.md body AND every matching agent
                                  body preloaded into the parent context at
                                  turn 1. "What if the router pattern were
                                  inlined instead of delegated?"
  A. As-implemented             — what the bundle does today. SKILL.md bodies
                                  enter the parent context when installed;
                                  agent bodies stay on disk until a matching
                                  `Agent(subagent_type=...)` call spawns
                                  them. drupal-meta-skills keeps its SKILL.md
                                  files small and routes to agents;
                                  a11y-meta-skills puts the full protocol in
                                  SKILL.md itself.
  C. Optimized                  — router-v2 applied. SKILL.md files shrink to
                                  frontmatter-only stubs; the full protocol
                                  lives in agents; matched skill runs in a
                                  subagent and returns a summary.

Each scenario reports:
  - turn-1 parent-context tokens
  - turn-10 parent-context tokens (one skill invoked at turn 2; rest unused)
  - % of the 300K rot-zone threshold (from just-one-more-turn/)
  - file-count contribution toward the 50-file subagent-isolation threshold
    (from subagent-isolation/)
  - cache-cold exposure: how many bytes of the "loaded" content are volatile
    enough that a 5-min cache TTL wipe would force re-cache at 1.25× base cost
    (from idle-tax/). Volatile = skill/agent bodies; stubs are treated as
    stable.

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


def discover_agents(repo_root: Path) -> list[Path]:
    """Find every .md inside .claude/agents/."""
    agents_dir = repo_root / ".claude" / "agents"
    if not agents_dir.is_dir():
        return []
    return sorted(p for p in agents_dir.glob("*.md") if p.is_file())


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
    agent_count: int
    total_skill_body_tokens: int
    total_agent_body_tokens: int
    stub_tokens: int
    largest_skill_body_tokens: int
    largest_agent_body_tokens: int
    scenarios: dict[str, Scenario] = field(default_factory=dict)


def measure_bundle(bundle: str, skill_paths: list[Path], agent_paths: list[Path]) -> BundleReport:
    skill_measures = [FileMeasure.from_path(p) for p in skill_paths]
    agent_measures = [FileMeasure.from_path(p) for p in agent_paths]
    if not skill_measures:
        raise SystemExit(f"no SKILL.md files found in {bundle}")

    total_skill_body = sum(m.body_tokens for m in skill_measures)
    total_skill_all = sum(m.total_tokens for m in skill_measures)
    total_stub = sum(m.stub_tokens for m in skill_measures)
    total_agent_body = sum(m.total_tokens for m in agent_measures)  # agents have no stub/body split — count as one
    largest_skill = max(m.body_tokens for m in skill_measures)
    largest_agent = max((m.total_tokens for m in agent_measures), default=0)

    # Pick the median skill body as the "one skill actually invoked at turn 2"
    # and the matching agent, if any, as the agent that would be spawned.
    sorted_skill_bodies = sorted(m.body_tokens for m in skill_measures)
    median_skill_body = sorted_skill_bodies[len(sorted_skill_bodies) // 2]
    sorted_agent_bodies = sorted(m.total_tokens for m in agent_measures)
    median_agent_body = (
        sorted_agent_bodies[len(sorted_agent_bodies) // 2]
        if sorted_agent_bodies else 0
    )

    ROUTER_OVERHEAD_TOKENS = 500
    SUBAGENT_SUMMARY_TOKENS = 500

    # Scenario F (straw-man): flattened. Every SKILL.md body + every agent
    # body preloaded into the parent session at turn 1. What it would cost
    # if the router pattern were inlined instead of delegated.
    flattened = Scenario(
        name="F. Flattened (straw-man: all SKILL.md bodies + all agents preloaded)",
        turn_1_tokens=total_skill_all + total_agent_body,
        turn_10_tokens=total_skill_all + total_agent_body,
        parent_files=len(skill_measures) + len(agent_measures),
        subagent_files=0,
        volatile_tokens=total_skill_all + total_agent_body,
    )

    # Scenario A (current, as-implemented): SKILL.md files enter the parent
    # context when the bundle is installed — that is how agent clients work
    # today. Agent bodies stay on disk and are only loaded when an
    # Agent(subagent_type=...) call spawns them; they live in subagent
    # context. Parent at turn 10 holds all SKILL.md bodies + one subagent
    # summary.
    as_implemented = Scenario(
        name="A. As-implemented (SKILL.md in parent, agents lazy via subagent)",
        turn_1_tokens=total_skill_all,
        turn_10_tokens=total_skill_all + SUBAGENT_SUMMARY_TOKENS,
        parent_files=len(skill_measures),
        subagent_files=1 if agent_measures else 0,
        volatile_tokens=total_skill_all,
    )

    # Scenario C (optimized, router-v2): SKILL.md files shrink to
    # frontmatter-only stubs. A lightweight router prompt sits above them.
    # Matched skill spawns a subagent; subagent body runs there and returns
    # a summary. Parent never sees a skill body or an agent body at full
    # size.
    optimized = Scenario(
        name="C. Optimized (stubs-only + router + subagent)",
        turn_1_tokens=ROUTER_OVERHEAD_TOKENS + total_stub,
        turn_10_tokens=ROUTER_OVERHEAD_TOKENS + total_stub + SUBAGENT_SUMMARY_TOKENS,
        parent_files=2,
        subagent_files=1,
        volatile_tokens=SUBAGENT_SUMMARY_TOKENS,
    )

    return BundleReport(
        bundle=bundle,
        skill_count=len(skill_measures),
        agent_count=len(agent_measures),
        total_skill_body_tokens=total_skill_body,
        total_agent_body_tokens=total_agent_body,
        stub_tokens=total_stub,
        largest_skill_body_tokens=largest_skill,
        largest_agent_body_tokens=largest_agent,
        scenarios={"F": flattened, "A": as_implemented, "C": optimized},
    )


def format_report(report: BundleReport) -> str:
    out: list[str] = []
    out.append(f"## {report.bundle}")
    out.append("")
    out.append(f"- Skills: **{report.skill_count}** · Agents: **{report.agent_count}**")
    out.append(f"- Sum of SKILL.md bodies: **{report.total_skill_body_tokens:,}** tokens")
    out.append(f"- Sum of agent bodies: **{report.total_agent_body_tokens:,}** tokens")
    out.append(f"- Sum of frontmatter stubs: **{report.stub_tokens:,}** tokens")
    out.append(f"- Largest skill body: **{report.largest_skill_body_tokens:,}** · Largest agent body: **{report.largest_agent_body_tokens:,}**")
    out.append("")
    out.append("| Scenario | Turn-1 parent | Turn-10 parent | % of 300K rot | Parent files | Volatile tokens |")
    out.append("|---|---:|---:|---:|---:|---:|")
    for key in ("F", "A", "C"):
        s = report.scenarios[key]
        out.append(
            f"| {s.name} | {s.turn_1_tokens:,} | {s.turn_10_tokens:,} "
            f"| {s.rot_zone_pct:.2f}% | {s.parent_files} | {s.volatile_tokens:,} |"
        )
    out.append("")
    f = report.scenarios["F"].turn_10_tokens
    a = report.scenarios["A"].turn_10_tokens
    c = report.scenarios["C"].turn_10_tokens
    if f > 0:
        out.append(f"- **As-implemented vs straw-man (A vs F)**: saves {100 * (f - a) / f:.0f}% of parent context at turn 10.")
        out.append(f"- **Optimized vs straw-man (C vs F)**: saves {100 * (f - c) / f:.0f}%.")
    if a > 0:
        out.append(f"- **Optimized vs as-implemented (C vs A)**: saves an additional {100 * (a - c) / a:.0f}% on top of what the bundle already does today.")
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
        agents = discover_agents(root)
        reports.append(measure_bundle(bundle, skills, agents))

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
