# Design notes

## Why a domain-specific Perforce agent

Perforce/Helix Core is the de facto standard VCS in game development because it
handles large binary assets and exclusive-checkout locking in ways Git doesn't. A
general-purpose coding agent tends to either avoid `p4` entirely or reach for
Git-shaped mental models (branches-as-default, cheap reverts, everything-is-mergeable)
that are actively wrong for a Perforce depot full of multi-GB art and audio - and,
crucially, it doesn't know that Perforce files are **read-only until checked out**,
so its edits either fail or silently clobber the read-only bit and desync the depot.

This agent is **read-first**: its center of gravity is observing and analyzing a
Perforce system (workspace/server state, changelist history, lock contention, CI
trigger health, depot bloat), with safe, gated write operations as the supporting
act. It models depot → client → changelist and treats `revert`/`obliterate`/force
ops as the dangerous operations they are.

## Positioning

A Claude Code **plugin** - first in ButterStack's series of gamedev agents. It ships
as a plugin (`.claude-plugin/plugin.json` + root-level `agents/`, `skills/`,
`commands/`, `hooks/`, `scripts/`).

## Key decisions

- **No MCP dependency in v1 - CLI-driven.** A community Perforce MCP server we
  evaluated exposed only a fraction of its advertised tools in practice, so v1 drives
  `p4` via Bash instead. A structured MCP backend may be revisited post-v1 as an
  *optional, preferred-when-available* read path, never a requirement.
- **`CLAUDE_CODE_PERFORCE_MODE=1` is set/recommended.** This (currently undocumented,
  but verified present in the CLI) makes Claude Code inject a note that Perforce files
  are read-only until `p4 edit`. It only *prompts* - it does not auto-checkout - so
  the agent still owns the actual `p4 edit`/reconcile discipline. Because plugins may
  only ship `agent`/`subagentStatusLine` in `settings.json` (not `env`/`permissions`),
  this and the read-only permission allowlist are **documented in the README** for
  users to add to their own settings, not auto-shipped.
- **Portability over POSIX-isms.** Identity (user/client/root/case/unicode) is derived
  from `p4 info`, never `$USER` - gamedev is Windows-dominant and shells are shared.

## What informed the connection/auth playbooks

These playbooks weren't written from the docs alone - they're informed by a real,
production Perforce integration ButterStack runs and operates: a Ruby p4 client that
authenticates, syncs, and imports changelist history for a live depot. That's where
the connection/auth robustness rules come from, which is what a generic agent gets
most wrong:

- `p4 info`-derived identity; `p4 login -s` ticket-state parsing; SSL `p4 trust`
  handling; `P4CHARSET=utf8`; `printf` (not `echo`) for passwords with `%`/`!`.
- An error-string → cause classifier and a network-vs-user error split (for
  retry/backoff decisions).
- The reconcile-driven "golden write cycle" (`revert → reconcile → opened [skip if
  empty] → submit → verify warnings/errors`) used by a git-to-Perforce replay path.

That production integration has **no** typemap, `P4IGNORE`, streams, or `+l` usage
anywhere (it's a read-only importer), so those playbooks were **authored from domain
knowledge**, not mined from production code - and were flagged as needing validation
against a real streams/lock server (see below).

## Live-depot validation learnings

Validated against a live Helix Core **P4D 2026.1** (a dockerized `p4d`, 3 classic
depots, ~8,700 changelists, real `.fbx`/`.png`/`.wav` assets). Corrections found by
running the commands, not just reading docs:

- **`-Mj` alone is not structured** - it wraps each text line as
  `{"data":...,"level":0}`. Use `p4 -ztag -Mj <cmd>` for real fields (`change`,
  `user`, `time`, `headType`, ...).
- **`p4 describe -du -dl <n>` is wrong** (a latent bug we found copied into more
  than one internal client): `-dl` means "ignore line endings", so the number gets
  parsed as another changelist. Correct: `p4 describe -du <n>` (the optional number
  *attaches* as context lines: `-du3`) - there's no per-file line cap; bound output
  with `head`.
- **`p4 -ztag describe` truncates the description to its first line** - use plain
  `p4 describe -s <n>` and read the tab-indented body.
- `p4 info` succeeds **unauthenticated**; most else needs a ticket - always confirm
  with `p4 login -s` (a "session has expired" is the common real-world state).
- **Streams validated** on a throwaway stream depot: the default `-S <stream>`
  direction is *toward the parent* (up = copy), so merge-**down** is bare `p4 merge`
  on the child and copy-**up** is `p4 copy -S <child>` from the parent, with the
  server enforcing merge-down-before-copy-up. Deleting a stream only *tombstones*
  it; `p4 stream --obliterate -y` is the real purge.
- **Held `+l` lock validated**: `opened -a` shows the lock holder directly, and
  `fstat` exposes the same state as structured fields.
- Worktree isolation (a per-worktree `p4 client` derived from the current one) and
  a catalogue of undocumented flags (`p4 help undoc`) were also live-verified; see
  the `p4-undoc` skill and `guard-p4` hook for what that produced.

Still authored-from-docs (validate on your setup, and open an issue with what you
find): per-engine external merge-tool invocations for `.uasset`/`.umap` resolve,
and edge/replica/broker routing + SSL `p4 trust` flow (our test server is single,
non-SSL).

## Source talk (design philosophy)

The repo's structure was shaped by a "Standard Agents" talk on domain-specific agents
(https://youtu.be/spNAUEgq_A8): (1) domain-specific agents get high token efficiency
because a sub-agent's context is just its prompt + tools + one request → keep
`perforce.md` tight and push step sequences into on-demand skills; (2) agents are
portable, shareable units → package as a distributable plugin; (3) prefer strict,
explicit capability limits over blanket permission bypass → the non-negotiable safety
rules and confirmation gates; (4) narrow scope makes cheaper models viable → the agent
runs on `sonnet`. No Perforce-specific tips came from the talk; the command playbooks
are from Perforce/gamedev domain knowledge plus the live-depot validation above.
