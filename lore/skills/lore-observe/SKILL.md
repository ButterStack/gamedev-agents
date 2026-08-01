---
name: lore-observe
description: >
  Read-only Epic Games Lore (the `lore` VCS CLI) observability & analysis
  playbooks - snapshot working-tree/branch/remote state, read revision history
  and velocity, diffs, branch and per-file history, the file dependency graph,
  advisory-lock/link/layer state, and repository verification. Use for inspecting
  and reasoning about a Lore repository WITHOUT changing it. For operations that
  modify the repo (stage, commit, push, sync, branch, merge, reset, obliterate)
  use the `lore-workflows` skill instead.
---

# Lore Observe & Analyze

Read-only playbooks for understanding a Lore repository. **Nothing here mutates the
repo or the remote** - every command is safe for inspection. A few ground rules:

- Lore is pre-1.0 - confirm commands against the installed binary
  (`lore --help` / `lore <cmd> --help`) if a flag looks off; this reference is pinned
  to CLI `0.8.x`.
- Most inspection works **offline** (add `--offline` to force it); only push/sync
  touch the server.
- `lore status` by default does **no filesystem walk** - it reads tracked dirty flags.
  `--scan` walks the tree and *persists* refreshed dirty flags (a local metadata
  write, still safe); `--reset` **drops** the staged anchor (discards local staging/
  dirty tracking) - don't use it just to look.
- Prefer `--oneline` on history and `-P/--no-pager` when you'll parse the output.

---

## 1. Working-tree & repository snapshot

```sh
lore --version                     # CLI version (surface drifts pre-1.0)
lore status                        # staged revision + files/dirs marked dirty (NO fs walk)
lore status --scan                 # walk the tree, reconcile every file, show full staged set
lore repository info               # remote URL / server-of-record, repo identity
lore branch info                   # current branch + its latest revision
lore branch list                   # all branches (add --archived to include archived)
lore auth info                     # current identity (read-only; omit --with-token)
```

- Resolve **who/where** from `lore` output, not the shell env. The remote lives in
  `lore repository info` (or `.lore/config.toml`'s `remote_url`); the branch and its
  latest revision in `lore branch info`.
- Report a concise snapshot: current branch, whether it's **in sync / ahead / behind**
  the remote, what's dirty vs. staged, and anything risky (large binaries dirty,
  a detached/older synced revision).
- **No `.lore/` directory?** You're not in a Lore repo - say so; don't guess.

## 2. Revision history & velocity

```sh
lore history                       # repo revision list (the `git log` equivalent - there is NO `lore log`)
lore history --oneline             # compact, one revision per line
lore history 50                    # limit to the last 50 revisions (LENGTH is positional)
lore history --branch <branch>     # history along a specific branch
lore revision info <revision>      # detail for one revision (--delta for changes, --metadata)
lore branch latest list --branch <b> [LIMIT]   # history of a branch's latest pointer
```

Analyses to derive:

- **Velocity** - revisions per day/week from the timestamps; active vs. quiet periods.
- **Contributors** - group by author identity (present only if committers set
  `--identity`; the demo server records none). Note if identity is unset repo-wide.
- **Hot paths** - which top-level directories churn most (cross-reference `lore diff`
  / `lore revision info --delta`), i.e. art vs. code vs. audio.
- Cap large scans with the positional `LENGTH`; a busy binary-heavy repo has deep
  history.

## 3. Diffs & inspecting a change

```sh
lore diff [paths]...                       # working tree vs. current revision (default)
lore diff --source <rev> --target <rev>    # between two revisions of a file/path
lore diff --diff3 [paths]                  # 3-way conflict-marker output
lore diff -U <n> [paths]                   # n context lines (default 3)
lore revision diff <rev_source> --target <rev>   # diff two whole revisions
lore branch diff <target> --source <b>     # diff two branches via common ancestor
```

- With no `--source`/`--target`, `lore diff` compares the **current revision to the
  current filesystem state** - the "what have I changed locally" view.
- `--ignore-space-at-eol` / `--ignore-space-change` cut whitespace noise on text.
- Binary assets won't produce a meaningful textual diff - report *that a binary
  changed* (and its size delta from `lore file info`), not a byte dump.

## 4. Branches

```sh
lore branch list [--archived]      # branches (archived ones hidden by default)
lore branch info [branch]          # a branch's latest revision + metadata
lore branch diff <target> --source <b>            # divergence between two branches
lore branch latest list --branch <b>              # how the branch tip has moved
lore branch metadata get --branch <b> [key]       # mutable branch annotations
```

- A Lore branch is a **named, mutable pointer** with a **stable opaque ID separate
  from its human-readable name** - a name can be archived and the ID/history survive.
  The default branch is `main`.
- There is **no true "delete a branch"** - only `lore branch archive` (removes it from
  the default listing; `--archived` still shows it). Report that honestly if asked to
  delete one.

## 5. File history, info, and the dependency graph

```sh
lore file history <PATH> [LENGTH]  # revisions touching one file (--oneline, --depth)
lore file info <paths>             # size/type/hash for file(s) (--local, --filtered, --revision)
lore file hash <paths>             # compute a local file's BLAKE3 address
lore file dependency list [paths]  # dependencies of a file
lore file dependency list --reverse <paths>       # dependents (who depends ON this)
lore file dependency list --recursive --tag <t> <paths>
```

- `lore file history` is the closest thing to `git log <file>`. **There is no
  `blame`/annotate** - per-line authorship isn't exposed; say so if asked rather than
  faking it.
- **Dependencies are first-class in Lore** (they drive selective clone/sync via
  `--root-file`/`--dependency-*`). Use `dependency list --reverse` to find what would
  break if an asset changed - the blast-radius view for a binary asset.

## 6. Advisory locks, links, and layers (state queries)

```sh
lore lock status --branch <b> [paths]     # who holds locks (READ-ONLY)
lore lock query --owner <id>              # locks by owner / path / branch
lore link list [--staged]                 # linked repos (recorded in the revision)
lore layer list                           # local overlays (per-machine, not in any revision)
```

- **Locks are advisory** - a held lock does **not** block another user's commit/push.
  Report the holder for coordination, but never present a lock as a hard guarantee.
- **Links** travel with every clone (recorded in the revision; each is its own
  partition/access boundary); **layers** are local-only (absent from clones). Don't
  confuse the two when explaining why a path is/isn't present after a fresh clone.

## 7. Repository health & store queries

```sh
lore repository verify state            # consistency check (READ-ONLY without --heal)
lore repository verify fragment <HASH>  # verify a specific fragment (READ-ONLY without --heal)
lore repository store immutable query <ADDRESS>   # query the content-addressed store
lore repository dump                    # diagnostic state dump (--path, --revision, --max-depth)
lore logfile info                       # logfile location/info
```

- **`lore repository verify` is read-only only WITHOUT `--heal`.** `--heal` mutates
  (re-fetches/repairs) - that belongs to `lore-workflows`, not here. Never add
  `--heal` during a read-only pass.
- `repository dump` and `store immutable query` are low-level diagnostics - use them
  to explain *why* something's missing (e.g. a fragment obliterated → typed absence),
  not for routine reporting.

---

## Example - a filled status briefing

From `lore status --scan` + `lore branch info` + `lore history --oneline`:

> **Repo `my-project` - branch `main`**
> - Sync: local is **1 revision behind** the remote (`lore sync` to catch up).
> - Working tree: 3 files dirty (`Art/Hero.uasset`, `Config/Game.ini`,
>   `README.md`), 1 staged (`Config/Game.ini`).
> - Recent: ~9 revisions this week, steady; last commit "Rebalance boss HP" 2h ago.
> - Identity: unset repo-wide - commits won't record an author until `--identity`
>   is set. Flagged.
> - Nothing locked by others.

(Shape illustrative; fill from real command output.)

## Caveats

- **Pre-1.0 surface drift.** Commands/flags may change between `0.x` releases -
  re-check `lore <cmd> --help` on the installed binary if something errors.
- **JSON output is not guaranteed.** The docs hint at a machine-readable mode but the
  flag isn't documented; parse `--oneline`/plain output unless you've verified a JSON
  flag works here. Don't assume `--json`.
- **`lore status` without `--scan` can under-report** - it trusts existing dirty
  flags and skips the FS walk. If drift is suspected after out-of-band edits (a DCC
  tool, a build step), run `--scan`.
- **Sparse/lazy working trees**: a path may be versioned but not materialized locally.
  `lore file info` reports repo-side facts even when the file isn't on disk.

## Notes

- Keep everything here read-only. If analysis reveals work to do (commit drift, sync,
  resolve a conflict, obliterate), hand off to `lore-workflows` and re-confirm with the
  user before mutating.
- Large history/dependency scans: cap with the positional `LENGTH`/`--depth` and scope
  to a path; a binary-heavy repo's full history can be large.
