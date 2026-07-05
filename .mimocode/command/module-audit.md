---
description: "Audit a Flutter module's current implementation state. Spawns an Explore subagent to map files, report actual state, completeness, and gaps before making changes."
---

# Module Audit

Explore a Flutter module's current implementation state before starting work. Produces a structured report: what exists, what's complete, what's missing.

## Usage

```
/module-audit <module-path>               # Audit a specific module directory
/module-audit <module-path> --focus <topic>  # Focus on a specific aspect
```

Examples:
```
/module-audit lib/presentation/pages/archive/
/module-audit lib/services/agent/ --focus "persona placeholders"
/module-audit lib/presentation/pages/achievement/ --focus "score calculation weights"
```

## Procedure

### Step 1: Locate the module

Use Glob to find all `.dart` files under the specified path:
```
Glob: <module-path>/**/*.dart
```

### Step 2: Spawn an Explore subagent

Description: "Audit <module-name>"
Subagent type: "Explore"

The subagent should:
1. Read every file under the module path
2. For each file, report:
   - **Actual responsibility** (what it really does, not what the name implies)
   - **Completeness** (fully implemented / partial / stub / TODO markers)
   - **Gaps** (missing features, hardcoded values, incomplete error handling)
   - **Dependencies** (what it imports, what depends on it)
3. Identify cross-cutting concerns:
   - Hardcoded strings that should be dynamic (course names, paths, etc.)
   - Missing error handling (bare `catch (_)`, no `swallowDebug`)
   - Inconsistent patterns vs. rest of codebase
4. Produce a structured summary:
   - **Files N**: X complete, Y partial, Z stub
   - **Top 3 gaps** (ranked by impact)
   - **Recommended next steps**

### Step 3: Present findings

Format the subagent's output into a clean report with:
- Module overview (files, lines, responsibilities)
- Completeness matrix (file × status)
- Gap analysis (what needs work)
- Recommended action plan (priority-ordered)

## Notes

- This command is specifically tuned for Flutter/Dart projects using the DAO → Service → Page pattern
- The Explore subagent reads files directly — no code changes are made
- Use this before starting any feature work on an unfamiliar module
- The `--focus` flag narrows the audit to a specific concern (e.g., "error handling", "i18n", "platform compatibility")
