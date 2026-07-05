---
name: audit-fix-reaudit
description: "Structured workflow for reading an audit report, fixing issues in priority order (CRITICAL → HIGH → MEDIUM), and conducting a new audit round. Designed for iterative code quality improvement cycles."
---

# Audit-Fix-Reaudit Workflow

A structured playbook for iterating on audit reports: read → fix by priority → verify → re-audit.

## When to Use

- User provides an audit report (`.md` file) with categorized issues
- User asks to "fix the issues" or "do another round of audit"
- Any iterative quality improvement cycle (audit round N → fix → round N+1)

## Workflow

### Phase 1: Read and Parse the Audit Report

1. Read the full audit report file
2. Extract issues by severity:
   - **CRITICAL** (C1-Cn): Must fix — data corruption, security, broken functionality
   - **HIGH** (H1-Hn): Should fix — poor UX, performance, maintainability
   - **MEDIUM** (M1-Mn): Nice to fix — style, minor inconsistencies
   - **LOW**: Note but don't fix in this round
3. For each issue, identify the referenced file(s) and line(s)
4. Create a task for each severity group

### Phase 2: Read All Referenced Files

Before making any changes:
1. Read every file referenced by CRITICAL issues (in parallel if possible)
2. Read files referenced by HIGH issues
3. Note which issues appear already partially fixed (the report may be stale)

### Phase 3: Fix in Priority Order

**CRITICAL issues first:**
- For each Cn, verify the issue still exists in current code
- If already fixed: mark as "verified fixed" with evidence
- If still present: apply the minimal fix, verify with `flutter analyze`
- Never skip a CRITICAL issue — if blocked, document why

**HIGH issues next:**
- Same process as CRITICAL
- For HIGH issues, prefer fixes that don't change public API

**MEDIUM issues last:**
- Only fix if they don't risk regressions
- Batch related MEDIUM fixes together

### Phase 4: Verify All Fixes

After all fixes are applied:
```bash
flutter analyze --no-pub
flutter test  # if tests exist
```

Check for:
- No new warnings introduced
- No `catch (_)` patterns (use `swallowDebug` instead)
- No hardcoded course names (use `{courseName}` placeholders)
- `localizationsDelegates` in `main.dart` is `AppL10n.localizationsDelegates` (not empty)

### Phase 5: Conduct New Audit Round

After fixes are verified:
1. Re-read all modified files
2. Look for issues the original report missed
3. Check if any fixes introduced new problems
4. Write a new audit report in the same format as the original:
   - `docs/MAD-KGDT审核报告(<Model>-第<N+1>轮).md`
   - Include: new issues found, previously fixed issues verified, remaining issues
5. Present summary to user

## Key Rules (from CLAUDE.md)

- All fixes must be **platform-agnostic** — not hardcoded to a specific course
- Agent personas use `{courseName}` placeholder (via `base_agent.dart:promptWithCourse()`)
- AI skill examples must be generic, not Flutter/Android-specific
- Forbidden: `catch (_) {}` — must use `swallowDebug(e, tag: '...')`
- Forbidden: `localizationsDelegates: const []` — must use `AppL10n.localizationsDelegates`
- Forbidden: `withOpacity()` — use `color.withValues(alpha: 0.x)`

## Output Format

The new audit report should follow this template:

```markdown
# <Project>审核报告(<Model>-第<N+1>轮)

## 审核概要
- 审核轮次: 第<N+1>轮
- 审核模型: <Model>
- 上轮修复: <N> 项已修复 / <M> 项未修复

## CRITICAL (<n> 项)
| # | 问题 | 文件 | 状态 | 说明 |
|---|------|------|------|------|

## HIGH (<n> 项)
...

## MEDIUM (<n> 项)
...

## LOW (<n> 项)
...

## 修复建议
...
```
