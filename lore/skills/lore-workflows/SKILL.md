---
name: lore-workflows
description: >
  Step-by-step Epic Games Lore (the `lore` VCS CLI) operational playbooks for game
  development - the stage → commit → push cycle, clone/create, sync (fetch+merge),
  branch create/switch/merge with conflict resolution, cherry-pick/revert, safe
  undo of local changes, gated obliterate and other destructive ops, dependencies/
  links/layers, and advisory-lock etiquette. Use whenever executing a concrete
  `lore` operation, not just discussing Lore concepts (that's the `lore` agent's
  job). For read-only inspection/analysis use the `lore-observe` skill instead.
---

# Lore Workflows

Concrete, copy-pasteable playbooks for Lore VCS operations in a gamedev repo.
Placeholders use `<ANGLE_BRACKETS>`. Every destructive playbook starts by showing
what would be lost - do not skip it.

Assumes you're in a Lore repo (`.lore/` present, `lore status` succeeds) and, for
anything touching the server, that you're authenticated (`lore login` on a real
remote; the demo server needs none). See the `lore` agent for the connection/auth
and mental-model rules. Two Lore facts drive everything below:

- **Staging pins the path, not the content** - fragments are made at *commit*, so a
  commit snapshots the file as it is *then*; no need to re-stage after further edits.
- **Commits are local; only `lore push` publishes.** "Submit" = commit **then** push.

---

## 0. The stage → commit → push cycle (the safe write cycle)

```sh
# 1. See what changed (walk the tree so nothing is missed):
lore status --scan

# 2. Stage paths. Same command for add/edit/delete. A directory (incl. `.`) stages
#    only files ALREADY marked dirty under it; --scan walks + marks + stages in one pass:
lore stage <paths>            # explicit paths
lore stage --scan .           # everything modified/added/deleted under cwd
lore stage move <from> <to>   # RENAME (keeps file identity/history - not delete+add)

# 3. Review before committing:
lore status                   # confirm the staged set
lore diff                     # working tree vs. current revision

# 4. Commit (LOCAL only) - needs a commit identity (see below):
lore commit "<message>"

# 5. Publish to the server - SHOW what's going, then push:
lore history --oneline        # the revisions you're about to send
lore push                     # append-only publish; rejected if the remote moved
```

- **Commit identity is required.** If unset, commit errors *"No commit identity
  configured..."*. Set it once with `--identity you@example.com` on `create`/`clone`, or
  add `identity` to `.lore/config.toml`. Don't invent an author on the user's behalf.
- **Undo a mis-stage** with `lore unstage <paths>` - it only removes the path from the
  stage; **working-tree content is untouched** (safe).
- **Verify the push.** A rejected push (remote advanced) is normal - go to §2 (sync),
  then push again. Never reach for `--force`.

## 1. Clone or create a repository

```sh
# Work on an existing remote repo:
lore clone <lore://host:41337/repo> <dir> [--identity you@example.com]
cd <dir> && lore status                       # confirm branch + sync state
# Narrow what materializes on a huge asset repo:
lore clone <url> <dir> --view <viewfile>      # EXCLUDE-style sparse checkout, gitignore syntax
                                               # (NOT an include-list - see §9)
lore clone <url> <dir> --use-shared-store     # dedup fragments across worktrees on one machine

# Initialize a NEW repo (there is no `lore init` - `create` is init):
mkdir <dir> && cd <dir>
lore repository create <lore://host:41337/repo> [--identity you@example.com]
```

- `--use-shared-store` lets multiple working trees on one machine share one fragment
  store (independent working trees/views/staged state) - the right call for parallel
  worktrees. Create the store first with
  `lore shared-store create <lore://host:41337>` (host:port, **no** repo path).

## 2. Sync to latest (fetch + merge = git pull)

```sh
lore sync            # fetch remote revisions + merge into local latest (produces a
                     # merge revision on divergence). There is NO separate fetch.
lore status          # confirm "in sync with remote"
```

- If `lore push` was **rejected** because the remote moved (the exact error is
  `Branch has diverged, sync to merge remote changes`): `lore sync` first (it merges,
  producing a merge revision), resolve any conflicts (§3), then `lore push`. Never
  `--force` past it.
- **`lore sync --reset` is destructive** - it overwrites local modified files to match
  incoming. Only with explicit intent to discard local edits (§5). Default to plain
  `lore sync`, which merges.
- Selective sync on a big repo: `lore sync --root-file <path> --dependency-recursive`
  filters an incoming delta down to what an asset depends on **that this repository
  instance already knows about locally** - it does not backfill unchanged dependency
  files you never materialized (§9 has the live-tested details).

## 3. Branching & merging

```sh
lore branch create <name>              # create from the current revision AND switch onto it
lore branch switch <name>              # move the working tree to an existing branch
# ...edit, then §0 to stage + commit on the branch...

# Merge a SOURCE branch into the current branch (clean merge auto-commits a merge revision):
lore branch switch main
lore sync                              # get main current first
lore branch merge <source> --message "Merge <source> into main"
lore push
```

Conflict resolution (when a merge reports conflicts):

```sh
lore branch merge resolve <paths>          # mark resolved after editing
lore branch merge resolve mine <paths>     # take current-branch side
lore branch merge resolve theirs <paths>   # take incoming side
lore branch merge unresolve <paths>        # re-mark unresolved
lore branch merge abort                    # back out of the whole merge
```

- **Per-filetype resolution.** Text/code (`.cpp`/`.h`/`.cs`/`.ini`/`.json`): editing +
  `resolve` is fine - re-read and confirm it parses/compiles before committing. Binary
  assets (`.uasset`/`.umap`/`.fbx`/`.psd`/`.png`/`.wav`, packaged builds) are **not
  safely mergeable** - pick a side (`resolve mine`/`theirs`) or use the studio's asset
  merge tool; **never blind-merge a binary**. If unsure which side is right, stop and
  ask.
- `lore branch merge into <target> <message>` merges the **current** branch *into* the
  named target (the inverse direction) - useful when you can't switch off your branch.
- **No `rebase`, no `squash`.** They're glossary concepts with no CLI command. Use
  `merge` / `cherry-pick` / `revert`; don't improvise a rebase.
- **`--no-commit`** (on `merge start`/`cherry-pick`/`revert`) stages the result without
  auto-committing, so you can review before `lore commit`.

## 4. Cherry-pick & revert

```sh
lore revision cherry-pick <revision> --message "..."   # apply one revision onto current latest
lore revision revert <revision> --message "..."        # create an anti-revision undoing one revision
lore revision bisect --start <rev> --end <rev>       # binary-search for a regressing revision
```

- Both cherry-pick and revert use the **same conflict subcommands as merge**
  (`resolve [mine|theirs]`, `unresolve`, `restart`, `abort`).
- `lore revision revert` is the safe "undo a committed change" - it *adds* a new
  revision, it does **not** rewrite history (contrast `reset`/`amend` below).

## 5. Safe undo - discarding local changes

Ordered least-destructive first. Show what would be lost before anything irreversible.

```sh
# SAFE: only un-stage (keeps your edits on disk):
lore unstage <paths>

# SAFE-ISH: park work instead of destroying it - commit to a scratch branch:
lore branch create wip/parked && lore stage --scan . && lore commit "WIP parked"

# DESTRUCTIVE: discard uncommitted local edits, restore to the current revision.
# ALWAYS inspect first:
lore status --scan            # 1. what's dirty
lore diff                     # 2. exactly what would be lost
lore reset <paths>            # 3. discard edits to those paths (git reset --hard / p4 revert)
lore reset <paths> --purge    #    ALSO deletes untracked files - call this out explicitly
```

- `lore reset` over **broad paths** wipes a lot - scope it narrowly (the path/
  `--targets` argument is required), and prefer `unstage` or a scratch-branch commit
  whenever the work might be wanted.
- **`lore branch reset <revision>`** is different and dangerous: it moves the branch's
  **latest pointer** and can orphan local commits. Show `lore branch latest list` (what
  the tip is now) and confirm before moving it.
- **`lore revision amend "<msg>"`** rewrites the latest commit (new hash). Fine while
  the revision is **unpushed**; after a push it diverges you from the remote - confirm
  it hasn't been pushed first.

## 6. Obliterate & other destructive server ops (gated)

The highest-risk commands. Each needs explicit, by-name confirmation.

```sh
# Irreversibly remove a fragment's payload bytes from the store for EVERYONE
# (the `p4 obliterate` analog - reads afterward return a typed absence):
lore file obliterate --path <PATH>
lore file obliterate --address <ADDRESS>     # by content address

lore repository delete <url>                 # delete an entire repository
lore layer remove <path> --purge             # remove a layer AND delete untracked files under it
```

- **`lore file obliterate` and `lore repository delete` are blocked by the bundled
  `guard-lore` hook** regardless of permissions - they are server-administration /
  irreversible-destruction operations. Surface exactly what's destroyed, confirm it's
  the user's remit (they operate the server), and defer to whoever runs the Lore
  deployment. Do not work around the guard.
- Before obliterating an asset, show its **dependents** (`lore file dependency list
  --reverse <path>`) so the blast radius is visible.
- `lore repository gc` runs a full GC pass on the **local** store (reclaims unreachable
  cached fragments). Incremental GC otherwise runs automatically in the background on
  writes; the global `--no-gc` flag suppresses it for a single command. A full pass is
  normally safe since history is append-only, but it's a destructive store operation -
  gate conservatively and don't run it "to tidy up" unprompted.

## 7. Dependencies, links, layers

```sh
# Dependencies - LOCAL, per-instance metadata (see caveat below); NOT staged/committed/pushed:
lore file dependency add <SOURCE> <deps>...          # record that SOURCE depends on deps
lore file dependency list <paths>...                 # forward: what <paths> depend on (paths REQUIRED, see below)
lore file dependency list --reverse <paths>...       # reverse: what depends on <paths>
lore file dependency remove <SOURCE> <deps>...       # (--force on add skips cycle detection)

# Links - reference another repo's subtree by URL; staged like a normal file change,
# so it isn't permanent/shared until you commit + push it (travels with clones after that):
lore link add <link_path> <link_url> <source_path>
lore link remove <link_path>

# Layers - LOCAL overlay only (per-machine, absent from clones); <repository> is this
# repo's ID or NAME on the current server, NOT a lore:// URL (a URL fails to resolve):
lore layer add <path> <repository> <source_path>
lore layer remove <path>                            # add --purge to also delete untracked files (DESTRUCTIVE)
```

- **Dependency edges are local-only in loreserver 0.8.5 - confirmed live.** Right after
  `lore file dependency add`, `lore commit` reports *"Nothing staged for commit"* (edges
  never touch the stage/commit cycle), `lore push` finds nothing new to send, and a fresh
  `lore clone` of the very same revision sees **zero** edges - even with
  `--remote`/`--local` explicitly passed to `dependency list`. Treat `dependency
  add`/`remove` as a personal, per-machine tool for driving *your own* selective
  clone/sync (§9), not a team-shared graph a teammate's clone will inherit. If the graph
  needs to be shared, track it out-of-band (e.g. a manifest file in the repo) until this
  changes.
- **`dependency list` needs at least one explicit path.** The `--help` text says "all
  files if omitted," but live-testing showed omitting paths (or passing a directory)
  silently prints nothing, even when edges exist - always pass the specific file(s):
  `lore file dependency list <path>` / `... --reverse <path>`.
- Use a **link** (submodule-like, recorded) when the composition must be part of
  history and reproduce on clone; use a **layer** when it's a machine-local convenience.
  Choosing wrong surprises teammates (a layer won't appear after their clone).
- **`lore link add`** clones the linked content immediately and stages the link - it
  still needs `lore commit` + `lore push` before it's permanent or visible to anyone
  else, same as any other change (confirmed: `lore link list` right after `add` showed
  "Added link and staged for commit"). The linked tree is flattened at the mount:
  content under `<source_path>` in the linked repo materializes directly under
  `<link_path>`, not nested one level deeper under `<source_path>`'s own name.
- `--force` on `dependency add` skips cycle detection - don't add it casually.

## 8. Advisory-lock etiquette

```sh
lore lock acquire <paths>              # claim a file (advisory) to coordinate on non-mergeable assets
lore lock release <paths>              # release your claim
lore lock status --branch <b> <paths>  # who holds a lock (read-only; see lore-observe §6)
```

- **Locks in Lore are advisory** - acquiring one does **not** stop another user's
  commit or push to the same file (storage/push/merge ignore locks). Treat a lock as a
  *social* coordination signal on unmergeable binaries, not a hard guarantee. Never
  tell a user a lock will prevent a conflicting push - it won't.
- This differs from Perforce `+l` (enforced at open). If the team needs hard exclusion
  on binaries, that's a workflow/social convention in Lore, not an engine guarantee.

## 9. Large binaries & selective (sparse) checkout

Lore is binary-first (fragment-level dedup), but a full game repo is still huge. Pull
only what you need - both mechanisms below were live-tested against loreserver 0.8.5
and behave differently from what the prose docs suggest:

```sh
lore clone <url> <dir> --view <viewfile>                          # EXCLUDE filter, gitignore syntax (see below)
lore clone <url> <dir> --root-file <path> --dependency-recursive  # only works if deps are known LOCALLY (see below)
lore sync  --root-file <path> --dependency-recursive              # filters a delta, does not backfill (see below)
lore file info <asset> --local                                    # local size/hash of a materialized asset
```

- **`--view <viewfile>` is a gitignore-style EXCLUDE filter, not an include-list -
  confirmed live.** A bare glob line in the view file (e.g. `Content/Materials/**`)
  *excludes* matching paths from materializing; `!pattern` re-includes. An empty or
  absent view file materializes everything. Live-testing a 3-file repo:
  - view file containing `Content/Materials/**` → cloned the *other two* files, the
    named path was left out (the opposite of an allowlist).
  - view file containing `**` (match everything) → cloned 0 files.
  - view file containing `*` then `!Content/Materials/**` → cloned exactly the one
    negated path.

  To build a sparse "only these paths" checkout, exclude everything and negate back in
  what you want:
  ```
  *
  !Content/Materials/**
  ```
  Do not hand a user a bare "list the globs you want" view file - it excludes them.
- **`--root-file <path> --dependency-recursive` cannot bootstrap a fresh clone from a
  dependency graph someone else recorded - confirmed live.** Because dependency edges
  are local-only (§7), a brand-new clone has no graph to walk: cloning a repo where two
  dependency edges were recorded (by the repo that pushed it) with `--root-file
  Content/Materials/Hero_Mat.mat --dependency-recursive` still only materialized that
  one named file ("Cloned 1/1 files") - none of its dependencies. The flag only prunes
  by edges *this* repository instance already knows about locally. If you want the
  traversal to actually pull dependents in, run `lore file dependency add` yourself
  first in that same working copy (the target files don't need to already be
  materialized for `add` to accept them).
- **`lore sync --root-file <path> --dependency-recursive` filters the sync's incoming
  delta; it does not retroactively backfill files you're missing.** Confirmed live: on
  a checkout already at the latest revision, re-running it is a no-op ("Dependency
  filter: 0 of 0 changes in inclusion set") even when dependency files exist on the
  remote but were never materialized locally - it only decides which files from
  *newly incoming* revisions to bring down, not "go fetch everything my declared
  dependencies point to right now."
- A `.lore/view` filter is **inbound** (what materializes to disk, gitignore-style
  exclude+negate per above); a `.loreignore` is **outbound** (what's excluded from
  staging/commit). Check for both before assuming a path will/won't be tracked.
- Binary assets don't diff meaningfully - report *that* a binary changed and its size
  delta, don't dump bytes. Merging binaries isn't safe (§3).

---

## Config & identity notes

- **Per-repo config**: `<repo>/.lore/config.toml` (`remote_url`, `identity`, `[store]`,
  `[file]`, shared-store keys). Written by `create`/`clone`; edited directly (there is
  no `lore config set` - `lore repository config get <KEY>` is read-only).
- **Set commit identity** before the first commit or Lore refuses to commit; the demo
  server records no author unless identity is set.
- Never handle tokens/passwords. Auth failures are the **user's** action (`lore login`),
  not something to retry as if transient.

## Validation status

Most of this playbook (§0-6, §8) is derived from Epic's official Lore docs (CLI
`0.8.x`) and mirrors the sibling `perforce`/`unreal` plugins' safety conventions; see
`../NOTES.md` for what has and hasn't been exercised for those sections against a live
`lore` server (demo mode).

**§7 (dependencies, links, layers) and §9 (selective clone/sync, view filters) are now
live-validated** against a real `loreserver 0.8.5` instance (two repositories, a
dependency graph, a cross-repo link, and a layer). Every command shown in those two
sections was actually run; every callout describing non-obvious or doc-contradicting
behavior (dependency edges being local-only, `--view` being an exclude filter,
`--root-file --dependency-recursive` not working on a fresh clone, `dependency list`
needing explicit paths, `layer add`'s repository argument being an ID/name not a URL)
reflects observed CLI output, not docs prose. Locks (§8), and the core stage/commit/
push/sync/branch/merge/obliterate flows (§0-6), remain doc-derived pending their own
live pass.

Because Lore is pre-1.0, **re-derive any command whose flags look off from `lore <cmd>
--help` on the installed binary** before relying on the exact spec - the CLI surface
can and does drift between patch releases.
