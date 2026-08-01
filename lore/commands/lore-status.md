---
description: Summarize the current Lore VCS state (branch, sync vs. remote, staged/dirty files, recent revisions, anything risky)
argument-hint: "[path-subtree]"
---

Summarize the current Epic Games **Lore** VCS state for the user. Read-only - run no
write/destructive command in this workflow. Use the `lore-observe` skill for the exact
command forms. Scope to `$ARGUMENTS` if a path is given, else the whole working tree.

Gather and report, in order:

1. **Repo & version** - confirm you're in a Lore repo (`.lore/` present, `lore status`
   succeeds) and note `lore --version`. If there's no `.lore/`, say so - this isn't a
   Lore repository; stop rather than guessing.
2. **Branch & sync state** - `lore branch info` (current branch + latest revision) and
   whether the local branch is **in sync with / ahead of / behind** the remote
   (`lore repository info` for the remote URL). Being behind ⇒ suggest `/lore-sync`.
3. **Working tree** - `lore status --scan` (walk the tree so nothing out-of-band is
   missed) grouped into **staged** vs. merely **dirty**, noting action (add/edit/
   delete) and flagging large binaries (`.uasset`/`.umap`/`.fbx`/`.psd`/audio) that are
   dirty.
4. **Recent history** - `lore history --oneline` (last ~10) for context on what landed
   recently and when.
5. **Commit identity** - if `identity` is unset (`lore auth info` / no author on recent
   revisions), flag that commits won't record an author until it's set (`--identity` or
   `.lore/config.toml`).
6. **Locks by others** - only if relevant: `lore lock status` for advisory locks other
   users hold on files in scope (remember Lore locks are advisory - they don't block a
   push).

Present a concise summary - what's staged/dirty, whether you're ahead of/behind the
remote, what's ready to push, and anything risky (large binaries dirty, unset identity,
a merge in progress) - not raw command dumps. For history/velocity use `/lore-log`; for
a change preview use `/lore-diff`; to catch up to the remote use `/lore-sync`.

**Example:** *"What's my Lore state?"* → a snapshot: on branch `main`, 1 revision behind
the remote; 3 files dirty, 1 staged; identity set; nothing locked by others. Prose, not
raw output.
