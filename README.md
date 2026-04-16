# Claude Cost Helpers

Local hooks and slash commands that make Claude Code's cost mechanics visible. No platform dependency — these run in your `~/.claude/` config on any machine with `bash` and `python3`.

Companion code for the *Economics of Claude Code* blog series.

## The helpers

| # | Helper | Blog post | Hook type | Slash commands | Status |
|---|---|---|---|---|---|
| 01 | [Idle Tax](01-idle-tax/) | Part 1: The Idle Tax | `UserPromptSubmit` — warns when cache has expired or is about to | `/save-session`, `/resume-session` | **Built + tested** |
| 02 | [Just One More Turn](02-just-one-more-turn/) | Part 2: The "just one more turn" trap | `UserPromptSubmit` — warns when context usage approaches the rot zone | `/split` | Stubbed |
| 03 | [Subagent Isolation](03-subagent-isolation/) | Part 3: The agent that read 200 files | `PostToolUse` on Read/Glob/Grep — warns when file count exceeds threshold | `/delegate` | Stubbed |
| 04 | [Compact Gamble](04-compact-gamble/) | Part 4: The compact gamble | `PreCompact` — backs up context before compaction | `/safe-compact` | Stubbed |
| 05 | [Watching Cost](05-watching-cost/) | Part 5: The watching cost | `PostToolUse` (all) — warns when tool output exceeds token threshold | `/to-file` | Stubbed |

## Install

Each helper is self-contained. Install one or all:

```bash
cd 01-idle-tax && ./install.sh
cd 02-just-one-more-turn && ./install.sh
# etc.
```

Each installer copies a hook script + slash commands into `~/.claude/`, backs up anything it would overwrite, and prints the `settings.json` snippet to merge. No auto-modification of settings — you merge manually.

## How they work together

The helpers are independent — install any subset. But they're designed to layer:

- **01 (Idle Tax)** gives you the foundation: cache-awareness + the save/resume cycle
- **02 (Just One More Turn)** builds on 01: when context gets fat, it recommends splitting — which uses the same `/save-session` from 01
- **03 (Subagent Isolation)** is orthogonal: prevents context bloat from file-heavy work
- **04 (Compact Gamble)** protects you when compaction fires: the backup hook means you can recover if a compact drops something
- **05 (Watching Cost)** catches the other source of context bloat: tool output you didn't need in context

The common thread: every helper makes an invisible cost visible at the moment it happens, so you have a real choice.

## For organizations

Individual developers can install these manually. For organizations with 20+ Claude Code users, [Joyus AI](https://github.com/joyus-ai) provides:

- **Deployment** — push canonical hook configs to all org users
- **Policy** — enforce which helpers are required ("idle-tax hook required for all users")
- **Threshold tuning** — org-wide defaults, overridable per team
- **Telemetry aggregation** — roll up warning events into cost dashboards (fleet-wide patterns, not just individual sessions)

The helpers are the sensors. Joyus is the fleet manager.

## License

MIT. See each helper's LICENSE file.

---

## Helper stubs (02–05)

Helpers 02–05 are not yet built. Below is what each will contain when implemented. The architecture follows the same pattern as 01 — a hook script, one or two slash commands, a settings snippet, and install/uninstall scripts.

---

### 02 — Just One More Turn

**Problem:** Context rot. Sessions that should have been split keep going. After ~300–400K tokens, model quality degrades and cost per turn keeps climbing (the entire growing context is re-processed on every message).

**Hook: `context-usage-monitor.sh`**
- Event: `UserPromptSubmit`
- Behavior: Estimates current context size by tracking turn count and average tool-output size per session (via local state file). When estimated context approaches a configurable threshold (default 300K tokens):
  - At 70% of threshold: status line indicator changes (if status line is configured)
  - At 90% of threshold: warns — "Context is getting heavy (~270K est). Consider `/split` to start fresh with a handoff."
  - At 100%+: stronger warning — "Context is past the rot zone. Quality and cost are both degrading. `/split` recommended."
- Limitation: token count is estimated from turn count × average, not measured. Accuracy is "good enough to warn," not "good enough to bill." Joyus platform (Spec 011 Phase 2) provides exact token counts.

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

### 03 — Subagent Isolation

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

### 04 — Compact Gamble

**Problem:** Compaction summarizes a session and continues on the summary. It's lossy — Claude decides what mattered. When it drops something you needed, there's no recovery. The compaction fires at the worst possible moment (peak context, peak rot), making bad compacts more likely when the stakes are highest.

**Hook: `pre-compact-backup.sh`**
- Event: `PreCompact`
- Behavior: Before any compaction (auto or manual), writes a snapshot of the current session state to `~/.claude/sessions/<sessionId>-pre-compact-<timestamp>.md`. The snapshot uses the same format as `/save-session` — a structured handoff that captures what was happening before the compact.
- This is a safety net, not an undo. If the compact drops something critical, you can start a fresh session with `/resume-session <path-to-pre-compact-snapshot>` and you'll have everything that was in context before the compact happened.
- Limitation: the snapshot is an LLM-written summary (via the `/save-session` prompt), not a verbatim transcript. It's subject to the same quality constraints as any summary at high context usage.

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

### 05 — Watching Cost

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
