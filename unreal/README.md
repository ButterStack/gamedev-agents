# Unreal Agent

**A Claude Code plugin to observe, diagnose, and safely operate your Unreal Engine
project's build/cook/package pipeline and editor automation - built for game
development.**

> Third in the series of public gamedev agents from ButterStack.

Unreal Engine punishes guesswork: builds and cooks run for minutes-to-hours and
hog the machine, the editor must be closed to build, `.uasset`/`.umap` are binary
and belong to Perforce's exclusive-checkout model, and opening a project in a
newer engine re-saves its assets forward **one-way**. This is a domain-specific
[Claude Code](https://claude.com/claude-code) agent that models those sharp edges
instead of treating UE like a generic build system.

It is **read-first**: its job is to *diagnose and validate before running anything
expensive* - an engine+project+version doctor (`.uproject` `EngineAssociation` vs
`Engine/Build/Build.version`, BuildId/`.modules`, project setup, DDC/ignore
hygiene, Windows `MAX_PATH`) and cook/build-log triage (`LogCook`/
`LogShaderCompilers`/DDC-hit-rate/PAK-size grammar) - with gated, confirmed builds
(`RunUAT BuildCookRun`, UBT), first-party editor automation (headless Python,
Remote Control, Automation tests), and runtime performance profiling (Unreal
Insights, `stat`/`obj` triage, GC/UObject and GPU/Nanite heuristics) as the
supporting act.

## Who this is for

Game studios and solo devs on UE 5.4-5.8 who want an AI assistant that gets the
things generic agents miss: **never guess the engine** (version matching is
ruthless - a source build's BuildId changes every compile), **the editor must be
closed to build**, and **binary assets must be `p4 edit`-checked-out before any
tool touches them**.

## What's in the box

```
agents/unreal.md                        the agent (context/version rules, gates, failure classification)
skills/unreal-observe/SKILL.md           engine+project+version doctor + cook/build-log diagnosis
skills/unreal-build/SKILL.md             gated UBT + BuildCookRun playbooks (FAST_COOK tracer vs full), DDC warming
skills/unreal-editor-scripting/SKILL.md  headless Python, Remote Control, Automation tests, the binary-asset loop, MCP posture
skills/unreal-profile/SKILL.md           runtime perf - Insights trace channels, stat/obj triage, GC/UObject + GPU/Nanite heuristics
commands/unreal-doctor.md                /unreal-doctor    - project + engine + version health
commands/unreal-build.md                 /unreal-build     - gated tracer / full build / compile
commands/unreal-cook-logs.md             /unreal-cook-logs - cook/build log triage & metrics
commands/unreal-profile.md               /unreal-profile   - runtime perf triage; gated live Insights capture
hooks/ + scripts/                        guard-unreal (blocks rm/mv of Content/Source/.uproject, engine-tree writes, shared-DDC wipes)
```

## Install

This repo is a self-contained Claude Code plugin marketplace. In Claude Code:

```
/plugin marketplace add ButterStack/gamedev-agents
/plugin install unreal@gamedev-agents
```

The agent, skills, slash commands, and the guard hook are auto-discovered on
install.

## Setup

You need an Unreal Engine install (5.4-5.8) and a project with a `.uproject`. The
agent resolves the engine from `UE_ROOT`, the source-build GUID registration
(Windows registry / `~/.config/Epic/UnrealEngine/Install.ini`), or conventional
install roots - it will ask rather than guess. `jq` is recommended (`.uproject`,
`Build.version`, and `.modules` are JSON); the guard hook falls back to `sed`
without it.

**Pair it with the [`perforce`](../perforce) plugin.** UE content is binary and
exclusive-checkout; that plugin owns the p4 side this agent's asset loop depends
on (checkout/submit discipline, `+l` lock etiquette, and the UE
typemap/P4IGNORE presets), plus `CLAUDE_CODE_PERFORCE_MODE` setup.

As a backstop, this plugin ships a `guard-unreal` hook that hard-blocks
destructive filesystem commands (`rm`/`mv`/truncating redirects/`find -delete`)
against `Content/` and `Source/` trees and `*.uproject` files (those belong to
Perforce), any write into the engine install tree (`UE_*/Engine/...` is a read-only
reference), and deletion of a shared/network DerivedDataCache - regardless of how
your permissions are set. Build-output cleanup (`Saved/`, `Intermediate/`,
`Binaries/`, a *local* DDC) passes through.

## Quickstart

Ask the `unreal` agent, or use the slash commands:

- **"Is this project healthy? Which engine does it want?"** → `/unreal-doctor`
  (version match, GUID vs launcher association, targets, BuildId, hygiene,
  editor-running, MAX_PATH)
- **"Do a quick sanity cook."** → `/unreal-build fast` (FAST_COOK tracer - shows
  the exact command + cost, runs on your confirmation)
- **"Package a Win64 Shipping build."** → `/unreal-build full Win64 Shipping`
  (gated the same way; reports DDC hit rate, PAK size, warnings)
- **"Why did last night's cook take 3 hours?"** → `/unreal-cook-logs` (first
  error, phase timing, DDC hit rate - cold-cache diagnosis)
- **"The game hitches every minute - profile it."** → `/unreal-profile` (reads an
  existing `.utrace`/stat capture first; a live Insights capture is gated - exact
  launch line + disk cost, runs on your confirmation)
- **"Bump the light intensity in Arena and verify it."** → the agent walks the
  checkout → modify-via-script → save → verify → submit loop via the
  `unreal-editor-scripting` skill

## Safety posture

Opinionated about UE's sharp edges: it resolves engine version + build type +
project association **before acting** and warns on any mismatch; treats one-way
asset upgrades, full cooks, and engine rebuilds as named, confirmed decisions;
checks the editor is closed before building (and never kills it); requires
`p4 edit` before any tool touches a binary asset; always runs UAT with
`-unattended -nop4 -utf8output`; and keeps Remote Control / MCP strictly on
localhost (they have **no auth by design**). Blueprint node-graph authoring is
out of scope by design - the agent follows a C++-heavy / thin-Blueprint strategy
instead. See `agents/unreal.md` for the full rules.

## A note on version matching

The doctor treats version identity as the first-class problem it is in UE:
`EngineAssociation` version-string vs source-build GUID, BuildId mismatches
(*"modules ... built with a different engine version"*), per-build plugin
recompiles on source engines, and UGS Precompiled Binaries as the studio answer.
If you've ever had Blueprints silently lose nodes after an engine update, that's
this.

## Contributing

Issues, playbook corrections, and especially **real-engine testing reports** are
welcome - see [CONTRIBUTING.md](../CONTRIBUTING.md). Exact log phrasing, flag
behavior, and Remote Control payloads vary across UE versions (this plugin
targets 5.4-5.8, authored from production build tooling on UE 5.6), so reports
from your engine version make this better for everyone.

## License

**Not yet licensed for reuse.** This repo has no LICENSE file yet, so all rights are
reserved by default. A license will be added before this repo is made public - see the
root [README](../README.md#license).

---

Part of the [ButterStack gamedev agents](../README.md) series.

*The open agents trail what ButterStack learns running gamedev tooling in production - get the managed version at [butterstack.com](https://butterstack.com?utm_source=github&utm_medium=repo&utm_campaign=gamedev-agents).*
