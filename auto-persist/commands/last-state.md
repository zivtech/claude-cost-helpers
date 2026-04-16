---
description: Print the most recent auto-persisted session state (git, cwd, recent files) without asking Claude to recall
---

Read the most recent auto-state snapshot and summarize where I left off.

Steps:
1. List `~/.claude/sessions/auto-state/*.md` sorted by mtime, newest first
2. Read the newest `.md` file
3. Print its contents verbatim, then add one line: "To resume, open the repo at the CWD above and start a fresh session — the git state and recent files tell you what was in flight."

If no files exist, print: "No auto-state files yet. The Stop hook writes one after your first Claude turn in this installation."

Do not fabricate a narrative summary. The value of auto-state is that it is the ground truth written by a shell after every turn, not an LLM recollection. Pass the file contents through as-is.
