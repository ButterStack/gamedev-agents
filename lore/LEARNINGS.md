# Lore Agent - Integration Learnings (running log)

Dated log of what running Lore VCS integrations *for real* teaches us - the stuff
that isn't obvious from the docs. Companion to [`NOTES.md`](./NOTES.md) (design
rationale) and the real-server testing-report template in
[`../CONTRIBUTING.md`](../CONTRIBUTING.md).

`[skill]` = the agent's own diagnosis was wrong or thin. `[integration]` = how a
real Lore integration actually behaves. Newest first, dated. No secrets -
reference credential *locations*, never paste them.

---

## 2026-10-02 - Workspace and firewall notes `[integration]`

Learned porting scripts into a Lore repo and standing up a Lore server on a cloud host.

- **`--scan` is also needed for files copied in from outside, not just drifted edits.**
  `lore status`/`lore stage` only see tracked dirty flags; run `lore status --scan
  <paths>` (or `lore stage --scan`) first.
- **A TCP test from an allowlisted address makes a firewalled port look public.** Read
  the firewall rules, not reachability from your own machine.
- **The GitHub mirror can lag the source of truth.** Base pipeline edits on the Lore
  revision, not the mirror's copy.

## 2026-09-24 - git-to-Lore mirror and push relay on loreserver 0.9.0 `[integration]`

Learned mirroring a 107-commit git repository into Lore across two branches, and
relaying pushes from a live `loreserver 0.9.0` into our own systems via the
notification stream.

- **Revision numbers are per branch, not global.** A second branch's replay started
  renumbering from its parent's revision, so a consumer keying on the bare number
  alone conflated two branches that happened to share a number, and a relay that
  kept one global "last seen" cursor silently treated an entire branch's revisions
  as already-seen. Namespace non-default branches, keep relay state per branch, and
  dedupe any history two branches inherited by content hash rather than by number.
- **A push notification's branch field is a 32-hex id, not a name.** Resolve it via
  `lore branch list` (returns id, name, and location) and skip - don't mark seen -
  any revision whose branch doesn't resolve yet.
- **`lore sync <hash>` moves the working copy, not the branch's local pointer.**
  `lore branch reset --branch <b> <hash>` is what moves the pointer that `revision
  history --branch` actually reads.
- **There is no import command, and `lore commit` has no author or date override.**
  The mirror recipe that worked: one revision per git commit, the tree extracted
  fresh via `git archive | tar -x`, staged with `lore stage --scan .` (a bare `lore
  stage .` staged nothing), and the git provenance carried as message trailers
  (`Git-Commit`, `Git-Author`, `Git-Date`, `Git-Parents`) for downstream
  SHA-to-revision lookups.
- **A git commit with no tree change produces no Lore revision at all.** 107 git
  commits produced only 105 revisions (two empty merge commits), so a
  SHA-to-revision lookup needs a fallback path rather than assuming every SHA maps
  to one.

## 2026-07-17 - live validation against loreserver 0.8.5 `[integration]` `[skill]`

Learned standing up a real `loreserver 0.8.5` and driving two clones through the
full stage → commit → push → sync → branch loop.

- **Staging pins the path, not the content - fragments are produced at commit
  time.** Staged a file at "VERSION-ONE", edited it to "VERSION-TWO" *before*
  committing, and the commit captured VERSION-TWO. This is the load-bearing
  mental-model claim: there's no "staged an old version by mistake" trap the way
  there would be in Git, because content is read fresh at commit time - don't
  apply `git add` muscle memory here.
- **`lore status` does no filesystem walk by default** - it reads tracked dirty
  flags only; `--scan` walks the working tree and persists them. Suspected drift
  from an out-of-band edit needs `--scan`.
- **A commit is local; only `lore push` publishes.** A divergent push is rejected
  with `Branch has diverged, sync to merge remote changes`; recovery is `lore
  sync` then `lore push` - never `--force`. There's no documented
  history-rewriting force-push, so treat a divergent push as "go merge," not "go
  override."
- **`lore sync` = fetch+merge, with no separate fetch step.**
- **No true branch delete** - `lore branch archive <b>` removes a branch from
  `lore branch list`, but `--archived` still shows it. Treat "delete" as archive,
  and don't tell a user a branch is gone for good.
- **The installed `0.8.5` CLI has a global `--no-gc`, not the `--gc` an earlier
  docs snapshot listed** (GC runs automatically in the background; `lore
  repository gc` forces a full pass) - a reminder that a command list built from
  docs alone can drift from the binary actually installed.
- **Terminology gotchas held up against the live server:** no `lore init` (use
  `lore repository create`), no `lore log` (use `lore history`), no blame, no
  rebase, no squash, and locks are advisory - `lore lock acquire` does not block
  another user's push.

### Push refused when the remote is ahead (2026-09-25)

`lore push` fails with a branch error once the remote has moved past your local
pointer, even if your working copy already has the files. Recovery: `lore branch
reset --branch main <remote head>`, `lore sync <remote head>`, re-apply the
change, `lore stage --scan .`, `lore commit`, `lore push`. There is no rebase -
the revision made on the stale pointer is simply abandoned.

### Revision numbers are the wrong key for a build (2026-09-25)

A CI build tied to a Lore revision should key on the 64-hex signature, not the
revision number - the number is per branch and repeats across branches, the
signature is global. A "commit" validator built for 7-40 hex characters needs
widening to 64.
