---
name: p4-workflows
description: >
  Step-by-step Perforce (Helix Core) operational playbooks for game development -
  check out before edit, sync, checkout & submit (with the safe write cycle),
  shelve/unshelve, reconcile offline edits, resolve conflicts, revert safely,
  exclusive-lock (+l) etiquette, streams (merge-down/copy-up), and engine
  typemap/P4IGNORE presets. Use whenever executing a concrete p4 operation, not
  just discussing p4 concepts (that's the `perforce` agent's job). For read-only
  inspection/analysis use the `p4-observe` skill instead.
---

# P4 Workflows

Concrete, copy-pasteable playbooks for Perforce operations in a gamedev depot.
Placeholders use `<ANGLE_BRACKETS>`. Every destructive playbook starts with a
dry-run (`-n`) - do not skip it.

Assumes connection info is resolved (`p4 info` succeeds) and you hold a valid
ticket (`p4 login -s` shows an expiry, not `session has expired`). Resolve identity
from `p4 info`, never from `$USER`/env. See the `perforce` agent for connection,
auth, and read-only-checkout rules.

---

## 0. Check out before you edit (the read-only model)

Perforce files are **read-only on disk until opened for edit**. Open first, then
modify with normal tools:

```sh
p4 edit -c <CL> <file>     # existing file → now writable, tracked
# ... make edits with Edit/Write ...
p4 add  -c <CL> <file>     # brand-new file
p4 delete -c <CL> <file>   # removal (don't just rm on disk)
```

- If you (or a tool) already modified files **without** opening them, don't panic -
  stage the drift with reconcile (§4) instead of losing it.
- A file that is already writable is already open; `p4 opened <file>` confirms.

## 1. Sync to latest

```sh
p4 sync -n //<depot_path>/...@<label_or_change_or_now>   # preview first
p4 sync    //<depot_path>/...@<label_or_change_or_now>   # same spec you previewed
```

- Scope to a subtree (`//depot/Project/Art/...`) instead of the whole depot - large
  binary syncs are slow and bandwidth-heavy.
- `p4 sync -f` (force resync) discards local state; only with confirmed intent.
- If a sync reports files needing resolve, go to §5.

## 2. Check out, edit, and submit - the safe write cycle

```sh
# Numbered changelist with a description. Do this NON-INTERACTIVELY - an agent can't
# drive `p4 change`'s $EDITOR (it will hang the shell). Prints "Change <n> created.":
p4 --field "Description=<desc>" change -o | p4 change -i
# older clients (pre-2017.2): p4 change -o | sed 's/<enter description here>/<desc>/' | p4 change -i

p4 edit -c <CL> <file_or_pattern>
# ... edits ...

# Review before submitting
p4 opened -c <CL>
p4 diff        # no -c flag; pass the opened file paths to scope it

p4 submit -c <CL>
```

- New/removed files: `p4 add -c <CL> <file>` / `p4 delete -c <CL> <file>`.
- **Always show the changelist description and file list before `p4 submit`** - treat
  it as a confirmation gate.
- **Verify the submit actually succeeded.** p4 does not always fail loudly - a submit
  can report warnings (e.g. "no files to submit", a trigger rejection) without an
  obvious error. Confirm the new submitted change number came back and no
  files were left open (`p4 opened -c <CL>` should be empty afterward).

**Offline / bulk reconcile pattern - AUTOMATION CLIENTS ONLY.** This was proven on a
*dedicated importer client* that never holds human work. **Never run it in a
developer's workspace**: the opening `revert` discards everything open under the path,
and reverting a `+l` asset also releases its exclusive lock. In a real workspace use
the gated §6 order (`opened` → `shelve` → `revert -n` → `revert`) instead.

```sh
# Only on a dedicated automation client with no human work open:
p4 revert //<depot>/...              # clean slate; "nothing to revert" is fine
# (materialize the files into the workspace root)
p4 reconcile -c <CL> //<depot>/...   # stage add/edit/delete into a NUMBERED CL
p4 opened    -c <CL> //<depot>/...   # IF EMPTY, stop - nothing to submit
# show the description + file list, get confirmation, then:
p4 submit -c <CL>                    # a numbered CL, never the default; verify success
```

## 3. Create, shelve, and unshelve a changelist

Shelving uploads pending changes to the server *without* submitting - for handing
work to another machine, backing up WIP, or freeing a workspace without losing
edits.

```sh
p4 --field "Description=<desc>" change -o | p4 change -i   # non-interactive (§2); note the CL
p4 shelve -c <CL>                  # shelve everything in that CL
p4 changes -s shelved -u <USER>    # see what's shelved
p4 unshelve -s <CL> -c <TARGET_CL> # restore into a (usually new) CL
p4 shelve -c <CL> -r               # update an existing shelf after more edits
```

- Prefer this over `p4 revert` any time the work might be wanted back.
- Shelved changes are visible to teammates - mention that if content is sensitive.

## 4. Reconcile offline / out-of-band edits

Game pipelines routinely touch files outside `p4 edit` (DCC tools, build scripts,
generated content, Finder/Explorer). `p4 reconcile` finds and stages the drift.

```sh
p4 reconcile -n //<depot_path>/...          # preview only - changes nothing
p4 reconcile -c <CL> //<depot_path>/...      # stage into a changelist
p4 status                                    # workspace-relative preview (like -n)
# On big game trees, add -m to reconcile/status: compares MODTIME instead of
# digesting every file's content - dramatically cheaper (misses same-modtime edits):
p4 reconcile -n -m //<depot_path>/...
```

- Always show the dry-run and let the user confirm before writing.
- **Never use `p4 clean`** to "tidy" drift - it force-reverts the workspace to depot
  state, deleting local files the depot doesn't know about. Same bar as revert.
- **Respect ignores.** Check for a `P4IGNORE` file. If none exists but the tree has
  obvious build output - Unreal (`Binaries/`, `Intermediate/`, `Saved/`,
  `DerivedDataCache/`), Unity (`Library/`, `Temp/`, `Logs/`) - flag it rather than
  reconciling hundreds of junk files in. See §9 for preset ignore contents.

## 5. Resolve conflicts

Happens after a `p4 sync` or integrate/merge brings in changes that overlap your
open files.

```sh
p4 resolve -n            # what needs resolving
p4 resolve               # interactive (text - safe to auto-merge non-overlapping hunks)
p4 resolve -at <file>    # accept theirs
p4 resolve -ay <file>    # accept yours
p4 resolve -am <file>    # accept merge (auto-merge, TEXT ONLY)
```

Per-filetype heuristics:

- **Text/code** (`.cpp`, `.h`, `.cs`, `.ini`, `.json`): `-am`/interactive is fine.
  After merging, re-read the file and confirm it compiles/parses before submitting.
- **Binary & most game assets** (`.uasset`, `.umap`, `.fbx`, `.psd`, `.png`, `.wav`,
  packaged builds): **not safely auto-mergeable.** Resolve by picking a side
  (`-at`/`-ay`) or using a studio external merge tool (e.g. Unreal's asset merge).
  **Never run `-am` on a binary filetype.**
- If unsure which side is correct on a binary, **stop and ask** - don't guess on the
  user's behalf.

## 6. Revert safely

The most dangerous common operation. Follow this order every time:

```sh
p4 opened -c <CL>              # 1. what's open / would be lost
p4 diff                        # (pass opened files to scope; there's no -c on diff)
p4 shelve -c <CL>              # 2. shelve first if the work might be wanted later
p4 revert -n -c <CL> //...     # 3. dry-run the revert
p4 revert    -c <CL> //...     # 4. only then, for real
```

- Never revert a changelist you didn't just review with the user; never revert
  another user's changelist.
- Single file: `p4 revert <file>` - same dry-run-first discipline.
- `p4 revert -a` (revert only unchanged files) is low-risk - it touches only
  zero-diff files.

## 7. Exclusive-lock (+l) etiquette

Binary/asset files are often `binary+l` (exclusive checkout): only one person can
have them open for edit at a time, because they can't be merged. Artists/designers
routinely get blocked by a lock someone else holds.

```sh
# Who has files open/locked across ALL clients/users (cap on big trees)
p4 opened -a -m 200 //<path>/...
# EDGE servers: `opened -a` is edge-local - use -x for globally-tracked +l opens
# (errors "only supported in a distributed configuration" on a classic server):
p4 opened -x //<path>/...
# Owner detail for a SPECIFIC opened file - otherOpen/otherLock appear by DEFAULT
# (no -O flag; don't fstat a whole subtree):
p4 -ztag fstat //<path>/<asset>
```

- `otherOpen`/`otherLock` in `fstat` name the user+client holding it. Surface it
  plainly: *"`<asset>` is exclusively locked by `<user>@<client>`."*
- **`+l` exclusivity is enforced at *open* time - it is not a `p4 lock` flock.** So
  `p4 unlock -f` does **not** clear another user's `+l` exclusive open (it releases
  `p4 lock` locks). The holder releases it by `p4 submit` or `p4 revert`; suggest the
  user ask them.
- **Admin override.** To clear someone else's `+l` open, an admin reverts *their*
  open: `p4 revert -C <their_client> <file>`. For a lock **orphaned** by a dead
  edge/client, use `p4 unlock -x <file>`. Releasing a lock **never destroys their
  content** - their local file stays on disk; what they lose is the exclusive right to
  submit (a teammate can open+submit first, stranding the work as unsubmittable on an
  unmergeable asset). Requires admin rights, explicit confirmation, and the holder
  known unreachable.
- Your own locks: `p4 lock`/`p4 unlock` (no `-f`) manage only your opened files.

Example - reading `p4 -ztag fstat //<depot>/Art/Hero.uasset`:

```
... depotFile //<depot>/Art/Hero.uasset
... otherOpen0 alice@art_ws
... otherLock0 alice@art_ws        <- exclusively locked by alice
... headType binary+l
```

→ Report *"Hero.uasset is exclusively locked by `alice@art_ws`."* Ask alice to submit
or revert. Admin release is `p4 revert -C alice_ws //.../Hero.uasset` - not `unlock -f`
(see the bullets above). Validated on P4D 2026.1: under a real held `+l` open the
indexed `otherOpen0`/`otherLock0`/`otherAction0` fields appear by default, and
`p4 opened -a` shows `... (binary+l) by alice@art_ws *locked*`.

## 8. Streams (merge-down / copy-up)

Modern Helix Core shops often use **streams** instead of classic branches. First
confirm the workspace is stream-based:

```sh
p4 client -o | grep '^Stream:'     # a Stream: line ⇒ stream workspace
p4 streams //<depot>/...           # list streams (mainline/dev/release)
```

Typical hierarchy: `release` ⇦ `main` (mainline) ⇦ `dev`/task streams. Flow of
change:

```sh
# What's pending, and in which direction. Read integFromParentHow/integToParentHow and
# fromResult/toResult ("query" = nothing pending, "cache" = pending):
p4 istat -a //<depot>/<child_stream>

# MERGE DOWN (parent -> child): be on a client on the CHILD stream, then bare `p4 merge`
# (it pulls from the parent). Resolve, then submit.
p4 merge -n                                 # preview
p4 merge                                    # == p4 merge -S //<depot>/<child_stream> -r
p4 resolve                                  # binary assets: pick a side (see §5)
p4 submit -d "Merge down from parent"

# COPY UP (child -> parent): from a client on the PARENT stream:
p4 copy -S //<depot>/<child_stream> -n      # preview
p4 copy -S //<depot>/<child_stream>         # promote finished, already-merged work
p4 submit -d "Copy up to parent"
```

- **Direction is counterintuitive - verified on P4D 2026.1.** The default
  `-S <stream>` direction is *toward the parent* (up = copy). So `p4 merge -S <child>`
  with **no** `-r` errors `needs 'copy' not 'merge' in this direction`; merge-down is
  `p4 merge -S <child> -r` - or just bare `p4 merge` from a client on the child.
- **Merge down before copy up - the server enforces it.** Copy up is blocked with
  `cannot copy over outstanding 'merge' changes` until the child has merged the
  parent's changes down and submitted.
- `p4 copy` is 1:1 (no resolve); `p4 merge` brings changes you resolve. Don't use
  classic `p4 integrate` branch specs on a stream depot.
- Switching a client between streams (`p4 switch <stream>` / `p4 client -s -S <stream>`)
  needs no open files (shelve/revert/submit first).
- **Deleting a stream is two-step**: `p4 stream -d` only *tombstones* it (shows
  `(deleted)` under `p4 streams -a`); `p4 stream --obliterate -y <stream>` purges it -
  and a stream depot can't be deleted until its tombstones are obliterated.

## 9. Engine typemap & P4IGNORE presets

Two studio-hygiene settings that a fresh depot usually lacks. Check first:

```sh
p4 typemap -o        # empty TypeMap: ⇒ nothing forcing binary/lock on assets
```

**Typemap** - force correct filetypes so art/audio are stored as binary and locked
(`+l`) instead of being diffed/merged. **`p4 typemap` requires admin and edits a
server-wide table affecting every depot and team** - treat editing it like a
destructive op: show the current table (`p4 typemap -o`) and your proposed diff, and
get confirmation. Apply non-interactively (never the bare `p4 typemap` editor):

```sh
p4 typemap -o | <insert your TypeMap lines> | p4 typemap -i
```

Recommended lines:

```
    binary+l //....uasset
    binary+l //....umap
    binary+l //....fbx
    binary+l //....psd
    binary   //....png
    binary   //....tga
    binary   //....wav
```

- `+l` = exclusive lock (unmergeable source assets: `.uasset`/`.umap`/`.fbx`/`.psd`).
- Plain `binary` for other art/audio. **Do not use `+w`** for source assets: `+w` is
  *always-writable*, which lets `p4 sync` clobber local edits even under `noclobber`
  and breaks the "read-only ⇒ not yet checked out" assumption the agent relies on.
  Reserve `+w` for engine-*written* build artifacts (`.exe`/`.dll`/`.pdb`), per Epic's
  own recommended typemap.
- Typemap applies to **newly added** files; existing files keep their type until
  re-typed (`p4 edit -t binary+l <file>`).

**P4IGNORE** - a file (path in the `P4IGNORE` env var, commonly `.p4ignore`) listing
patterns reconcile/add must skip. Engine presets:

```
# --- Unreal ---
Binaries/
Intermediate/
Saved/
DerivedDataCache/
.vs/
*.tmp

# --- Unity ---
Library/
Temp/
Logs/
Obj/
*.csproj
*.sln
```

- Test a specific path with `p4 ignores -i <path>` - it reports whether that path
  *would* be ignored (`-v` alone only *lists* the translated rules; `-i` is the actual
  test).
- **Don't blanket-ignore `Binaries/`** at studios that check prebuilt editor binaries
  into the depot so non-programmers never compile (common) - ask first.

---

## Workspace (client) spec notes

- Human workspace `Options`: `noallwrite noclobber nocompress unlocked nomodtime
  normdir` (safe defaults - won't overwrite writable files).
- Automation/replay workspace `Options`: `allwrite clobber ...` so a tool can rewrite
  the tree freely between steps without "can't clobber writable file" errors. Set
  `Host:` empty so the client isn't pinned to one machine/container hostname.
- Create/update a client with the pipe form `p4 client -o | ... | p4 client -i` - it
  composes cleanly with `sed`/`awk` (the `p4 client -i < file` redirect form also
  works).

## Validation status

Validated end-to-end against a live **P4D 2026.1** server: the connection/auth,
observe/analyze, checkout/submit, reconcile, `+l` lock fields (real held lock),
worktree isolation hooks, and the **streams** merge-down/copy-up + `istat` +
tombstone/obliterate flow above.

Still authored-from-docs (validate on your setup before relying on the exact spec):
- Per-engine external merge-tool invocations for `.uasset`/`.umap` resolve.
- Edge/replica/broker routing specifics (`opened -x`, replica write rejection wording).
- SSL `p4 trust` fingerprint flow (test server is non-SSL).
