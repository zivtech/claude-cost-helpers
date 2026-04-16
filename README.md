# Claude Cost Helpers

Local hooks and slash commands that make Claude Code's cost mechanics visible. No platform dependency — these run in your `~/.claude/` config on any machine with `bash` and `python3`.

Companion code for the *Economics of Claude Code* blog series.

## The helpers

| Helper | Blog post | Hook type | Slash commands | Status |
|---|---|---|---|---|
| [Idle Tax](idle-tax/) | Part 1: The Idle Tax | `UserPromptSubmit` — warns when cache has expired or is about to | `/save-session`, `/resume-session` | **Built + tested** |
| [Just One More Turn](just-one-more-turn/) | Part 2: The "just one more turn" trap | `UserPromptSubmit` — warns when context usage approaches the rot zone | `/split` | **Built + tested** |
| [Subagent Isolation](subagent-isolation/) | Part 3: The agent that read 200 files | `PostToolUse` on Read/Glob/Grep — warns when file count exceeds threshold | `/delegate` | **Built + tested** |
| [Compact Gamble](compact-gamble/) | Part 4: The compact gamble | `PreCompact` — saves a marker and urges context preservation before compaction | `/safe-compact` | **Built + tested** |
| [Watching Cost](watching-cost/) | Part 5: The watching cost | `PostToolUse` (all) — warns when tool output exceeds token threshold | `/to-file` | **Built + tested** |
| [Effort Control](effort-control/) | Part 1 addendum: 4.7's `xhigh` default | `SessionStart` — confirms `CLAUDE_CODE_EFFORT_LEVEL` pin is active | `/deep` | **Built + tested** |
| [Auto-Persist](auto-persist/) | Part 1 addendum: Stop-hook session state | `Stop` — writes minimal environmental state after every turn | `/last-state` | **Built + tested** |

## Install

### Option A: Skills registry (skills.sh)

Install the slash commands as agent skills — works with Claude Code, Codex, Cursor, and 40+ other agents:

```bash
npx skills add zivtech/claude-cost-helpers
```

This installs the 6 skills (save-session, resume-session, split, delegate, safe-compact, to-file). To also get the **automatic warning hooks**, run the hook installers below.

### Option B: Hook installers (manual)

Each helper is self-contained. Install one or all:

```bash
# Install all helpers at once
./install-all.sh

# Or install individually
cd idle-tax && ./install.sh
cd just-one-more-turn && ./install.sh
cd subagent-isolation && ./install.sh
cd compact-gamble && ./install.sh
cd watching-cost && ./install.sh
cd effort-control && ./install.sh
cd auto-persist && ./install.sh
```

Each installer copies a hook script + slash commands into `~/.claude/`, backs up anything it would overwrite, and prints the `settings.json` snippet to merge. No auto-modification of settings — you merge manually.

### Combined settings snippet (all helpers)

If you install all helpers, here's the combined `hooks` block for `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/idle-tax/cache-idle-timer.sh",
            "timeout": 5,
            "statusMessage": "Checking cache freshness..."
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/just-one-more-turn/context-usage-monitor.sh",
            "timeout": 5,
            "statusMessage": "Checking context usage..."
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "^(Read|Glob|Grep)$",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/subagent-isolation/file-count-monitor.sh",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/watching-cost/output-size-monitor.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/compact-gamble/pre-compact-backup.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/effort-control/effort-pin-banner.sh",
            "timeout": 5,
            "statusMessage": "Checking effort pin..."
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/auto-persist/stop-auto-persist.sh",
            "timeout": 5
          }
        ]
      }
    ]
  },
  "env": {
    "CLAUDE_CODE_EFFORT_LEVEL": "high"
  },
  "effortLevel": "high"
}
```

Note: the `PostToolUse` array has two entries with different matchers — the file-count monitor only fires on Read/Glob/Grep, while the output-size monitor fires on all tools. The `env.CLAUDE_CODE_EFFORT_LEVEL` pin is what defeats Opus 4.7's first-run `xhigh` override — the env var is load-bearing, the root `effortLevel` field is belt-and-suspenders.

## How they work together

The helpers are independent — install any subset. But they're designed to layer:

- **Idle Tax** gives you the foundation: cache-awareness + the save/resume cycle
- **Just One More Turn** builds on idle-tax: when context gets fat, it recommends splitting — which uses the same `/save-session`
- **Subagent Isolation** is orthogonal: prevents context bloat from file-heavy work
- **Compact Gamble** protects you when compaction fires: the backup hook means you can recover if a compact drops something
- **Watching Cost** catches the other source of context bloat: tool output you didn't need in context
- **Effort Control** pins `CLAUDE_CODE_EFFORT_LEVEL=high` so Opus 4.7 doesn't silently spend `xhigh` per turn
- **Auto-Persist** writes environmental state after every turn via Stop hook — zero Claude tokens, always current. The automatic counterpart to idle-tax's manual `/save-session`

The common thread: every helper makes an invisible cost visible at the moment it happens, so you have a real choice.

## For organizations

Individual developers can install these manually. For organizations with 20+ Claude Code users, [Joyus AI](https://github.com/joyus-ai) provides:

- **Deployment** — push canonical hook configs to all org users
- **Policy** — enforce which helpers are required ("idle-tax hook required for all users")
- **Threshold tuning** — org-wide defaults, overridable per team
- **Telemetry aggregation** — roll up warning events into cost dashboards (fleet-wide patterns, not just individual sessions)

The helpers are the sensors. Joyus is the fleet manager.

## License

GPL-3.0-or-later. See each helper's LICENSE file.

---

## Helper details

Below is what each helper contains. The architecture follows the same pattern as idle-tax — a hook script, one or two slash commands, a settings snippet, and install/uninstall scripts.

---

### Just One More Turn

**Problem:** Context rot. Sessions that should have been split keep going. After ~300–400K tokens, model quality degrades and cost per turn keeps climbing (the entire growing context is re-processed on every message).

**Hook: `context-usage-monitor.sh`**
- Event: `UserPromptSubmit`
- Behavior: Estimates current context size by tracking turn count per session (via local state file). Each turn is estimated at ~3,000 tokens (configurable). When estimated context approaches a configurable threshold (default 300K tokens):
  - At 70% of threshold: soft heads-up — "Context is getting heavy. You're approaching the rot zone."
  - At 90% of threshold: warns — "Context is getting heavy (~270K est). Consider `/split` to start fresh with a handoff."
  - At 100%+: stronger warning — "Context is past the rot zone. Quality and cost are both degrading. `/split` recommended."
- Limitation: token count is estimated from turn count × per-turn average, not measured. Sessions with heavy tool output (file reads, build logs) will have higher actual usage. The estimate is a floor, not a ceiling — "good enough to warn," not "good enough to bill." Joyus platform (Spec 011 Phase 2) provides exact token counts.

**Slash command: `/split`**
- Runs `/save-session` with an auto-generated description ("context-split at ~Nk estimated tokens")
- Prints: "Session saved. Open a fresh session and run `/resume-session` to continue."
- Effectively a convenience wrapper — doesn't do anything `/save-session` can't do, but names the *reason* for the split in the handoff file

**Settings snippet:**
```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/just-one-more-turn/context-usage-monitor.sh",
            "timeout": 5,
            "statusMessage": "Checking context usage..."
          }
        ]
      }
    ]
  }
}
```

**Joyus tie-in:** Spec 012 (Session Splitting and Resume Pointers). The platform provides exact token counts, auto-split triggers, and fleet-wide "sessions that split proactively cost X% less" visibility.

---

### Subagent Isolation

**Problem:** A parent agent that reads 200 files itself bloats its context forever. A subagent can do the same work in isolation and return only the synthesis. Most users don't think about this because the cost is invisible.

**Hook: `file-count-monitor.sh`**
- Event: `PostToolUse` on `Read`, `Glob`, `Grep`
- Behavior: Counts unique file paths accessed in the current session (via local state file keyed by session ID). When count exceeds threshold (default 50 files):
  - First warning: "This session has read N files. The context is getting heavy with file content. Consider using the `Agent` tool to delegate file-heavy work — subagents get their own context window and only return a summary."
  - Subsequent warnings: every 25 additional files, re-warn with updated count
- Does NOT block — purely informational
- The file-path tracking is lightweight: appends to a local set file, deduplicates on read

**Slash command: `/delegate`**
- Prompts: "Describe the task to delegate (the subagent will have its own clean context):"
- Wraps the input into an `Agent` tool call with a clean prompt and `run_in_background: true`
- Prints: "Subagent dispatched. It will return a synthesis when done."
- This is a convenience — users can call the Agent tool directly. The slash command makes the pattern discoverable.

**Settings snippet:**
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "^(Read|Glob|Grep)$",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/subagent-isolation/file-count-monitor.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

**Joyus tie-in:** Spec 013, sub-feature A (Subagent Isolation & Spawning). The platform provides `joyus_spawn_subagent` with context-budget enforcement, per-subagent cost attribution, and fleet-wide "files read per session" aggregation.

---

### Compact Gamble

**Problem:** Compaction summarizes a session and continues on the summary. It's lossy — Claude decides what mattered. When it drops something you needed, there's no recovery. The compaction fires at the worst possible moment (peak context, peak rot), making bad compacts more likely when the stakes are highest.

**Hook: `pre-compact-backup.sh`**
- Event: `PreCompact`
- Behavior: Before any compaction (auto or manual), does two things:
  1. Writes a metadata marker file to `~/.claude/sessions/<sessionId>-pre-compact-<timestamp>.md` recording the session ID, timestamp, and trigger type (auto/manual). This marker lets you know exactly when a compact happened if you later notice missing context.
  2. Injects `additionalContext` asking Claude to briefly summarize what was being worked on, key decisions, current file state, and the next step — so that summary survives into the compacted context.
- This is a safety net, not an undo. The marker file is metadata only (a bash hook cannot access conversation content). The real value is the `additionalContext` prompt that gets Claude to preserve key context before compaction runs.
- If the compact drops something critical, the marker tells you when it happened. Use `/save-session` proactively before compaction for a richer handoff.

**Slash command: `/safe-compact`**
- Instead of compacting, runs `/save-session` and tells the user to start fresh
- Rationale: starting fresh with a handoff is often the better economic choice than compacting. Compaction keeps the session alive (and re-caches the summary), while a fresh session starts with a clean, warm cache.
- Output: "Session saved to ~/.claude/sessions/... — starting fresh is usually cheaper than compacting. Run `/resume-session` in a new session to continue."

**Settings snippet:**
```json
{
  "hooks": {
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/compact-gamble/pre-compact-backup.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

**Joyus tie-in:** Spec 013, sub-feature B (Compaction Strategy & Validation). The platform provides `joyus_compact_session` with strategy selection (aggressive/conservative/query-aware), compaction-delta artifacts, `undo_compact` within a retention window, and bad-compact detection heuristics.

---

### Watching Cost

**Problem:** Tools that dump large output into context — build logs, test results, file listings, API responses — silently inflate input cost on every subsequent turn. The output sits in context even if you never reference it again. Pasting a 10K-token build log into chat means every future message in that session reprocesses those 10K tokens.

**Hook: `output-size-monitor.sh`**
- Event: `PostToolUse` (all tools)
- Behavior: Inspects the length of tool output. When output exceeds threshold (default 5,000 tokens, estimated at ~4 chars/token):
  - Warns: "That tool returned ~N tokens of output now sitting in context. Every future message in this session will reprocess it. Consider: (1) redirecting long output to a file with `/to-file`, (2) starting a subagent for output-heavy work, or (3) being specific about what you need (e.g., 'show me lines 40–60' instead of 'show me the file')."
  - Does NOT suppress the output (the tool already ran) — this is a forward-looking warning
- Tracks cumulative "watching cost" per session: total tokens of tool output sitting in context. Warns again when cumulative watching cost crosses higher thresholds (25K, 50K, 100K).

**Slash command: `/to-file`**
- Usage: `/to-file <command>`
- Behavior: Runs the command with stdout redirected to a temp file. Returns: file path, line count, first 10 lines, last 10 lines.
- Keeps the full output available (just `Read` the file for specific sections) without dumping it all into context.
- Example: `/to-file npm test` → "Output saved to /tmp/claude-test-output-abc123.txt (847 lines). First 10 lines: ... Last 10 lines: ..."

**Settings snippet:**
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/watching-cost/output-size-monitor.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

**Joyus tie-in:** Spec 013, sub-feature C (Tool Output Modes). The platform provides `outputMode` annotations on MCP tool definitions (`stream`/`polling`/`signaled`), watching-cost as a distinct line item in cost dashboards, and operator alerting when watching cost exceeds threshold.

---

### Effort Control

**Problem:** On April 16, 2026, Opus 4.7 shipped with `xhigh` as its new default effort level. The first-run rule silently overrides any previous `effortLevel: "high"` setting. Every turn on 4.7 now spends more thinking tokens than it would on 4.6 with the same config, and there's no notification when the override fires.

**Hook: `effort-pin-banner.sh`**
- Event: `SessionStart`
- Behavior: Reads `CLAUDE_CODE_EFFORT_LEVEL` from the hook process environment. Confirms the pin is active (`low|medium|high`), flags no-ops (`xhigh|max` matching the default), warns if missing, or flags unknown values. Banner surfaces via `additionalContext` so Claude can reference it if you ask.
- Why the env var: `CLAUDE_CODE_EFFORT_LEVEL` is the only mechanism that survives 4.7's "first run on new model family" override. The `effortLevel` settings field and per-session `/effort` both get overridden; the env var does not.

**Slash command: `/deep`**
- Usage: `/deep <task>`
- Wraps the next turn in `ultrathink` for one-shot deeper reasoning without changing session effort. Lets you pin `high` by default and escalate only for the one message that needs it.

**Settings snippet:**
```json
{
  "env": { "CLAUDE_CODE_EFFORT_LEVEL": "high" },
  "effortLevel": "high",
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/effort-control/effort-pin-banner.sh",
            "timeout": 5,
            "statusMessage": "Checking effort pin..."
          }
        ]
      }
    ]
  }
}
```

**Joyus tie-in:** effort-level is per-user config today. Fleet-level, Joyus can enforce `high` as the org default, track escalations to `xhigh`/`max` as a cost line item, and surface "which engineers or tasks consistently need more reasoning budget" analytics.

---

### Auto-Persist

**Problem:** `/save-session` works, but it costs tokens and requires you to remember. The most common failure mode of idle-tax is "I forgot to save before walking away" — which means the cache expires, you come back, and the handoff you would have wanted never happened.

**Hook: `stop-auto-persist.sh`**
- Event: `Stop` (fires once per main-session turn; not SubagentStop, which is noisier)
- Behavior: Writes machine-readable JSON + human-readable Markdown snapshots of the current environment to `~/.claude/sessions/auto-state/<sessionId>.{json,md}`. Captures: cwd, git branch, last commit, staged/modified/untracked counts, upstream ahead/behind, files modified in the last 30 min. Zero Claude tokens — pure shell + git.
- Injection-safe: values are passed to python via env vars, never interpolated into source, so tricky commit messages and filenames survive round-trip.

**Slash command: `/last-state`**
- Reads the most recent auto-state Markdown and prints it. One file Read, no synthesis. Much cheaper than `/save-session` for "where did I leave off?" questions.

**Settings snippet:**
```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/auto-persist/stop-auto-persist.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

**Joyus tie-in:** the auto-state file shape is the local-single-user version of the Joyus session-telemetry spec. Aggregating across a team gives you "where is each developer's work sitting right now?" without any platform instrumentation beyond a cron that scrapes `~/.claude/sessions/auto-state/*.json`.
