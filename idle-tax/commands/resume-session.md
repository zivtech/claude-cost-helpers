---
description: Load the most recent session file and resume work with full context from where the last session ended.
---

# Resume Session

Load the last saved session state and orient fully before doing any work.

## Usage

```
/resume-session                          # loads most recent session file
/resume-session 2026-03-16               # loads most recent for that date
/resume-session path/to/file.md          # loads a specific file
```

## Process

### Step 1: Find the session file

If no argument: check `~/.claude/sessions/`, pick the most recently modified `*-session.md` or `*-session.tmp` file.

If argument is a date: search for files matching that date prefix.
If argument is a path: read that file directly.

If nothing found: "No session files found. Run /save-session at the end of a session to create one."

Also check `.omc/notepad.md` for any session pointers written by save-session.

### Step 2: Read the entire file

Read the complete file. Do not summarize yet.

### Step 3: Output a structured briefing

```
SESSION LOADED: [path]
========================================

PROJECT: [name / topic]
BRANCH: [branch if noted]

WHAT WE'RE BUILDING:
[2-3 sentence summary in your own words]

CURRENT STATE:
  Working: [count] items confirmed
  In Progress: [list]
  Not Started: [list]

WHAT NOT TO RETRY:
[list every failed approach with reason — critical]

OPEN QUESTIONS / BLOCKERS:
[list]

NEXT STEP:
[exact next step from the file, or "Not defined — review untried approaches"]

========================================
Ready to continue. What would you like to do?
```

### Step 4: Wait for the user

Do NOT start working automatically. Do NOT touch any files. Wait for direction.

If the next step is defined and the user says "continue" — proceed with that exact step.
If no next step — suggest approaches from "What Has NOT Been Tried Yet."

## Edge Cases

- **Session > 7 days old:** Note the gap — "This session is from N days ago. Things may have changed."
- **Referenced files no longer exist:** Flag during briefing.
- **Multiple files for same date:** Load the most recently modified.
- **Empty/malformed file:** Report and suggest running /save-session fresh.

## Notes

- Never modify the session file when loading — it's read-only history
- Always show "What Not To Retry" even if empty — too important to skip
