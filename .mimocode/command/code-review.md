---
description: "Run three-pronged code review (Efficiency + Quality + Reuse) on uncommitted changes or a specified commit range. Spawns 3 parallel subagents, synthesizes findings into a prioritized fix list."
---

# Three-Pronged Code Review

Run a structured code review on uncommitted changes (or a specified diff) by spawning three parallel subagents, then synthesize their findings.

## Usage

```
/code-review                    # Review uncommitted changes (git diff HEAD)
/code-review HEAD~3..HEAD       # Review a specific commit range
/code-review <branch>           # Review diff against another branch
```

## Procedure

### Step 1: Generate the diff

```bash
# Default: uncommitted changes
git diff HEAD > /tmp/review_diff.txt

# Or for a commit range:
git diff $ARGUMENTS > /tmp/review_diff.txt
```

If the diff is empty, report "No changes to review" and stop.

### Step 2: Get context

```bash
git diff --stat HEAD
```

### Step 3: Spawn 3 parallel review subagents

Spawn all three simultaneously. Each reads `/tmp/review_diff.txt`.

**Subagent 1 — Code Reuse Review:**
- Description: "Code reuse review"
- Prompt: "Review the diff at `/tmp/review_diff.txt` for CODE REUSE opportunities. Search for existing utilities, helpers, widgets, or patterns in the codebase that could replace newly written code. Flag: duplicated logic, missed abstractions, reinvented wheels. For each finding: file:line, what to reuse instead, severity (critical/high/medium/low)."

**Subagent 2 — Code Quality Review:**
- Description: "Code quality review"
- Prompt: "Review the diff at `/tmp/review_diff.txt` for CODE QUALITY issues. Check: redundant state, parameter sprawl, copy-paste variation, leaky abstractions, naming, error handling, unnecessary complexity. For each finding: file:line, issue description, suggested fix, severity."

**Subagent 3 — Efficiency Review:**
- Description: "Efficiency review"
- Prompt: "Review the diff at `/tmp/review_diff.txt` for EFFICIENCY issues. Check: unnecessary work, missed concurrency, hot-path bloat, recurring no-op updates, O(n²) in loops, unnecessary rebuilds, redundant DB/file reads. For each finding: file:line, impact, suggested optimization, severity."

### Step 4: Synthesize findings

After all 3 subagents return:
1. Merge findings, deduplicate
2. Sort by severity: critical → high → medium → low
3. For each finding, include: source subagent, file:line, issue, suggested fix
4. Present a concise prioritized list

### Step 5: Apply fixes (optional)

If the user says "fix" or "apply", iterate through critical and high findings, applying fixes one by one with verification (`flutter analyze` for Dart files).

## Notes

- This command is designed for Flutter/Dart projects but works for any codebase
- The diff is saved to `/tmp/review_diff.txt` — subagents read it from there
- For large diffs (>5000 lines), consider splitting by module first
