---
name: save-session
description: Save current session state for handoff to a future session. Creates a structured file capturing what worked, what failed, and the exact next step. Use when stepping away, before cache expires, or when context is getting heavy. Part of claude-cost-helpers (01-idle-tax).
---

# Save Session

Capture everything from this session so the next one can pick up exactly where this one left off. The "What Did NOT Work" section is the most critical — without it, the next session will blindly retry failed approaches.

## Process

### Step 1: Gather context

Before writing, collect:
- All files modified this session (check `git diff` or recall from conversation)
- What was discussed, attempted, and decided
- Errors encountered and how they were resolved (or not)
- Current test/build status if relevant

### Step 2: Create the session file

```bash
mkdir -p ~/.claude/sessions
```

Create `~/.claude/sessions/YYYY-MM-DD-<short-description>-session.md` using today's date and a lowercase-hyphenated description (e.g., `2026-03-16-drupal-migration-session.md`).

### Step 3: Write every section honestly

Do not skip sections — write "None" or "N/A" if a section has no content. An incomplete file is worse than an honest empty section.

### Step 4: Show the file to the user

Display the full contents and ask: "Does this look accurate? Anything to correct or add?"

## Session File Format

```markdown
# Session: YYYY-MM-DD

**Project:** [project name or path]
**Topic:** [one-line summary]
**Branch:** [git branch if applicable]

---

## What We Are Building

[1-3 paragraphs with enough context that someone with zero memory can understand the goal.]

---

## What WORKED (with evidence)

- **[thing]** — confirmed by: [specific evidence]

If nothing confirmed: "Nothing confirmed working yet."

---

## What Did NOT Work (and why)

- **[approach tried]** — failed because: [exact reason / error message]

If nothing failed: "No failed approaches yet."

---

## What Has NOT Been Tried Yet

- [approach / idea with enough detail to act on]

---

## Current State of Files

| File | Status | Notes |
|------|--------|-------|
| `path/to/file` | Complete / In Progress / Broken / Not Started | [details] |

---

## Decisions Made

- **[decision]** — reason: [why chosen over alternatives]

---

## Blockers & Open Questions

- [blocker / question]

---

## Exact Next Step

[The single most important thing to do when resuming. Be precise enough that resuming requires zero thinking about where to start.]
```

## Notes

- Each session gets its own file — never append to a previous session's file
- "What Did NOT Work" is the most critical section — prevents wasting time on dead ends
- If saving mid-session, mark in-progress items clearly

## Companion Hook

This skill is part of the **Idle Tax** helper (01-idle-tax). The companion hook (`cache-idle-timer.sh`) warns when your prompt cache has expired after 5+ minutes of inactivity. Install the hook for automatic warnings: `cd 01-idle-tax && ./install.sh`
