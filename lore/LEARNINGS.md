# Lore Agent - Integration Learnings (running log)

Dated log of what running Lore VCS integrations *for real* teaches us - the stuff
that isn't obvious from the docs. Companion to [`NOTES.md`](./NOTES.md) (design
rationale) and the real-server testing-report template in
[`../CONTRIBUTING.md`](../CONTRIBUTING.md).

`[skill]` = the agent's own diagnosis was wrong or thin. `[integration]` = how a
real Lore integration actually behaves. Newest first, dated. No secrets -
reference credential *locations*, never paste them.

---

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
