---
name: p4-observe
description: >
  Read-only Perforce (Helix Core) observability & analysis playbooks - snapshot
  workspace/server state, analyze changelist history and velocity, CI-trigger
  health, exclusive-lock (+l) contention, and large-binary/depot bloat. Use for
  inspecting and reasoning about a p4 system WITHOUT changing it. For operations
  that modify the depot (edit, submit, shelve, revert, reconcile) use the
  `p4-workflows` skill instead.
---

# P4 Observe & Analyze

Read-only playbooks for understanding a Perforce system. **Nothing here mutates the
depot** - every command is safe to run for inspection. Prefer structured output for
anything you'll parse:

- `p4 -ztag -Mj <cmd>` → one JSON object per line with real fields.
- `-Mj` **without** `-ztag` only wraps text as `{"data":...}` - always pair them.
- `p4 -ztag describe` truncates the description to its first line; for the full
  changelist description use plain `p4 describe -s <n>` and read the tab-indented
  body.

Resolve identity from `p4 info` (never `$USER`). `p4 info` works unauthenticated, so
also confirm a live ticket with `p4 login -s` before commands that need one.

---

## 1. Workspace & server snapshot

```sh
p4 -ztag info                 # userName, clientName, clientRoot, serverVersion,
                              # serverUptime, clientCase (case sensitivity)
p4 login -s                   # ticket expiry (or "session has expired")
p4 opened                     # files open in THIS client, by changelist
p4 opened -a //<depot>/...    # AUDIT / no client: depot-wide (plain `opened` errors without a client)
p4 changes -s pending -u <USER> -l -m 50   # this user's pending work (capped; long desc)
p4 changes -s shelved -u <USER>      # shelved WIP
p4 client -o | grep '^Stream:'       # stream-based? (empty ⇒ classic depot)
```

**No workspace? That's an audit, not an error.** When `clientName` is `*unknown*`,
this agent's core read-only job still works - just prefer client-independent queries
(`opened -a`, `changes`, `files`, `sizes`, `fstat`, `streams`, `depots`, `protects -m`)
over client-scoped ones (`opened`, `status`, which error `Client ... unknown`).

Report a concise summary: who/where, ticket state, what's checked out, what's
pending/shelved, and anything risky (assets open for edit, long-open changelists).

## 2. Changelist history & velocity

```sh
# Recent submitted changes as structured JSON (change, user, client, time, status, desc).
# -l keeps FULL descriptions so CI/approval tags at the end aren't truncated.
p4 -ztag -Mj changes -l -s submitted -m 200 //<depot>/...

# Full description of one change (use -s: no per-file diffs)
p4 describe -s <n>

# Diff-bearing describe (unified). The numeric arg to -du is CONTEXT lines and
# ATTACHES to the flag (-du3); there is NO per-file line-cap flag, so bound large
# output with head yourself. (Do not write `-du -dl <n>`: -dl means "ignore line
# endings" and a bare number after it is parsed as another changelist.)
p4 describe -du <n> | head -400
```

Analyses to derive from the JSON stream (parse `time` as a Unix timestamp):

- **Velocity** - submissions per day/week; active vs quiet periods.
- **Contributors** - group by `user`/`client`; who's most active where.
- **CI-trigger health** - count description tags the studio uses (`#ci`, `#build`,
  `#jenkins`, `#approval`, `[ci]`, `#jenkins:<Job>`). A drop-off in `#ci`/`#build`
  tags on `change-commit`-triggered paths can indicate the webhook/Jenkins bridge
  is down. Cross-check with §5.
- **Hot paths** - bucket by top-level depot dir (`path` field) to see where change
  concentrates (art vs code vs audio).

## 3. Exclusive-lock (+l) contention

```sh
p4 opened -a -m 200 //<path>/...       # everything open across ALL clients/users (capped)
p4 opened -x //<path>/...              # EDGE servers only: globally-tracked +l opens
# then fstat just the opened paths - otherOpen/otherLock show by DEFAULT (no -O flag,
# which only adds size/digest cost); never fstat a whole subtree:
p4 -ztag fstat //<path>/<specific_asset>
```

- Files with an `otherLock` field are exclusively locked by another user - report
  **who** (`otherOpen`/`otherLock` name `user@client`) and on **what asset**.
- Surface contention hotspots: assets that are frequently locked, or locked for a
  long time, block artists. Name the holder so the user can go ask them.
- This is read-only reconnaissance; releasing a lock is an operation → `p4-workflows`
  §7.

## 4. Large-binary / depot bloat

```sh
p4 sizes -s -h //<depot>/...           # summary total (INCLUDES lazy/branched copies)
p4 sizes -z //<depot>/...              # real archive bytes: EXCLUDES lazy copies
                                       # (-z and -s are mutually exclusive)
p4 sizes -aH -m 1000 //<depot>/....fbx # per-file (head rev), human units, CAPPED, by type
# Cleanest "biggest files" (no awk) via the undoc -F flag (see the p4-undoc skill):
p4 -F '%fileSize% %depotFile%' sizes -m 5000 //<depot>/....fbx | sort -n | tail -20
# Self-throttle a wide exploratory scan so a mistyped wildcard fails fast:
p4 -zmaxScanRows=500000 files //<depot>/...
```

- Break total size down by asset type (`.png`/`.fbx`/`.wav`/`.uasset`) to see what's
  driving depot growth.
- Flag files that probably shouldn't be in the depot at all (build output, caches) -
  cross-reference the P4IGNORE presets in `p4-workflows` §9.
- Remember every large binary is expensive to sync/branch - bloat is a real cost,
  not just disk.

## 5. Trigger / CI configuration health

```sh
p4 triggers -o                         # the trigger table (super-only)
p4 monitor show                        # running commands / load (super; monitor must be enabled)
p4 configure show                      # server config (super-only)
```

- All three above need **`super`**. On a least-privilege account they error - degrade
  gracefully (e.g. do CI-tag analysis from §2 without the trigger table); don't retry.
- Classic Perforce has **no native webhooks** - CI/build integration is `change-commit`
  triggers invoking a script (e.g. `//depot/... "webhook.sh %changelist%"`). Trigger
  fields are **whitespace-separated with the command quoted**; the usual
  "Wrong number of words" error is an *unquoted* command with spaces, not a
  tabs-vs-spaces issue. (Helix Core 2019.2+ also has **Extensions** as a richer
  alternative to shell triggers.)
- A healthy trigger fires per submit and **exits 0** even on failure, so a down
  webhook never blocks developers. If §2 shows CI tags but builds aren't happening,
  the trigger is likely firing while the downstream endpoint is failing (which by
  design is silent to submitters) - check the endpoint, not just the trigger table.

## 6. Server & connection health

```sh
p4 info                                # liveness probe (works unauthenticated)
p4 -ztag info | grep -i serverUptime   # how long the server's been up
p4 login -s                            # ticket state for the current user
```

- A passing `p4 info` with a failing `p4 login -s` = server up, ticket expired
  (a very common state) - the fix is `p4 login`, not a connection change.
- For SSL servers, a first-contact `authenticity ... can't be established` means the
  fingerprint isn't trusted yet (see the `perforce` agent's connection rules).

---

## Example - a filled analysis briefing

From `p4 -ztag -Mj changes -l -s submitted -m 200 //<depot>/...` + `p4 sizes -s -h`:

> **Depot //<depot> - last 200 changes**
> - Velocity: ~14 submits/day, steady; quietest on weekends.
> - Contributors: one automation account dominates; 3 human users.
> - CI health: 21 `#ci` / 31 `#approval` tags on `change-commit`-covered paths -
>   consistent with the configured triggers; no drop-off.
> - Size: 927 files, ~695 MB. Biggest types: `.png` (669), `.fbx` (223), `.wav` (127).
>   No obvious build-output/cache leakage.
> - Locks: nothing exclusively locked right now (`p4 opened -a` empty).

(Numbers illustrative - shape taken from a live P4D 2026.1 test depot.)

## Caveats

- **`-Mj`/`-ztag -Mj` need a reasonably modern client** (`-Mj` ~2021.2+). On an older
  `p4`, fall back to `p4 -ztag -G <cmd>` (Python marshal) or parse plain text.
- **`p4 triggers -o`, `p4 configure show`, `p4 monitor show` need `super`/admin.**
  Least-privilege accounts get permission errors - degrade gracefully, don't retry.
  Note `p4 monitor show` returning `Monitor not currently enabled` is a *distinct*
  failure (the feature is off server-side), not a permission denial - same "skip it"
  outcome, but don't report it as an access problem.
- **Wide `p4 opened -a //...`, `fstat`, and `p4 sizes -a` are a server-LOAD concern**
  (not permission): they can trip `MaxScanRows`/`MaxResults` and page the admin.
  Always scope to a subtree and cap with `-m`.
- **`p4 sizes -s` counts lazy copies** - a branched tree inflates the total without
  using archive space. Use `p4 sizes -z` for real stored bytes; plain `sizes` reports
  head-revision sizes, not disk-on-client.

## Notes

- Keep everything here read-only. If analysis reveals work to do (release a lock,
  add a typemap, reconcile drift), hand off to `p4-workflows` and re-confirm with the
  user before mutating.
- Large history scans: cap with `-m <N>` and scope to a subtree; the full changelist
  history on a busy depot can be enormous.
