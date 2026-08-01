---
description: Guided, safe Lore sync - check state, warn about local edits, then fetch + merge from the remote
argument-hint: "[revision]"
---

Guide the user through a safe `lore sync` (Lore's `git pull` - **fetch + merge** in one
step; there is no separate fetch). Use the `lore-workflows` skill (§2) for exact forms.

Steps:

1. **Establish state** - `lore branch info` (current branch + whether local is behind
   the remote) and `lore status --scan` (any dirty/staged local work). If already in
   sync, say so and stop.
2. **Protect local work.** If the working tree has uncommitted edits, warn that syncing
   will merge remote changes into them. If the user's real intent is to *discard* local
   edits, that's `lore sync --reset` - a **destructive** overwrite of local modified
   files - and must be confirmed explicitly by name; never add `--reset` on your own.
3. **Sync** - `lore sync` (optionally `lore sync <revision>` to sync to a specific
   revision). On divergence this produces a **merge revision** - that's normal.
4. **Resolve conflicts if any** - `lore branch merge resolve <paths>` (or
   `resolve mine|theirs`); for binary assets pick a side, never blind-merge. See the
   `lore-workflows` skill (§3). `lore branch merge abort` backs out.
5. **Report** - confirm the branch is now in sync, and note any files that needed
   resolution. If the user was mid-push and got rejected, remind them the flow is
   **sync → resolve → `lore push`** (never `--force`).

For a large asset repo, mention selective sync: `lore sync --root-file <path>
--dependency-recursive` pulls only what an asset depends on.

**Example:** *"Get me current with the server."* → `lore branch info` shows 2 revisions
behind, working tree clean → `lore sync` → "in sync; fast-forwarded 2 revisions, no
conflicts."
