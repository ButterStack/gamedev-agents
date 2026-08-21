# Perforce Agent

**A Claude Code plugin to observe, analyze, and safely operate your Perforce
(Helix Core) system - built for game development.**

> First in a planned series of public gamedev agents from ButterStack.

Perforce / Helix Core is the dominant version control system in game development -
it's built for large binary assets, exclusive-checkout locking, and stream-based
branching in ways Git struggles with. This is a domain-specific
[Claude Code](https://claude.com/claude-code) agent that understands Perforce's
mental model (depot → client → changelist) instead of guessing from Git muscle
memory.

It is **read-first**: its job is to *observe and analyze* your p4 system - workspace
and server state, changelist history and velocity, exclusive-lock (`+l`) contention,
CI-trigger health, and depot bloat - with safe, gated write operations (checkout,
submit, shelve, reconcile, resolve) as the supporting act. Destructive operations
(`revert`, `obliterate`, force sync, `unlock -f`) are treated with the caution they
deserve around irreplaceable art/audio/build assets.

## Who this is for

Game studios and solo devs on Helix Core who want an AI assistant that models
Perforce correctly - including the thing generic agents miss: **Perforce files are
read-only until you `p4 edit` them**, so a naive edit either fails or clobbers the
read-only bit and desyncs the depot.

## What's in the box

```
agents/perforce.md               the agent (role, safety rules, read-only-checkout & connection rules)
skills/p4-observe/SKILL.md        read-only observability & analysis playbooks
skills/p4-workflows/SKILL.md      operational playbooks (checkout/submit, shelve, reconcile, resolve, locks, streams, typemap)
commands/p4-status.md             /p4-status  - workspace & server snapshot
commands/p4-analyze.md            /p4-analyze - changelist velocity, CI health, bloat
commands/p4-locks.md              /p4-locks   - exclusive-lock (+l) contention
commands/p4-sync.md               /p4-sync    - guided, safe sync
hooks/ + scripts/                 guard-p4 (blocks obliterate/admin) + WorktreeCreate/Remove p4-client isolation
```

## Install

This repo is a self-contained Claude Code plugin marketplace. In Claude Code:

```
/plugin marketplace add ButterStack/gamedev-agents
/plugin install perforce@gamedev-agents
```

The agent, skills, slash commands, and worktree hooks are auto-discovered on install.

## Setup

You need `p4` installed and configured so `p4 info` succeeds (via
`P4PORT`/`P4USER`/`P4CLIENT`, a `.p4config`, or `p4 set`).

**The real safety boundary is the p4 account.** Run the agent as a **normal or
read-only Perforce user - never as `super`/admin.** Perforce protections, not Claude
Code permissions, are what actually stop a destructive command. As a backstop, this
plugin also ships a `guard-p4` hook that hard-blocks `p4 obliterate`, `p4 admin`,
`archive`/`restore`, `dbverify`, and other server-lifecycle commands regardless of
how your permissions are set, including when a benign `p4` call precedes the
destructive one in the same command (`p4 info && p4 obliterate ...`). It is a
shell-string matcher, not a full shell-grammar parser - the p4 account's own
permissions remain the control that cannot be talked around.

Two settings are worth adding to your **own** `~/.claude/settings.json` or project
`.claude/settings.json` (plugins can't ship `env`/`permissions` for you):

**1. Turn on Perforce mode** so Claude Code knows read-only files must be checked out
before editing (this env var is currently **undocumented** and may change between CLI
releases):

```json
{
  "env": { "CLAUDE_CODE_PERFORCE_MODE": "1" }
}
```

**2. Optionally reduce prompts** for read-only inspection. Note a caveat: the skills
run structured queries with global flags first (`p4 -ztag -Mj changes ...`,
`p4 -ztag info`), so an allow rule like `Bash(p4 changes:*)` does **not** match them -
you must list the `-ztag` forms too. A starter list:

```json
{
  "permissions": {
    "allow": [
      "Bash(p4 info:*)", "Bash(p4 -ztag info:*)",
      "Bash(p4 login -s:*)",
      "Bash(p4 opened:*)", "Bash(p4 -ztag fstat:*)",
      "Bash(p4 changes:*)", "Bash(p4 -ztag -Mj changes:*)",
      "Bash(p4 describe:*)", "Bash(p4 sizes:*)", "Bash(p4 filelog:*)",
      "Bash(p4 client -o:*)", "Bash(p4 streams:*)", "Bash(p4 istat:*)",
      "Bash(p4 triggers -o:*)", "Bash(p4 protects:*)"
    ]
  }
}
```

> ⚠️ **Do not add `Bash(p4:*)`.** That allowlists `p4 obliterate`, `p4 client -d`,
> `p4 admin stop`, and every other write - defeating the point. Prefix matching can't
> cleanly separate read from write across p4's global flags, which is why the p4
> account (above) and the `guard-p4` hook are the real guardrails. Anything not
> allowlisted simply prompts; write/destructive commands are proposed and gated by the
> agent, not run silently.

## Quickstart

Ask the `perforce` agent, or use the slash commands:

- **"What's the state of my Perforce workspace?"** → `/p4-status` (connection, ticket,
  opened files, pending/shelved CLs, reconcile drift, locks by others)
- **"Analyze depot activity this month."** → `/p4-analyze` (submission velocity,
  contributors, CI-trigger health, large-binary bloat)
- **"Who's blocking me - what's locked?"** → `/p4-locks` (exclusive-lock holders and
  contention)
- **"Sync me to latest on the Art tree."** → `/p4-sync` (dry-run preview, then sync)
- **"Shelve my changes, I need to switch tasks."** → the agent walks it via the
  `p4-workflows` skill

The agent warns before anything destructive and prefers safer alternatives (shelve,
dry-run) when there's ambiguity.

## Safety posture

Opinionated about Perforce's sharp edges: it never runs `p4 obliterate` without
explicit, by-name confirmation; warns and prefers `p4 shelve` before any `p4 revert`;
dry-runs (`-n`) large syncs/reverts/reconciles; treats large binaries and `+l` locks
as expensive; and never forces past another user's lock without spelling out the
consequence. See `agents/perforce.md` for the full list.

## Parallel work isolation

For non-git VCS, Claude Code delegates worktree isolation to hooks. This plugin ships
`WorktreeCreate`/`WorktreeRemove` hooks that provision a dedicated `p4 client` rooted
at each worktree (derived from your current client) and tear it down on cleanup - so
parallel agents don't fight over one workspace. If `p4` isn't available the worktree
degrades gracefully to a plain directory.

## Contributing

Issues, playbook corrections, and especially **real-depot testing reports** are
welcome - see [CONTRIBUTING.md](../CONTRIBUTING.md). Much Perforce behavior varies by
server version and topology (streams vs classic, security level, SSL, unicode, edge/
replica), so reports from your server make this better for everyone.

## License

**Not yet licensed for reuse.** This repo has no LICENSE file yet, so all rights are
reserved by default. A license will be added before this repo is made public - see the
root [README](../README.md#license).

---

Part of the [ButterStack gamedev agents](../README.md) series.

*The open agents trail what ButterStack learns running gamedev tooling in production - get the managed version at [butterstack.com](https://butterstack.com?utm_source=github&utm_medium=repo&utm_campaign=gamedev-agents).*
