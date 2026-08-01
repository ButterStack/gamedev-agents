---
description: Read Lore revision history - recent revisions, velocity, contributors, and hot paths (read-only)
argument-hint: "[path-or-branch]"
---

Summarize Epic Games **Lore** VCS history for the user. Read-only - run no write
command. Use the `lore-observe` skill (§2) for exact command forms. If `$ARGUMENTS`
names a path, scope to per-file history; if it names a branch, scope to that branch;
otherwise report whole-repo history.

Gather and report:

1. **Recent revisions** - `lore history --oneline` (default ~20; cap with the positional
   `LENGTH` on a deep repo). For a specific file use `lore file history <path> --oneline`;
   for a branch, `lore history --branch <branch> --oneline`. Note: there is **no
   `lore log`** - `lore history` is the equivalent, and there is **no `blame`**.
2. **A specific revision**, if the user asked about one - `lore revision info <rev>
   --delta` for what it changed.
3. **Velocity** - revisions/day or /week from the timestamps; call out active vs. quiet
   periods.
4. **Contributors** - group by author identity **if committers set `--identity`**; if
   identity is unset repo-wide (common on a demo/local server), say so rather than
   reporting "no authors" as if it were meaningful.
5. **Hot paths** - which top-level directories churn most (art vs. code vs. audio), from
   the revision deltas.

Present a concise briefing, not a raw dump. For the current working-tree state use
`/lore-status`; to preview uncommitted changes use `/lore-diff`.

**Example:** *"What's landed this week?"* → ~9 revisions, steady, quietest on the
weekend; top contributor is the CI account; churn concentrated under `Content/Art/`.
