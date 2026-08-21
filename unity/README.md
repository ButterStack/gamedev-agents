# Unity Agent

**A Claude Code plugin to observe, diagnose, and safely operate your Unity
project's CLI build pipeline - built for game development.**

> Part of the series of public gamedev agents from ButterStack, alongside
> [`perforce`](../perforce), [`unreal`](../unreal), [`lore`](../lore), and
> [`jenkins`](../jenkins).

Unity now has a real, standalone CLI (`unity`, currently `1.0.0-beta.x`) - a
Hub replacement, a batchmode front-end (`unity build` / `test` / `run`), and a
live-Editor control plane in one binary. It also has sharp edges the docs
undersell: the published CLI reference omits most of the commands an agent
needs, the CLI's surface **splits on Editor version** (the live-Editor/MCP
half requires Unity 6; on 2022 LTS it simply does not exist), a batchmode
build **can exit 0 with nothing built**, and "not signed in" does **not**
mean unlicensed. This is a domain-specific
[Claude Code](https://claude.com/claude-code) agent that models those edges
instead of treating Unity like a generic build system - authored from
verified, first-hand CLI research on a real rig, not from the docs page.
Both halves are verified: batchmode on 2022.3 LTS, and the Unity 6 Pipeline
live-Editor surface (140 tools, Unity's own server-side confirm/dry_run
gates, the MCP stdio server) against a running Unity 6.3 Editor.

It is **read-first**: its job is to *diagnose and validate before running
anything expensive* - a project+Editor-version doctor that routes the CLI
surface before proposing a single command - with gated, confirmed builds and
tests as the supporting act.

## Who this is for

Game studios and solo devs on Unity 2022 LTS or Unity 6 who want an AI
assistant that gets the things generic agents miss: **the Editor version is
the routing decision** (2022.x = batchmode only; 6.0+ adds
Pipeline/`command`/MCP), **never trust a batchmode exit code alone** (verify
the artifact and the log), **`unity license status` is the license probe**
(`auth status` is just the cloud login), and **`Assets/` + `.meta` files are
the project** (`Library/` is a cache).

## What's in the box

```
agents/unity.md                  the agent (version routing, gates, failure classification)
skills/unity-observe/SKILL.md    the doctor - version-first routing, editors, license probe, hygiene, log grammar
skills/unity-cli/SKILL.md        the Unity CLI itself - install/beta channel, real surface vs docs, JSON/exit codes
skills/unity-build/SKILL.md      gated unity build/test/run - the --execute-method contract, signing discipline, verification
skills/unity-pipeline/SKILL.md   the Unity 6 live-Editor surface - state ladder, 140 tools, confirm/dry_run gates, async polling, MCP
commands/unity-doctor.md         /unity-doctor   - project + CLI + Editor + license health
commands/unity-build.md          /unity-build    - gated build with artifact+log verification
commands/unity-test.md           /unity-test     - gated EditMode/PlayMode run, NUnit XML results
commands/unity-pipeline.md       /unity-pipeline - drive a running Unity 6 Editor, dry_run before confirm
hooks/ + scripts/                guard-unity (blocks rm/mv of Assets/ProjectSettings/Packages/*.meta, Editor-install writes)
```

## Install

This repo is a self-contained Claude Code plugin marketplace. In Claude Code:

```
/plugin marketplace add ButterStack/gamedev-agents
/plugin install unity@gamedev-agents
```

The agent, skills, slash commands, and the guard hook are auto-discovered on
install.

## Setup

You need the **Unity CLI** (beta channel - there is no stable channel yet):

```sh
# macOS / Linux
curl -fsSL https://public-cdn.cloud.unity3d.com/hub/prod/cli/install.sh | UNITY_CLI_CHANNEL=beta bash
```

```powershell
# Windows (the docs' `| bash` line is wrong for PowerShell). install.ps1 is an
# undocumented CDN script Unity does not version - download and inspect it
# rather than piping straight into `iex`:
Invoke-WebRequest -Uri https://public-cdn.cloud.unity3d.com/hub/prod/cli/install.ps1 -OutFile install.ps1
Get-FileHash install.ps1 -Algorithm SHA256
# last verified 2026-08-21: 3b5b42c066f04a43aaa587cfa50c5873e0148b80138a8befc610f7a7477b58e6
# a different hash later isn't itself a red flag - Unity can update this file
# without notice - but re-read the script before running it if it changes.
$env:UNITY_CLI_CHANNEL="beta"; .\install.ps1
```

plus a Unity Editor matching the project's
`ProjectSettings/ProjectVersion.txt` - the agent resolves both and will ask
rather than guess. Note that archived Editor versions (anything pre-Unity-6
on a current Hub) install only with an explicit changeset
(`unity install 2022.3.62f3 -c 96770f904ca7`); the agent knows how to find
changesets. `jq` is recommended for parsing manifests and the CLI's JSON
output; the guard hook falls back to `sed` without it.

**Pair it with the [`perforce`](../perforce) plugin.** It ships the Unity
`P4IGNORE` preset (`Library/ Temp/ Logs/ Obj/`) for the generated directories
this agent treats as regenerable cache, not the project.

As a backstop, this plugin ships a `guard-unity` hook that hard-blocks
destructive filesystem commands (`rm`/`mv`/truncating redirects/
`find -delete`) against `Assets/`, `ProjectSettings/`, and `Packages/` trees
and any `*.meta` file (those belong to source control - and a deleted `.meta`
orphans its asset's GUID), plus any write into a Unity Editor install tree -
regardless of how your permissions are set. Regenerable build-state cleanup
(`Library/`, `Temp/`, `Logs/`, `obj/`, `Builds/`) passes through. **The hook is
a shell-string matcher, not a sandbox** - it catches the common direct and
chained forms, but a route that never puts the protected path next to
`rm`/`mv` (`find ... | xargs rm`, `git clean -xfd`) is not something a
shell-string matcher can reliably see. Source control, not this hook, is the
real backstop against data loss.

## Quickstart

Ask the `unity` agent, or use the slash commands:

- **"Is this project healthy? What can the CLI do here?"** -> `/unity-doctor`
  (version routing first: on 2022.x it tells you plainly that
  `pipeline`/`command`/`mcp` do not exist for this project)
- **"Run the tests before I build."** -> `/unity-test` (EditMode by default,
  `--timeout` always set, results read from the NUnit XML - not the exit code)
- **"Build the Windows player."** -> `/unity-build StandaloneWindows64`
  (gated - shows the exact `unity build --target ... --execute-method ...`
  line + cost, runs on your confirmation, then verifies the artifact and log)
- **"CI says the build passed but there's no player."** -> the agent's first
  suspect is the batchmode exit-0 trap: a build method that never checked
  `report.summary.result` - it reads the log and explains the fix
- **"Set up MCP so Claude can drive the Editor."** -> version check first: on
  2022.x, not possible (Pipeline needs Editor 6.0+) - the agent says so and
  offers the batchmode alternatives
- **"Rename that asset / switch the build target / clear the navmesh."** (a
  running Unity 6 Editor) -> `/unity-pipeline` - climbs the state ladder,
  previews with the tool's `dry_run`, and never passes Unity's own
  `confirm=true` gate without your explicit approval

## Safety posture

Opinionated about Unity's sharp edges: it resolves the project's Editor
version **before acting** and routes the CLI surface on it; never reports
build success from an exit code alone; probes licensing with
`unity license status` (an active machine license with nobody signed in is a
healthy CI state, not a problem to "fix" with a login); treats
`--allow-install` (multi-GB silent download), `--allow-dirty-build` (defeats
the CLI's own uncommitted-changes guard), license activate/return (seats),
`unity editors upgrade` and any `--editor-version` change (one-way asset
reserialization), `unity uninstall`, and `unity pipeline install` (edits
`Packages/manifest.json`) as named, confirmed decisions; always sets
`--timeout` on unattended test/run (it is off by default); and never inlines
Android signing secrets (Unity's own help warns they leak into shell history
and CI logs). On the Unity 6 live-Editor surface it honors Unity's own
server-side safety gates - `dry_run` previews first, and `confirm=true` is
never passed on your behalf - and keeps the loopback-only control port and
MCP server strictly on the machine. See `agents/unity.md` for the full rules.

## A note on the CLI being beta

The Unity CLI has no stable channel yet (`latest.json` 404s; installs pin
`UNITY_CLI_CHANNEL=beta`), and the published reference documents only a
fraction of the real surface. This plugin's command forms are verbatim from a
real `1.0.0-beta.2` binary - and its skills teach the durable rule: **trust
`unity <cmd> --help` on the box over any doc, including this plugin.**

## Contributing

Issues, playbook corrections, and especially **real-install testing reports**
are welcome - see [CONTRIBUTING.md](../CONTRIBUTING.md). The CLI is beta and
its surface may shift between releases (this plugin was validated against
`1.0.0-beta.2` with Unity 2022.3.62f3 for batchmode and Unity 6000.3.20f1
with `com.unity.pipeline` 0.3.1-exp.1 for the live-Editor surface), so
reports from your CLI/Editor version make this better for everyone.

## License

**Not yet licensed for reuse.** This repo has no LICENSE file yet, so all rights are
reserved by default. A license will be added before this repo is made public - see the
root [README](../README.md#license).

---

Part of the [ButterStack gamedev agents](../README.md) series.

*The open agents trail what ButterStack learns running gamedev tooling in production - get the managed version at [butterstack.com](https://butterstack.com?utm_source=github&utm_medium=repo&utm_campaign=gamedev-agents).*
