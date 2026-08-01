# Lore Agent (Epic Games VCS)

**A Claude Code plugin to observe, analyze, and safely operate your Epic Games
[Lore](https://github.com/EpicGames/lore) version control system - built for game
development.**

> Part of the [ButterStack gamedev agents](../README.md) series, alongside
> [`perforce`](../perforce) and [`unreal`](../unreal).

[Lore](https://epicgames.github.io/lore/) is Epic Games' next-generation,
open-source version control system - formerly **Unreal Revision Control**, and
already the built-in VCS for Unreal Editor for Fortnite. Like Perforce, it's built
for repositories that mix source code with large binary assets; unlike Perforce it
is **content-addressed** (BLAKE3 Merkle trees), **binary-first** (files split into
deduplicated *fragments*), open source (MIT), and runs everyday operations
**offline against a local store** with a central server it syncs to. This is a
domain-specific [Claude Code](https://claude.com/claude-code) agent that understands
Lore's mental model instead of guessing from Git muscle memory.

> **This is version control, not narrative "story lore."** The agent drives the
> `lore` CLI (commit / push / sync / branch / merge / obliterate) - it is not a
> story-bible or worldbuilding tool.

It is **read-first**: its job is to *observe and analyze* your Lore repo - working
tree, branch and sync state, revision history and velocity, diffs, the file
dependency graph - with safe, gated write operations (the stage → commit → push
cycle, branch/merge, sync) as the supporting act. Destructive operations
(`obliterate`, `reset`/`--purge`, `sync --reset`, `branch reset`, amend-after-push)
are treated with the caution they deserve around irreplaceable art/audio/build
assets and shared history.

## Who this is for

Game studios and solo devs adopting Epic's Lore VCS who want an AI assistant that
models Lore correctly - including the things generic (Git-shaped) agents get wrong:
**staging pins the path, not the content** (fragments are made at commit time), a
**commit is local until you `lore push`**, `lore sync` is a **fetch+merge**, and
**locks are advisory** (they don't block another user's push).

## What's in the box

```
agents/lore.md                    the agent (mental model, connection/auth, safety rules)
skills/lore-observe/SKILL.md      read-only observability & analysis playbooks
skills/lore-workflows/SKILL.md    operational playbooks (stage/commit/push, branch/merge, sync, safe undo, gated obliterate)
commands/lore-status.md           /lore-status - branch, sync state, staged/dirty files, recent revisions
commands/lore-log.md              /lore-log    - revision history, velocity, contributors, hot paths
commands/lore-diff.md             /lore-diff   - preview working-tree / revision / branch diffs
commands/lore-sync.md             /lore-sync   - guided, safe fetch+merge from the remote
hooks/ + scripts/                 guard-lore (hard-blocks `file obliterate` / `repository delete`) + WorktreeCreate/Remove shared-store-clone isolation
```

## Install

This repo is a self-contained Claude Code plugin marketplace. In Claude Code:

```
/plugin marketplace add ButterStack/gamedev-agents
/plugin install lore@gamedev-agents
```

The agent, skills, and slash commands are auto-discovered on install.

## Setup

You need the `lore` CLI installed and, for a real remote, authenticated so
`lore status` succeeds in your repo. Install the CLI (macOS ARM64 / Linux):

```
curl -fsSL https://raw.githubusercontent.com/EpicGames/lore/main/scripts/install.sh | bash
```

To try it end-to-end with no server or credentials, Lore ships a **local demo mode**
(`install.sh | bash -s -- --demo`) that runs an unauthenticated local server - see
Epic's [quickstart](https://epicgames.github.io/lore/tutorials/quickstart/). Set a
commit identity (`lore ... --identity you@example.com`, or `identity` in
`.lore/config.toml`) or Lore will refuse to commit.

**The real safety boundary is your Lore account and server permissions**, not Claude
Code's. As a backstop, this plugin ships a `guard-lore` hook that hard-blocks
`lore file obliterate` (irreversible fragment destruction) and `lore repository
delete` regardless of how your permissions are set.

Optionally reduce prompts for read-only inspection by allowlisting the safe commands
in your **own** `~/.claude/settings.json` or project `.claude/settings.json` (plugins
can't ship `permissions` for you). A starter list:

```json
{
  "permissions": {
    "allow": [
      "Bash(lore --version:*)", "Bash(lore status:*)",
      "Bash(lore history:*)", "Bash(lore diff:*)",
      "Bash(lore branch list:*)", "Bash(lore branch info:*)", "Bash(lore branch diff:*)",
      "Bash(lore revision info:*)", "Bash(lore file history:*)", "Bash(lore file info:*)",
      "Bash(lore file dependency list:*)", "Bash(lore repository info:*)",
      "Bash(lore lock status:*)", "Bash(lore auth info:*)"
    ]
  }
}
```

> ⚠️ **Do not add `Bash(lore:*)`.** That allowlists `lore file obliterate`,
> `lore repository delete`, `lore reset --purge`, `lore push`, and every other write -
> defeating the point. Prefix matching can't cleanly separate read from write across
> Lore's global flags, which is why the Lore account (above) and the `guard-lore` hook
> are the real guardrails. Anything not allowlisted simply prompts; write/destructive
> commands are proposed and gated by the agent, not run silently.

## Quickstart

Ask the `lore` agent, or use the slash commands:

- **"What's the state of my Lore repo?"** → `/lore-status` (branch, sync vs. remote,
  staged/dirty files, recent revisions, unset identity, locks by others)
- **"What's landed recently?"** → `/lore-log` (revision history, velocity,
  contributors, hot paths)
- **"What have I changed?"** → `/lore-diff` (working-tree, revision, or branch diff)
- **"Get me current with the server."** → `/lore-sync` (guided, safe fetch+merge)
- **"Commit and push my changes / merge my branch / undo my local edits."** → the
  agent walks it via the `lore-workflows` skill - showing the staged set and diff
  before a commit, the revisions before a push, and what would be lost before any
  `reset`.

The agent warns before anything destructive and prefers safer alternatives (unstage,
commit-to-scratch-branch, dry-run) when there's ambiguity.

## Safety posture

Opinionated about Lore's sharp edges: it never runs `lore file obliterate` without
explicit, by-name confirmation; shows what would be lost before any `reset`/`--purge`
or `sync --reset`; shows the revisions before a `push`; won't `amend` an
already-pushed revision; treats large binaries and shared-history rewrites as
expensive; and never adds `--force` to push past a rejection without spelling out the
consequence. See `agents/lore.md` for the full list.

## Parallel work isolation

For non-git VCS, Claude Code delegates worktree isolation to hooks. This plugin ships
`WorktreeCreate`/`WorktreeRemove` hooks that provision an isolated Lore checkout for
each worktree: `lore clone` the same remote repo the current directory is checked out
from, using Lore's shared store (`--use-shared-store`) so fragment payloads dedup
across worktrees on the machine instead of being fetched and stored once per worktree,
while each worktree still gets its own independent working tree, staged state, and
branch. On cleanup, the hook opportunistically prunes stale shared-store instance
entries and removes the worktree's local `.lore` metadata. If `lore` isn't available,
or the current directory isn't a Lore repo, the worktree degrades gracefully to a
plain directory.

## Contributing

Issues, playbook corrections, and especially **reports from running this against a
real `lore` server** are welcome - see [CONTRIBUTING.md](../CONTRIBUTING.md). Lore is
pre-1.0 and its command surface still evolves, so reports from your version make this
better for everyone.

## License

**Not yet licensed for reuse.** This repo has no LICENSE file yet, so all rights are
reserved by default. A license will be added before this repo is made public - see the
root [README](../README.md#license).

---

Part of the [ButterStack gamedev agents](../README.md) series.

*The open agents trail what ButterStack learns running gamedev tooling in production - get the managed version at [butterstack.com](https://butterstack.com?utm_source=github&utm_medium=repo&utm_campaign=gamedev-agents).*
