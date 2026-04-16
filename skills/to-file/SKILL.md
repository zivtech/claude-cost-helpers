---
name: to-file
description: Run a command and redirect output to a temp file instead of dumping it into context. Returns the file path, line count, and a preview (first/last 10 lines). Use for test runs, build logs, or any command with large output. Part of claude-cost-helpers (05-watching-cost).
---

# To File

Run a command and capture its output to a temp file instead of printing it into context. Use this when the command would produce large output (test runs, build logs, directory listings, file contents) that you don't need in full right now.

## Usage

```
/to-file <command>
Example: /to-file npm test
```

## Process

1. Take the user's command as the input (everything after `/to-file`)
2. Generate a short hash from the command string for a unique filename
3. Run the command via Bash, redirecting stdout to `/tmp/claude-output-<short-hash>.txt`
4. Report back:
   - Full file path
   - Line count (`wc -l`)
   - First 10 lines (`head -10`)
   - Last 10 lines (`tail -10`)
5. Remind the user: "The full output is saved at `<filepath>`. Read specific sections with `Read <filepath>` using `offset` and `limit` parameters."

## Example

User: `/to-file npm test`

Claude runs:
```bash
HASH=$(echo "npm test" | md5 | cut -c1-8)
OUTFILE="/tmp/claude-output-${HASH}.txt"
npm test > "$OUTFILE" 2>&1
echo "File: $OUTFILE"
echo "Lines: $(wc -l < "$OUTFILE")"
echo "--- First 10 lines ---"
head -10 "$OUTFILE"
echo "--- Last 10 lines ---"
tail -10 "$OUTFILE"
```

Then tells the user: "Full output is at `/tmp/claude-output-a1b2c3d4.txt` — use `Read /tmp/claude-output-a1b2c3d4.txt offset:40 limit:20` to read specific sections."

## Why this helps

Every line of output that appears in the conversation sits in context permanently and is reprocessed on every subsequent message. A 5,000-line test run pasted into context costs roughly the same as 5,000 lines of your own code — but unlike your code, it has zero value after the first glance. Redirecting to a file keeps context clean and costs near zero. You can always read the parts that matter.

## Companion Hook

This skill is part of the **Watching Cost** helper (05-watching-cost). The companion hook (`output-size-monitor.sh`) automatically warns when tool output exceeds 5K tokens per call and tracks cumulative output with escalating alerts at 25K, 50K, and 100K tokens. Install the hook for automatic warnings: `cd 05-watching-cost && ./install.sh`
