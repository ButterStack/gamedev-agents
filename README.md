# ButterStack Gamedev Agents

A collection of small, focused, domain-specific [Claude Code](https://claude.com/claude-code)
agents for **game development**, packaged as installable plugins.

ButterStack builds narrow, safe, domain-specific agents rather than one giant
do-everything assistant. This repo is the home for a growing series - each
agent is its own plugin in its own directory, distilled from the agents we run
against our own production depots and builds.

## Agents

| Agent | What it does | Status |
|---|---|---|
| [**perforce**](./perforce) | Observe, analyze, and safely operate a Perforce / Helix Core (`p4`/`p4d`) system - read-first, gamedev-tuned (streams, `+l` locks, engine typemap/P4IGNORE). | Ready (v0.2.0) |
| [**unreal**](./unreal) | Observe, diagnose, and safely operate Unreal Engine build/cook/package pipelines and editor automation - read-first, version-matching doctor, cook-log triage, gated `BuildCookRun`/UBT, first-party editor scripting. | Ready (v0.1.0) |
| [**lore**](./lore) | Observe, analyze, and safely operate an Epic Games [Lore](https://github.com/EpicGames/lore) VCS (the `lore` CLI, formerly Unreal Revision Control) - read-first, staging/commit/push/sync/branch/merge, gated `obliterate` & history rewrites. | Ready (v0.1.0) |
| [**unity**](./unity) | Observe, diagnose, and safely operate a Unity project's CLI build pipeline via the standalone Unity CLI - read-first, Editor-version routing (2022 LTS batchmode vs Unity 6), the batchmode exit-0 trap, gated `unity build`/`test`/`run`, license-vs-auth diagnosis, and the verified Unity 6 Pipeline live-Editor + MCP surface (140 tools, Unity's own confirm/dry_run gates). | Ready (v0.2.0) |
| [godot](./godot) | Godot headless export/build workflows. | Planned |
| [**jenkins**](./jenkins) | Observe, operate, and safely diagnose a Jenkins CI/CD server; read-first, built around the Perforce `change-commit` → Jenkins build loop, with gated triggers/aborts and the Script Console refused. | Ready (v0.1.0) |

## Install

This repo is a self-contained Claude Code plugin marketplace. In Claude Code:

```
/plugin marketplace add ButterStack/gamedev-agents
/plugin install perforce@gamedev-agents
```

Each agent installs the same way (`<name>@gamedev-agents`) as it ships. See a
plugin's own directory (e.g. [`perforce/`](./perforce)) for its setup and usage.

## Why these exist

Every agent here started the same way: point Claude Code at a real tool - a live
Helix Core server, a real Unreal build/cook pipeline, a CSRF-enabled Jenkins
controller, a running `loreserver` - and see where a general-purpose, Git-shaped
mental model gets it wrong. The gap is usually specific and durable: Perforce files
are read-only until checked out; a Unity batchmode build can exit `0` with nothing
built; a headless Unreal engine/binary mismatch silently drops a module instead of
prompting; a Jenkins CSRF crumb has to be fetched in the same HTTP session as the
write it protects. Each plugin's `agents/*.md` and skills encode what we found, and
each `LEARNINGS.md` is a dated, running log of what real integrations keep teaching
us - see any plugin's `LEARNINGS.md` for the specifics.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md). Real-depot and real-engine testing reports
are especially valuable - behavior varies a lot by server/engine version and setup.

## License

**Not yet licensed for reuse.** This repo does not currently include a LICENSE file,
so all rights are reserved by default - treat it as read-only reference, not
licensed open-source code. A license decision (most likely MIT, matching
ButterStack's stated intent for this series) is still pending and will be made
before this repo is ever made public.

---

*The open agents trail what ButterStack learns running gamedev tooling in
production - get the managed version at
[butterstack.com](https://butterstack.com?utm_source=github&utm_medium=repo&utm_campaign=gamedev-agents).*
