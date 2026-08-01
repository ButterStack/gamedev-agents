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

Soft gates the agent owns: `--allow-install` (multi-GB silent download);
`--allow-dirty-build` (defeats the CLI's own uncommitted-changes guard);
`unity license activate`/`return` (seat); `unity editors upgrade` and any
`--editor-version` change (one-way reserialization); `unity uninstall`;
`unity pipeline install` (mutates `Packages/manifest.json`).

## Verified vs not-yet-verified

**Verified on the rig (2026-07-22, CLI `1.0.0-beta.2`, Unity 2022.3.62f3):**
the install lines (including the undocumented Windows `install.ps1`); the
full command surface vs the docs page; global options and format behavior;
exit codes; `unity build`/`test`/`run` flags and help-text examples
(verbatim); the license state (`auth status` "not signed in" alongside
`license status: active`, Personal ULF at `C:\ProgramData\Unity\Unity_lic.ulf`);
`editors` subcommands; the archived-version changeset requirement
(`unity install 2022.3.62f3 -c 96770f904ca7`); the release API for changeset
discovery; the beta-only channel (`latest.json` 404s).

**Since verified by a later live-validation pass** (full findings in
[`LEARNINGS.md`](./LEARNINGS.md)): an end-to-end `unity build` on 2022.3
producing a real artifact; `unity test` writing a real NUnit report; the §2
C# build-method contract, compiled and run on the rig **both ways** (checking
and swallowing the `BuildReport`) - the exit-0 trap reproduced at exit `0`
with no artifact; the Unity 6 boundary, confirmed by `unity pipeline install`
refusing a 2022.3 project with `Pipeline package requires Unity 6.0 or
higher.` and leaving the manifest untouched. That pass also **corrected** two
things authored here: exit codes are not the documented `0`/`1`/`130` (`6`
is common, and the CLI's code is not the Editor's), and the missing-
`com.unity.test-framework` precondition.

**Verified by the Unity 6 Pipeline pass (2026-07-22, Editor `6000.3.20f1`,
`com.unity.pipeline` `0.3.1-exp.1`, live Editor):** `pipeline install`
succeeding - with **no sign-in required** (the docs' `auth login` ordering is
not enforced); the state ladder (`pipeline list` / `status` / `list` /
`command`) and its no-Editor degradation modes; the 140-tool dump
(`unity list --format json`) with Unity's own server-side `confirm`/`dry_run`
gates (29/40 tools, 400 + exit 6 on refusal); the response envelope and the
second exit-0 trap (`unity command` exits 0 on inner `success:false`); the
nine `*_status` async pollers; `list_build_targets`/`isInstalled` as the
build precondition; the loopback-only transport (`127.0.0.1:7800`); and the
`unity mcp configure --list` client table (16 clients incl. `claude-code`).
All captured in the `unity-pipeline` skill.

**Still not verified:** running `unity mcp` end-to-end (starting the stdio
server and driving it from a client); parameter passing to `unity command`
beyond the `--confirm true` flag form; most of the 140 Pipeline tools
individually (the package is experimental and the surface will move);
non-Windows CLI installs; the dirty-tree guard behind `--allow-dirty-build`;
any build target other than `StandaloneWindows64`, which leaves the whole
`--android-*` family help-level only; and the full option surfaces of the
assorted subcommands (`templates`, `cache`, `hub`, `env`, `config`, ...).

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
