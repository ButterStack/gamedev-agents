# Design notes

## Why a domain-specific Unreal agent

Unreal Engine punishes guesswork. It mirrors the shipped [`perforce`](../perforce)
agent's shape and posture, and is the engine-side specialist the other plugins in
this repo point at: the `perforce` agent carries UE typemap/`P4IGNORE` presets, and
the `jenkins` agent defers `BuildCookRun` stage/flag depth to this one.

The object here is not a server - it's the **engine + project + editor + build
pipeline** on a workstation or build node. So "read-first" translates to: **diagnose
and validate before running anything expensive**. Cooks/builds run for
minutes-to-hours and hog the machine; the editor must be closed to build;
`.uasset`/`.umap` are binary and must be `p4 edit`-checked-out before any tool
touches them; opening a project in a newer engine re-saves its assets forward
**one-way**.

## Key decisions

- **First-party / CLI-driven; no MCP dependency in v1.** Wrap Epic's own stable
  automation surfaces (Python Editor Scripting, Remote Control, the Automation
  framework, UBT, UAT) rather than a third-party plugin. An MCP server is an
  optional *accelerant if present and version-matched*, never a requirement. Two MCP
  flavors exist today and both stay optional: Epic's own built-in server (UE 5.8+,
  experimental, loopback-only, no auth) and several third-party servers, each of
  which recompiles per engine version and has Blueprint-graph tools as its buggiest
  surface. Imitate the useful tool taxonomy; depend on none.
- **Read-first.** Observe/analyze/validate runs freely; every *expensive or mutating*
  action (a build/cook/package, modifying a binary asset, a one-way version upgrade)
  is gated + confirmed.
- **Establish context first - never guess the engine.** The Unreal analog of the
  perforce agent's "never guess identity": resolve **engine version + build type +
  project association** from files before acting. Never assume a default install
  path, never assume a plugin binary is portable.
- **Never bake creds; localhost-only automation.** Remote Control and every Unreal
  MCP server bind loopback with no auth by design - never expose them beyond
  localhost, the same discipline the `jenkins` agent applies to API tokens.
- **C++-heavy, thin-Blueprint strategy.** Authoring Blueprint node-graphs from script
  is the buggiest surface in every third-party MCP server, and Epic is sunsetting
  Blueprints in UE6 in favor of Verse - so it's out of scope for v1 by design. Logic
  lives in C++ (compiled by UBT/Live Coding); Blueprints stay thin (subclass, set
  defaults, get placed in a level via Python, which handles structural/param work
  well).

## What informed the doctor and build playbooks

The version-matching doctor and the `BuildCookRun` flag sets weren't written from
the docs alone - they're informed by a real, production Unreal build pipeline
ButterStack runs: a build script that drives `RunUAT BuildCookRun` (a fast
iterate-cook tracer vs. a full build/stage/pak/archive), a cook-log parser for the
`LogCook`/`LogShaderCompilers`/`LogDerivedDataCache`/`LogPakFile` grammar, and a
project-doctor client that compares a project's `EngineAssociation` against the
installed engine's `Build.version` and validates `Source/`/`Content/`/`Config/`
layout. That pipeline's orchestration order - `setup → validate → build → collect` -
is the read-first posture in code, and it's what this agent's "validate before build"
rule is modeled on.

## Version matching - the Unreal-specific footgun (why it gets a dedicated section)

UE is ruthless about versions; this is the "establish identity" problem for this
agent, same as the perforce agent's identity-from-`p4 info` rule.

- **`.uproject` `EngineAssociation`**: a **version string** (`"5.4"` - launcher/
  installed build, portable) vs. a **GUID** (a *source* build registered
  per-developer - not portable; a committed GUID breaks for every teammate) vs.
  **empty** (editor prompts).
- **BuildId (`.modules` JSON)**: every compile stamps a BuildId into each binary dir;
  the engine silently refuses to load any DLL whose BuildId doesn't match the
  executable's. Installed builds get a stable BuildId; source builds get a new
  random one per compile, so plugins must be recompiled per build.
- **One-way asset upgrade**: opening a `.uasset` in a newer editor re-saves it
  forward; an older editor then can't open it. Gate opening a project against a
  newer/mismatched engine - it's a whole-team decision, not a convenience.
- **UnrealGameSync (UGS)** is the studio answer on Perforce source-engine teams: CI
  builds a matching-BuildId editor, zips it (Precompiled Binaries), and submits it to
  Perforce, so non-programmers can sync working binaries without compiling.

## Live-engine validation learnings

Validated against real Unreal Engine 5.6 and 5.8 installs, running real
`BuildCookRun` builds and cooks end-to-end (not just log samples) - see
[`fixtures/`](./fixtures) for the actual captured build/cook logs this plugin's log
grammar was checked against, and [`LEARNINGS.md`](./LEARNINGS.md) for the full dated
findings. The headline corrections:

- **A matched 5.6 cook uses ZenServer, not the classic DDC line.** Real UE 5.5+ has
  **no `DDC Hit Rate` line** in its cook log - cache effectiveness instead lives in
  `LogShaderCompilers: ... FShaderJobCache stats ... cache hits x%, DDC hits y%`, and
  cook progress is a `Cooked packages N ... Total T` tally, not per-asset lines. This
  held on both 5.6 and 5.8, so the fix is version-general, not a 5.6-specific patch.
- **A headless engine/binary mismatch does not print the interactive "rebuild?"
  prompt.** Running UE 5.8 against 5.6-built binaries **silently drops** the mismatched
  module and reports a misleading `LogPluginManager: ... could not be found ...
  consider disabling the plugin` - which is a trap: the right fix is to rebuild for
  the running engine, not disable the plugin the log suggests disabling.
  Reproduced and captured live; see `fixtures/parrot-ue5.8-vs-5.6-mismatch.txt`.
- **UBT exit codes, verified against real failures**: `8` = RulesError (a bad module
  dependency reference), `6` = OtherCompilationError - corrected from an earlier,
  wrong guess. See `fixtures/parrot-ue5.6-build-fail-rulesError.txt` for the real
  failure log this was verified against.
- Standing up a real UE-in-Docker build rig taught its own set of lessons (host
  architecture, WSL2 idle-shutdown timers, image-transfer pitfalls, RAM pressure on a
  16 GB box) - these are operational/rig learnings rather than agent-diagnosis fixes,
  and the durable ones are folded into `unreal-build`'s environment guidance and
  logged in full in `LEARNINGS.md` section B.

## Open questions

- **MCP posture**: pure first-party-automation for now, treating Epic's built-in MCP
  and third-party servers as detected, version-gated accelerants. A pivot to
  wrapping a thin first-party MCP server is a live option if that changes.
- **Blueprint-graph authoring**: explicitly out of scope (buggy everywhere, and
  Blueprints are being deprecated in favor of Verse). Revisit only if a task
  genuinely needs graph automation.
- **UE version span**: this plugin targets UE 5.4-5.8; UE6/Verse is forward-looking
  and not yet covered.
