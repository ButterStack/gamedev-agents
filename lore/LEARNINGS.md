# Lore Agent - Integration Learnings (running log)

Dated log of what running Lore VCS integrations *for real* teaches us - staging and
commit semantics, sync/push behavior, branch lifecycle, CLI surface drift - the stuff
that isn't obvious from the docs. Companion to [`NOTES.md`](./NOTES.md) (design
rationale; its "Validation status" section holds the raw findings) and the real-server
testing-report template in [`../CONTRIBUTING.md`](../CONTRIBUTING.md).

Two kinds of entry - tag each one:

- **`[skill]`** - where the agent's own diagnosis or a playbook was wrong or thin. These
  graduate into the skills (that's the feedback loop).
- **`[integration]`** - how a real Lore integration (staging, commit, sync, push, branch
  lifecycle) actually behaves. Useful to anyone wiring `lore` into a pipeline even if it
  never touches a skill.

Conventions: newest first, dated. No secrets - reference token/credential *locations*,
never paste them. Prefer relative links so entries survive a repo rename. This is where
the team logs what each real integration teaches us; sibling plugins keep their own (e.g.
[`../perforce/LEARNINGS.md`](../perforce/LEARNINGS.md) and
[`../unreal/LEARNINGS.md`](../unreal/LEARNINGS.md)).

---

## 2026-07-17 - live validation against loreserver 0.8.5: staging, local-then-push, sync, branch lifecycle `[integration]`

Learned standing up a real `loreserver 0.8.5` (local, single-node) and driving two
clones through the full stage -> commit -> push -> sync -> branch loop.

- **Staging pins the path, not the content - fragments are produced at commit time.**
  Staged a file at "VERSION-ONE", edited it to "VERSION-TWO" *before* committing, and
  the commit captured VERSION-TWO (commit reported `31.00`/`12.00` bytes; post-commit
  `lore diff` was empty). This is the load-bearing mental-model claim and it holds. Do
  not apply `git add` muscle memory here - there's no "staged an old version by mistake"
  trap the way there would be in Git, because the content is read fresh at commit time.

- **`lore status` does no filesystem walk by default.** It reads tracked dirty flags
  only; `--scan` walks the working tree, reconciles it, and persists the dirty flags.
  Suspected drift after an out-of-band edit (something touched the working tree outside
  `lore`) needs `--scan` - plain `lore status` will not surface it.

- **A commit is local; only `lore push` publishes.** A divergent push is rejected with
  the exact error `Branch has diverged, sync to merge remote changes`. Recovery is
  `lore sync` (which merges, producing a merge revision) then `lore push` - never
  `--force`. There is no documented history-rewriting force-push, so treat a divergent
  push as "go merge," not "go override."

- **`lore sync` = fetch+merge (git pull) - there is no separate fetch step.** One clone
  went from "behind remote" to current in a single `lore sync` call.

- **No true branch delete.** `lore branch archive <b>` removes a branch from `lore
  branch list`; `lore branch list --archived` still shows it. Treat "delete a branch" as
  archive, not as a destructive, irreversible op, and don't tell a user a branch is gone
  for good.

Verified live against a real `loreserver 0.8.5` (local, single-node, two clones
exercising the full stage/commit/push/sync/branch loop end-to-end).

## 2026-07-17 - CLI surface drift and terminology gotchas, confirmed against the live binary `[skill]`

Learned re-deriving the command surface from the installed CLI instead of trusting a
docs snapshot, because Lore is pre-1.0 and still moving.

- **The installed `0.8.5` CLI has a global `--no-gc`, not `--gc`.** GC runs
  automatically in the background on writes; `lore repository gc` forces a full pass.
  An earlier docs snapshot listed a global `--gc` instead. A command list built from
  docs alone can drift from the binary actually installed - re-derive commands from
  `lore <cmd> --help` on the installed binary whenever a flag looks off, rather than
  trusting a cached doc.

- **Terminology gotchas held up against the live server:** no `lore init` (use `lore
  repository create`), no `lore log` (use `lore history`), no blame, no rebase, no
  squash, and locks are advisory - `lore lock acquire` does **not** block another
  user's push. These were docs-derived assumptions going in; good to have them
  confirmed load-bearing against a real server rather than the docs alone.
