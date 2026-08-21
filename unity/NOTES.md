# Unity Agent - plan & design notes

Design notes for the `unity` plugin. It mirrors the shipped
[`perforce`](../perforce), [`jenkins`](../jenkins), [`lore`](../lore), and
[`unreal`](../unreal) agents' shape and posture: a read-first
Claude Code plugin to **observe, diagnose, and safely operate a Unity
project's CLI build pipeline**, tuned for game development. Unity is the
second engine in the series after Unreal; the `unreal` agent's shape
(doctor-first, gated builds, a guard hook) transfers directly. What differs
is Unity-specific: version identity lives in
`ProjectSettings/ProjectVersion.txt`, the regenerable cache is `Library/`,
every asset's GUID lives in a sibling `.meta` file, and - new with this
plugin - the CLI surface is Unity's **standalone `unity` CLI**
(`1.0.0-beta.x`), not just the Editor's classic `-batchmode` command line.

## Scope for this pass - "start with the CLI"

The goal was to start from Unity's
["Meet the Unity CLI"](https://unity.com/blog/meet-the-unity-cli)
announcement and mirror the `unreal` plugin's structure. This pass is built
on **verified, first-hand research from a real rig** (Windows 11, Unity CLI
`1.0.0-beta.2`, Unity 2022.3.62f3 - the final 2022.3 LTS patch), captured
2026-07-22. That matters because **the published Unity CLI docs are
materially incomplete**: the reference page lists only the Hub-ish commands
and omits `build`, `test`, `run`, `license`, `doctor`, `diagnose`, `mcp`,
`pipeline`, `command`, `status`, `list`, and `shell` - the commands an agent
needs most. The skills therefore teach "trust `unity <cmd> --help` on the
box" as an operating rule, and every command form they cite is verbatim from
the real binary.

An earlier authoring pass had no access to the real CLI and built the plugin
entirely on classic Editor `-batchmode`. Its structure and safety posture
were kept (the guard-script shape, the doctor structure, the batchmode
exit-0 trap, `.meta`/`Library/` discipline); its CLI content was replaced
wholesale with the verified surface once real access was available.

## The central design decision - branch on Editor version

The Unity CLI's surface splits, and the agent routes on
`ProjectSettings/ProjectVersion.txt` (`m_EditorVersion`) **before proposing
any command**:

- `build` / `test` / `run` / `install` / `editors` / `license` / `releases` /
  `doctor` / `diagnose` etc. work against **any** Editor the CLI can resolve,
  **including 2022.3**.
- `pipeline` / `command` / `list` / `status` / `mcp` require the
  `com.unity.pipeline` package, which requires **Editor 6.0 or later**. On a
  2022.x project the live-Editor/MCP half of the CLI simply does not exist,
  and the agent says so instead of suggesting commands that will fail.

The validation rig is deliberately pinned to **2022.3 LTS** (the Unity analog
of validating Unreal on 5.6/5.8), so 2022.x is the primary path and Unity 6
is the secondary path - the skills are written in that order, with both kept
correct. A second probe project on the same rig (Unity `6000.3.20f1`) later
verified the Unity 6 half live - see "Verified vs not-yet-verified" below and
the `unity-pipeline` skill.

## Locked decisions (carry over from perforce/jenkins/unreal)

- **First-party / CLI-driven; no MCP dependency.** The plugin wraps Unity's
  own CLI. `unity mcp` exists (Unity 6 + Pipeline package) and is documented
  as an optional surface, never a requirement - same posture as the `unreal`
  agent toward its MCP landscape.
- **Read-first.** Observe/diagnose runs freely; every build/test/run,
  install, license operation, and version change is a deliberate, gated
  action.
- **Establish context first - never guess the Editor version.** Read
  `m_EditorVersion`, route the CLI surface, resolve installed Editors and the
  license, then act.
- **The exit-0 trap is a first-class rule.** `--execute-method` code that
  doesn't check `report.summary.result` and call `EditorApplication.Exit(1)`
  makes Unity exit 0 on a failed build. The agent never reports success from
  an exit code alone - artifact + log, always.
- **`unity license status` is the license probe, not `unity auth status`.**
  Verified on the rig: an active Personal ULF with nobody signed in.
  "Not signed in" is a normal, healthy CI state.
- **Never inline secrets.** Android signing flags leak into shell history and
  CI logs (Unity's own help says so) - env/CI secret store only.
- **Structured output always**: `--format json --no-banner --non-interactive`
  on every parsed invocation; errors on stderr, data on stdout.

## Never-do list -> `guard-unity.sh`

Hard-block (backstop, mirrors `guard-unreal.sh`): destructive `rm`/`mv`/
overwrite of `Assets/`, `ProjectSettings/`, or `Packages/` (the project -
belongs to source control); deleting any `*.meta` file (it carries the asset
GUID; deleting one orphans every reference); any write into a Unity Editor
install tree (`.../Hub/Editor/<version>`, `Unity.app` - a read-only
reference). **Allowed**: deleting regenerable build state - `Library/`,
`Temp/`, `Logs/`, `obj/`, `Builds/` (the agent still confirms a `Library/`
wipe because of the reimport cost, but the hook does not block it).

**Honest limit**: this is a shell-string matcher, not a sandbox. It catches
the common direct forms (`rm x.meta`, `rm -rf Assets/...`) and chained
variants, but a path that never puts the protected filename or directory
directly next to `rm`/`mv` - `find Assets -name '*.meta' | xargs rm`,
`git clean -xfd Assets` - is not something a shell-string matcher can
reliably see and is not caught. The hook is a backstop against the common
mistake, not a guarantee against every route to the same deletion; treat
source control (commit before destructive local operations) as the real
safety net.

Soft gates the agent owns: `--allow-install` (multi-GB silent download);
`--allow-dirty-build` (defeats the CLI's own uncommitted-changes guard);
`unity license activate`/`return` (seat); `unity editors upgrade` and any
`--editor-version` change (one-way reserialization); `unity uninstall`;
`unity pipeline install` (mutates `Packages/manifest.json`).

## Verified vs not-yet-verified

Verified first-hand against a real rig (Windows, Unity CLI beta, both a 2022.3 LTS
Editor and a Unity 6 Editor): the full command surface against the docs page,
exit-code and format behavior, an end-to-end `build`/`test` producing a real
artifact and NUnit report, the Unity 6 Pipeline boundary enforcement, and the full
Pipeline live-Editor surface (the state ladder, the 140-tool dump, the server-side
`confirm`/`dry_run` gates, the loopback-only transport). Full findings - including
what this pass corrected from the original docs-derived draft - are in
[`LEARNINGS.md`](./LEARNINGS.md).

**Still not verified:** running `unity mcp` end-to-end from a real client; most of
the 140 Pipeline tools individually (the package is experimental and will move);
non-Windows CLI installs; and any build target beyond the one exercised here.

## Open questions

- Whether the Unity Gaming Services CLI (`ugs` - Cloud Save/Economy/Remote
  Config deployment) belongs anywhere in this plugin - leaning out-of-scope:
  it is a services/backend surface, not the build pipeline.
- Editor scripting / asset-pipeline depth - the Unity 6 half of this is now
  the `unity-pipeline` skill (the analog of `unreal-editor-scripting`, built
  on the Pipeline tool surface). Still open: the 2022.x/headless analog
  (`unity run ... --` + `AssetDatabase` scripts, addressables), and per-tool
  depth as the experimental Pipeline package stabilizes.
- Runtime profiling (an analog of `unreal-profile`) - future.
- How fast the beta CLI churns its surface - each new beta should get a quick
  `--help` diff against `unity-cli` §3 before trusting the skill's table.
