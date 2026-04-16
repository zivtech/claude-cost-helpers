---
description: Delegate a task to a subagent with its own clean context window. Keeps heavy file reading out of your main session.
---

# Delegate to Subagent

Offload file-heavy or research-heavy work to a subagent so the main session context stays lean. Subagents get their own context window and only return a summary — the files they read don't accumulate in your session.

## Process

### Step 1: Ask what to delegate

Ask the user: "What task would you like to delegate to a subagent? Describe the goal and any relevant file paths or scope."

Wait for their response before proceeding.

### Step 2: Identify if it's a good delegation candidate

Good candidates for delegation:
- Reading many files to produce a summary (e.g., "read all test files and summarize coverage gaps")
- Codebase exploration or discovery tasks (e.g., "find all places X pattern is used")
- Research tasks with bounded scope (e.g., "read the docs in /docs and extract all API endpoints")
- Auditing tasks (e.g., "check all components for accessibility issues")

Poor candidates (keep in main session):
- Tasks that require back-and-forth decisions with the user
- Small tasks (reading 1-3 files) — subagent overhead isn't worth it
- Tasks that need to modify files — delegating writes creates coordination risk

### Step 3: Wrap into an Agent tool call

Use the `Agent` tool with `run_in_background: true` and a self-contained prompt. The prompt must include all context the subagent needs — it has no memory of the current session.

Example prompt structure:
```
You are a subagent working on a specific task. Report your findings concisely.

Task: [what to do]
Scope: [which files/directories]
Output format: [what to return — bullet list, structured summary, etc.]

Do not ask clarifying questions. Work with what you have and report what you find.
```

### Step 4: Tell the user what to expect

After dispatching, let the user know:
- The subagent is running in the background
- It will return a summary — not a dump of every file it read
- While it runs, you can continue working in this session
- When it reports back, you'll review the findings together

## Examples of good delegation prompts

**Coverage gap analysis:**
> Read all test files under `src/tests/` and summarize the coverage gaps. List functions or modules that appear untested. Return a bullet list of gaps, not the full file contents.

**Pattern audit:**
> Search all `.tsx` files in `src/components/` for direct DOM manipulation (document.querySelector, innerHTML, etc.). Return a list of file paths and line numbers where this pattern appears.

**API surface extraction:**
> Read all files under `docs/api/` and extract every documented endpoint: method, path, and a one-line description. Return a markdown table.

## Notes

- Each subagent invocation is a fresh context — it knows nothing about your current session
- Subagents can read and analyze, but coordinate file writes through the main session
- For very large codebases, narrow the scope in the prompt so the subagent doesn't time out
