---
description: Guided, safe Perforce sync - dry-run preview, scope confirmation, then real sync
argument-hint: [depot-path-or-subtree]
---

Guide the user through a safe `p4 sync`, defaulting to the workspace root
if no path is given: `$ARGUMENTS`.

Steps:

1. Confirm connection context with `p4 info` if not already established
   this session.
2. Determine scope: use `$ARGUMENTS` as the depot path/subtree if provided,
   otherwise sync the full client view. Prefer narrowing scope for large
   asset trees rather than syncing everything by default when the user
   hasn't specified.
3. **Dry run first**: `p4 sync -n <scope>`. Summarize what would change -
   file counts, rough size if determinable, anything that looks like a
   large binary/asset batch.
4. If the preview is large or touches asset directories, flag it and get
   explicit confirmation before proceeding.
5. Check for conflicts with open files: warn if any file in the sync scope
   is currently open for edit in a pending changelist (syncing over an open
   file can require a resolve).
6. Run the real sync: `p4 sync <scope>` (for large game trees add
   `--parallel=threads=4` and `-q` to speed up big transfers).
7. Report results: files updated, any that failed (locked, needs resolve,
   clobbered), and next steps if resolve is needed (point to the
   `p4-workflows` skill's resolve playbook).

Never pass `-f` (force resync) without explicit user confirmation - it can
discard local modifications outside of p4's tracking.

**Example:** *"Sync the Art tree to latest."* → `p4 sync -n //<depot>/Art/...` first,
summarize the batch (file count / rough size), confirm if large, then
`p4 sync //<depot>/Art/...`.

Caveat: on a **stream** workspace, sync a stream path/changelist/label the same way
(`//<depot>/<stream>/...@<label>`); the client's Stream mapping already scopes what
you receive. Never `-f` (force resync) without confirmation - it discards local
modifications p4 isn't tracking.
