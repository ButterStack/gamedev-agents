# Design notes

## Why a domain-specific Lore agent

[Lore](https://github.com/EpicGames/lore) is Epic Games' next-generation, open-source
version control system (formerly **Unreal Revision Control**, already the built-in VCS
for Unreal Editor for Fortnite). It targets the same problem Perforce does - code plus
large binary assets at studio scale - but with a very different model: content-
addressed (BLAKE3 Merkle trees), binary-first (fragment-level dedup), offline-capable
against a local store, with a central server of record.

A general-purpose coding agent handles Lore badly for the same reason it handles
Perforce badly, plus a twist: it reaches for **Git muscle memory** that is subtly
wrong here. In Lore, **staging pins the path, not the content** (fragments are made at
commit, so there's no `git add`-then-edit-again trap), a **commit is local until
`lore push`**, `lore sync` is a **fetch+merge** (no separate fetch), **locks are
advisory** (they don't block another user's push), and there is **no `blame`, no
`rebase`, no `squash`, and no true branch delete**. This agent encodes that model so
it doesn't guess.

This agent is **read-first**: its center of gravity is observing and analyzing a Lore
repo (working-tree/branch/sync state, revision history, diffs, the dependency graph),
with safe, gated write operations (stage → commit → push, branch/merge, sync) as the
supporting act. It treats `obliterate`, `reset`/`--purge`, `sync --reset`,
`branch reset`, and amend-after-push as the dangerous operations they are.

## Positioning

A Claude Code **plugin** - a sibling to `perforce`/`unreal` in the
ButterStack gamedev-agents series. It ships as a plugin (`.claude-plugin/plugin.json`
+ `agents/`, `skills/`, `commands/`, `hooks/`, `scripts/`) and drives the `lore` CLI
via Bash, exactly as the `perforce` agent drives `p4`.

## Provenance - this plugin was rebuilt from a wrong first draft

The original ask was for "a Lore agent, similar to perforce and unreal - see the
`EpicGames/lore` project and repo." The **first two automated attempts had no
outbound web access**, so they never reached `github.com/EpicGames/lore` and guessed
from the word "lore" alone - producing a **narrative canon / story-bible** agent
(characters, factions, retcons, timeline continuity). That was wrong: `EpicGames/lore`
is a **version control system**, and the original ask's own "similar to **perforce**"
is the tell.

This version is the corrected rebuild, authored **with** the real project in hand: the
command surface, terminology, and safety classification are derived from Epic's
official docs (repo README, [developer docs](https://epicgames.github.io/lore/), the
CLI command/config references, quickstart, glossary, and FAQ), pinned to CLI `0.8.x`.
The narrative agent/skills/commands were scrapped, not adapted.

## Key decisions

- **CLI-driven, no MCP/API dependency.** Like `perforce` (drives `p4`) and `unreal`
  (drives `UBT`/`RunUAT`), v1 drives the `lore` CLI directly via `Bash`/`Read`/`Grep`/
  `Glob`. Lore ships no separate agent API; the CLI is the surface.
- **The safety boundary maps to Perforce's, not Git's.** `lore file obliterate` is the
  `p4 obliterate` analog (irreversible, server-side, all-users) → gated by name **and**
  a hook backstop. `lore reset`/`--purge` and `sync --reset`/`switch --reset` are the
  `git reset --hard`/`p4 revert` analog (discard local work) → agent-gated with
  show-what's-lost-first. `lore push` is the publish gate. `lore branch reset` and
  `revision amend`-after-push are the history-hazard gates.
- **The `guard-lore` hook stays minimal and hard.** It blocks only the two
  irreversible, server-destructive commands - `lore file obliterate` and
  `lore repository delete` - regardless of how permissions are set, mirroring
  `guard-p4.sh`'s "catastrophic-only" boundary. Softer destructive ops (reset,
  `--reset`, `branch reset`, amend, `layer remove --purge`, push, `--force`) are gated
  by the agent's confirmation rules, because a shell hook can't tell a safe local
  `reset <one-file>` from a catastrophic one - only that `obliterate`/`repository
  delete` are never in scope for this agent. The hook handles Lore's `noun verb`
  command shape (skips global flags + their values; emits a pair per `lore` token so
  `cd x && lore file obliterate` is still caught).
- **Executable guard + direct-exec hook.** `guard-lore.sh` is committed `0755` and
  `hooks.json` invokes it directly (`"${CLAUDE_PLUGIN_ROOT}"/scripts/guard-lore.sh`),
  matching `guard-p4.sh`/`guard-jenkins.sh` - no `bash <path>` wrapper.
- **Pre-1.0 humility baked in.** Lore is `0.x` and its command surface still evolves,
  so the agent and skills tell the model to re-derive commands from `lore <cmd> --help`
  on the installed binary when a flag looks off, and to **not** assume a `--json` flag
  (the docs hint at machine-readable output but don't document the flag).
- **Worktree isolation = shared-store clone, not a "client" concept.** Perforce's
  `WorktreeCreate`/`WorktreeRemove` hooks provision a dedicated `p4 client`; Lore has
  no equivalent named-workspace object, so the analog is a full `lore clone <url>
  <worktree_path> --use-shared-store`, addressed at the SAME remote repo the source
  checkout points at. `--use-shared-store` alone (no explicit `--shared-store-path`)
  self-provisions Lore's default per-remote shared store on first use and silently
  reuses it after, deliberately skipping a separate `lore shared-store create` step,
  since that subcommand errors if the path already exists and would add an
  idempotency case for no benefit. The repo name isn't exposed by any
  `repository config get` key, so `worktree-create.sh` parses it off the first line of
  `lore repository info` (`"<name> (<id>)"`) and degrades to a plain directory if that
  parse looks wrong. On `WorktreeRemove`, `lore repository instance prune` cannot
  deregister a worktree's OWN entry while its `.lore` is still a valid `--repository`
  target, and only recognizes a sibling entry as stale once that sibling's directory
  is fully gone (removing just `.lore` is not enough, confirmed empirically). So the
  hook prunes opportunistically (sweeping already-stale siblings) then removes only
  its own `.lore`; full deregistration of THIS worktree happens on a later prune once
  the harness deletes the directory, the same best-effort, may-lag-a-crash story as
  Perforce's `claude_wt_*` client leak.

## Command-surface facts that drive the design

Grounded in Epic's docs (CLI `0.8.x`). The ones most likely to trip a Git-shaped agent:

- **No `lore init`** - `lore repository create <url>` initializes a repo.
- **No `lore log`** - `lore history` (repo) / `lore file history` (per file). No
  `blame`/annotate.
- **No `rebase`, no `squash`** - glossary concepts with no CLI command; only
  `branch merge`, `revision cherry-pick`, `revision revert`.
- **No true branch delete** - only `lore branch archive` (history retained via the
  branch's stable ID; `--archived` lists them; no documented CLI un-archive).
- **`lore commit` is local; `lore push` publishes** (append-only, rejected on
  conflict). "Submit" = commit then push. No documented history-rewriting force-push.
- **`lore sync` = fetch+merge** (git pull); produces a merge revision on divergence.
- **`lore status` does no FS walk by default** (`--scan` walks + persists dirty flags;
  `--reset` drops the staged anchor).
- **Commit identity is required** or Lore refuses to commit; the demo server records no
  author unless `--identity`/config sets one.
- **Locks are advisory** - `lore lock acquire` doesn't block another user's push.
- **Destructive set** the agent gates: `file obliterate`, `repository delete`,
  `reset`/`file reset` (`--purge` deletes untracked), `sync --reset`,
  `branch switch --reset`, `branch reset <rev>`, `revision amend` (after push),
  `layer remove --purge`, global `-f/--force`, `branch unprotect`.

## Validation status

Live-validated end-to-end against a real `loreserver` 0.8.5 (local, single-node,
auth off, self-signed cert auto-generated by default). Two clones against one
server exercised the full stage → commit → push → sync → branch loop and
corrected/confirmed the docs against the running binary - see
[`LEARNINGS.md`](./LEARNINGS.md) for the specific findings.

Beyond the VCS semantics themselves, two safety mechanisms were live-exercised
rather than just hand-traced:

- **`guard-lore.sh` against real PreToolUse JSON** (not a sandboxed trace): every
  `file obliterate` / `repository delete` form blocks, including global-flag
  prefixes and chained shell commands (`cd x && lore file obliterate`), while
  read/observe commands and false-positive bait (a commit message that merely
  *mentions* "obliterate", `cat obliterate.txt`) all pass through cleanly.
- **The worktree-isolation hooks, end-to-end against the same server**: cloning a
  fresh worktree correctly derives the shared-store clone URL and produces an
  independently-staged, independently-committed working tree; removing one
  cleans up its local metadata while leaving files untouched, and a later prune
  from a second worktree correctly sweeps the first one's now-fully-deleted
  directory out of the shared store's registry. Both scripts degrade cleanly to
  a plain directory when `lore` is unavailable or the directory isn't a Lore
  repo.

## Not done / out of scope for v1

- Validated against a **single-node local server** (one `loreserver`, two clones). Not
  yet exercised against a multi-node/replicated deployment, remote caches, or the
  dependency-selective clone/sync (`--root-file`/`--dependency-*`) and links/layers
  playbooks - those remain docs-derived.
- Worktree-isolation hooks now ship (`WorktreeCreate`/`WorktreeRemove` in
  `hooks/hooks.json`, `scripts/worktree-create.sh` / `worktree-remove.sh`), feature
  parity with the `perforce` plugin's `p4 client` isolation. See "Key decisions" above
  for the shared-store-clone approach and "Validation status" above for what was
  live-exercised.
- No real-server auth flow exercised (`lore login` token types, `ucs-auth://`) - the
  demo server is unauthenticated and Epic lists OAuth integration as roadmap, so those
  flows may change.
- No binding to Lore's server config / `loreserver` deployment - server administration
  is intentionally out of scope for this agent.
