---
name: unreal-observe
description: >
  Read-only Unreal Engine diagnostics - the engine+project+version DOCTOR
  (.uproject EngineAssociation vs Engine/Build/Build.version, project setup,
  .Target.cs targets, plugin/BuildId, DDC and P4IGNORE hygiene, editor-running,
  Windows MAX_PATH) and cook/build LOG diagnosis (the LogCook / LogShaderCompilers
  / LogDerivedDataCache / LogPakFile grammar, error triage, DDC-hit-rate and
  PAK-size metrics). Use for inspecting and reasoning about an Unreal project
  WITHOUT building or changing it. To actually compile/cook/package use the
  `unreal-build` skill; to automate the editor use `unreal-editor-scripting`.
---

# Unreal Observe & Diagnose

Read-only playbooks for understanding an Unreal project and its build output.
**Nothing here compiles, cooks, or mutates** - every command is safe to run for
inspection. Placeholders use `<ANGLE_BRACKETS>`; `$UE_ROOT` is the resolved engine
install. `.uproject`, `Build.version`, and `.modules` are JSON - prefer `jq`.

Run §1-§2 (the doctor core) before ANY build the `unreal-build` skill proposes -
validate before build.

---

## 1. Find the project & its engine association

```sh
# The project file (search shallow - a workspace usually has exactly one)
find . -maxdepth 2 -name "*.uproject"

# Engine association - the project's claim about which engine it needs
jq -r '.EngineAssociation' <Project>.uproject
```

Interpret the value:

- **`"5.6"` (version string)** - launcher/installed build. Portable: any 5.6
  install opens it.
- **`"{B488FF40-...}"` (GUID)** - a **source build**, registered per-machine.
  **Not portable**: resolve it via Windows registry
  `HKCU\Software\Epic Games\Unreal Engine\Builds` (`reg query` the key; values map
  GUID→path) or Linux `~/.config/Epic/UnrealEngine/Install.ini`. A **committed**
  GUID breaks for every teammate - flag it; teams blank or script this field.
- **empty/missing** - the editor prompts on open; the project has no pinned engine.

Also worth reading from the same file:

```sh
jq -r '.Modules[]? | "\(.Name) (\(.Type))"' <Project>.uproject   # code modules
jq -r '.Plugins[]? | "\(.Name) enabled=\(.Enabled // true)"' <Project>.uproject  # Enabled omitted ⇒ true
jq -r '.TargetPlatforms[]?' <Project>.uproject                    # if pinned
```

## 2. Resolve the engine install & compare versions

```sh
# Resolution order: explicit env/studio config, GUID registration (§1), then
# conventional roots. NEVER just assume "C:\Program Files\Epic Games\UE_5.x".
echo "$UE_ROOT"
ls -d /opt/UnrealEngine "/mnt/c/Program Files/Epic Games"/UE_5.* \
      "/Users/Shared/Epic Games"/UE_5.* /Users/Shared/UnrealEngine* 2>/dev/null  # +macOS launcher/source

# The AUTHORITATIVE engine version (JSON, ships with every engine):
jq -r '"\(.MajorVersion).\(.MinorVersion).\(.PatchVersion)"' \
  "$UE_ROOT/Engine/Build/Build.version"

# Last resort when Build.version is unreadable: the UE_X.Y path segment
echo "$UE_ROOT" | grep -oE 'UE_[0-9]+\.[0-9]+'

# Installed (launcher) build vs source build:
test -f "$UE_ROOT/Engine/Build/InstalledBuild.txt" \
  && echo "installed/launcher build (stable BuildId)" \
  || echo "source build (new BuildId per compile - plugin binaries NOT portable)"
```

If **no engine resolves at all** (every path above empty, `UE_ROOT` unset) - common on
a dev box that only syncs/edits and offloads builds to a container or build node - report
it as an **issue** ("no engine installed here - can't build/cook locally") and skip the
version compare below **and** the §4 BuildId check. It is not a project defect: name the
missing toolchain and where the build actually runs (e.g. the docker image / build node).

**Compare** `EngineAssociation` against `Build.version`:

- `5.6` project vs `5.6.x` engine → OK.
- **Any mismatch → WARN**, before anything else runs. Same major, newer minor
  (5.4 project, 5.6 engine): opening **and saving** re-saves assets **forward,
  one-way** - an older editor then can't read them. Rebuilding the *binaries* is
  reversible (recompile for 5.4 any time); the asset **re-save** is the one-way
  ratchet, so opening alone is safe until something saves. Different major:
  incompatible, stop.
- A sanity check some backends use is "same major ⇒ probably compatible" - treat
  that as the *floor*, not clearance: minor-version drift is exactly what triggers
  the one-way asset upgrade.

## 3. Validate project setup (the doctor checks)

```sh
PROJ_DIR="$(dirname <Project>.uproject)"
test -d "$PROJ_DIR/Source"  || echo "note: no Source/ - Blueprint-only project (no code targets)"
test -d "$PROJ_DIR/Content" || echo "WARN: no Content/ directory"
test -f "$PROJ_DIR/Config/DefaultEngine.ini" || echo "ISSUE: missing Config/DefaultEngine.ini"

# Build targets & their types - these are the names UBT accepts:
grep -H "TargetType\.[A-Za-z]*" "$PROJ_DIR"/Source/*.Target.cs
#   TargetType.Game / .Editor / .Server / .Client
#   e.g. MyGame.Target.cs -> "MyGame", MyGameEditor.Target.cs -> "MyGameEditor"
```

Report **issues** (missing `DefaultEngine.ini`, no engine found, unparseable
`.uproject`) separately from **warnings** (version mismatch, no `Source/`, no
`Content/`) - issues block a build, warnings need a human judgment call.

## 4. Plugin & BuildId hygiene

The engine silently refuses to load any DLL whose **BuildId** doesn't match the
executable's. Check when modules are "missing", Blueprints lose nodes, or the
editor demands a rebuild on open:

```sh
# BuildId of the engine's own binaries vs the project's & its plugins'
# (adjust the platform dir: Win64 / Linux / Mac)
jq -r '.BuildId' "$UE_ROOT/Engine/Binaries/Win64/UnrealEditor.modules"
jq -r '.BuildId' "$PROJ_DIR"/Binaries/Win64/*.modules 2>/dev/null
jq -r '.BuildId' "$PROJ_DIR"/Plugins/*/Binaries/Win64/*.modules 2>/dev/null
```

- **No `.modules` anywhere** → the project has never been compiled on this machine (a
  freshly-synced workspace, or one that builds in a container / on a build node). Report
  it plainly - *"no local binaries yet; the first build compiles from source"* - not as a
  mismatch. There is nothing to compare until something is built here.
- All equal → binaries load. Any difference → that module is silently dropped (or
  the *"modules ... built with a different engine version. Rebuild?"* prompt).
- **Installed builds**: stable BuildId per engine version - Fab/Marketplace binary
  plugins for 5.6 work on every 5.6 install.
- **Source builds**: new random BuildId per compile - every plugin must be
  recompiled per engine build. On Perforce teams, UGS "Precompiled Binaries" exists
  precisely to sync a matching set without compiling.

## 5. DDC & ignore hygiene

```sh
# Where is the DerivedDataCache coming from? (cold cache = hours of shader compiles)
grep -A5 "DerivedDataBackendGraph" "$PROJ_DIR/Config/DefaultEngine.ini" 2>/dev/null
env | grep -i -E "UE-(Shared|Local)DataCachePath"
du -sh "$PROJ_DIR/DerivedDataCache" 2>/dev/null    # local project DDC, if any

# Ignore hygiene: generated dirs must not be reconciled into the depot.
# The perforce plugin's p4-workflows §9 ships the preset -
#   Binaries/ Intermediate/ Saved/ DerivedDataCache/ .vs/
# Needs a reachable server; if p4 is down, fall back to the local config:
echo "P4IGNORE=$P4IGNORE"; ls -a "$PROJ_DIR" | grep -i p4ignore   # env var + committed ignore file
p4 ignores -i "$PROJ_DIR/Intermediate/foo.tmp" 2>/dev/null   # (live server) would p4 skip it?
```

- Empty/local-only DDC on a build node ⇒ every cook pays full shader compilation.
  Recommend a warm or shared DDC (see `unreal-build` §6) rather than more hardware.
- Generated dirs staged in `p4 reconcile` output ⇒ missing P4IGNORE - cross-ref the
  perforce plugin's presets; don't restate them here.
- Caveat from that skill: don't blanket-ignore `Binaries/` at studios that check
  prebuilt editor binaries into the depot (the UGS pattern) - ask first.

## 6. Environment checks - editor running & Windows MAX_PATH

```sh
# Editor running? (it locks module DLLs - builds will fail; PIE also holds assets)
pgrep -fl UnrealEditor                      # Linux/Mac
tasklist | findstr /i UnrealEditor          # Windows cmd
powershell -c 'Get-Process -Name "UnrealEditor*"'   # PowerShell
```

Report it; **never kill the editor yourself** - unsaved work dies with it.

**Windows MAX_PATH (260 chars)** - UE nests deep `Intermediate/` and `Saved/Cooked/`
paths; long project roots push past the limit and fail with misleading
file-not-found / cannot-create errors:

```sh
# Longest paths in the generated trees (run from the project root):
find Intermediate Saved -type f 2>/dev/null | awk '{ print length, $0 }' | sort -rn | head -5
```

Root path + longest relative path ≳ 260 on Windows ⇒ diagnose MAX_PATH - the tell is
`GetLastError=206` / *"The filename or extension is too long"* / a SavePackage
*"Could not create file"*, which masquerades as a disk/permission error. **Count the
failing path first**: if it's under 260 chars it isn't MAX_PATH - suspect a longer
intermediate/temp path or another cause. Fixes, most reliable first: **shorten the
project root** (`C:\P\<Proj>` beats `C:\Users\name\Documents\Unreal Projects\<Proj>`);
shorten asset/dir names on the worst offenders; and only as best-effort, enable Windows
long paths (`LongPathsEnabled`) - it needs longPathAware manifests and much of the UE /
third-party toolchain isn't, so the flag alone often won't fix a cook.

## 7. Cook/build log diagnosis

Logs to look for: the project's `Saved/Logs/*.log`, and whatever file the build
wrapper `tee`'d UAT output into (ButterStack's build script writes
`cook_output_<build>.log`). Parse the newest one relevant to the question.

**The grammar** (each line is `[YYYY.MM.DD-HH.MM.SS:mmm][frame]Channel: Verbosity: message`):

| Channel | Line pattern | Meaning |
|---|---|---|
| `LogCook` | **5.6:** `Cooked packages <N> Packages Remain <M> Total <T>` (a running tally) · **older:** `Cooking <path>` · `Cooked <N> packages` | cook progress |
| `LogCook` | **5.6 summary:** `Packages Cooked: <N>, ... Total Packages: <T>` then `Done!` · `Cook Diagnostics: ... VirtualMemory=<N>MiB` | final totals + cook memory |
| `LogSavePackage` / `LogCookStats` | `Finished SavePackage <path>` · `SavePackageTimeSec=<t>` | cooked asset written / save time |
| `LogShaderCompilers` | `Using <N> local workers` · **`FShaderJobCache stats ... cache hits <n> (<x>%), DDC hits <m> (<y>%)`** · **older:** `Compiling <N> shaders` · `[i/N]` | shader workers + **the real cache-hit metric** |
| `LogZenServiceInstance` / `LogZenStore` / `LogDerivedDataCache` | **5.5+:** `ZenLocal: Using ZenServer HTTP service ...` · `Performance: Latency=<t>ms` · **pre-Zen only:** `... Hit Rate: <NN.N>%` | DDC backend (5.5+ is **ZenServer**) |
| `LogPakFile` | `Creating pak file` · `Created pak file ... size <N>` · `Adding <path> to pak` | packaging |
| (any channel) | `Error:` / `Fatal:` · `LogInit: Display: Success - <N> error(s), <M> warning(s)` | errors / the run's success summary line |
| (any channel) | `Warning:` | warnings |

> ⚠ **Version-verified (real UE 5.6.1 cook, 2026-07):** 5.5+ moved DDC to **ZenServer**, so
> there is **no `DDC Hit Rate: NN.N%` line** - read cache effectiveness from the
> `LogShaderCompilers: ... FShaderJobCache stats` line instead (`cache hits X%` + `DDC hits
> Y%`; low % ⇒ cold, ≈0 real compile work when both high). And 5.6 reports cook progress as
> a `Cooked packages N ... Total T` tally, **not** per-asset `Cooking <path>`. ButterStack's
> `parse_cook_log.py` patterns (`Cooking (.+)`, `Hit Rate:`) are **pre-Zen and match nothing
> in 5.6** - fix both together.

Asset type is inferable from path conventions: `T_*`/`/Textures/` = Texture,
`SM_*` = StaticMesh, `SK_*` = SkeletalMesh, `M_*`/`/Materials/` = Material,
`BP_*`/`/Blueprints/` = Blueprint, `DT_*` = DataTable, `W_*`/`/Widgets/` = Widget,
`A_*`/`/Animations/` = Animation, `/Sound/`·`/Audio/` = SoundWave,
`P_*`/`/Particles/` = ParticleSystem, `.umap` = Level. (Matches ButterStack's
`parse_cook_log.py` inference table - extend it there and here together.)

**Triage sequence** (fix the FIRST error; later ones usually cascade from it):

```sh
grep -n -m 5 -E "Error:|Fatal:" <log>          # first errors, with line numbers
grep -c "Warning:" <log>                        # warning volume
grep -B2 -A5 -m 1 "Fatal:" <log>                # context around a fatal

# Metrics - verified against a real UE 5.6.1 cook (the pre-Zen greps match nothing in 5.6):
grep -E "FShaderJobCache stats|cache hits .*%|DDC hits .*%" <log> | tail -3   # 5.6 cache effectiveness (NOT "Hit Rate")
grep -E "Using [0-9]+ local workers|Compiling [0-9]+ shaders" <log>           # shader worker/job activity
grep -E "Packages Cooked:|Cooked packages [0-9]+ .*Total|LogCook: Display: Done!" <log> | tail -3   # cook totals
grep -E "LogInit: Display: Success - .* error|BUILD (SUCCESSFUL|FAILED)|ExitCode=" <log> | tail -3   # outcome
find <archive_dir> -name "*.pak" -exec du -ch {} + 2>/dev/null | tail -1       # PAK size (if packaged)
# pre-Zen UE / ButterStack parser only: grep "DDC Hit Rate[: ]+[0-9.]+" and "Compiling shader|Shader compiled"
```

Reading the numbers:

- **Cache cold** → in 5.6 read the `LogShaderCompilers: ... FShaderJobCache stats` line:
  low `cache hits %` **and** low `DDC hits %` (both near 0) ⇒ the run compiled shaders
  from scratch (the real Parrot 5.6 cook showed 22% cache + 60% DDC hits = *warm*). Cold is
  expected once per machine/engine version; recurring cold ⇒ the shared/Zen DDC isn't
  configured (§5). Don't kill a cook mid-shader-compile - you lose the warm-up you paid for.
  (Pre-Zen UE only: the `DDC Hit Rate ≈ 0%` line.)
- **High warning count, zero errors, cook "failed"** → the failure is usually in
  the UAT stage wrapper, not content - search for `AutomationTool exiting with` and
  `BUILD FAILED`.
- **Timestamps** (`[2026.01.15-10.30.45:123]`) - subtract across phase boundaries
  to attribute time: cook vs shaders vs pak. Name the dominant phase in your
  report.

## 8. Failure signatures - from error string to root cause

`ExitCode=0` does **not** end triage: on a *successful* run still report the DDC hit
rate and the dominant phase (a green build can hide a multi-hour cold-shader compile -
see the DDC-unreachable row). And when a log really is healthy, say **"no action"** -
don't manufacture findings. Otherwise map these distinctive strings straight to a cause
(fix the FIRST one; later errors usually cascade):

| Signature in the log | Root cause | Fix / next step |
|---|---|---|
| `UnrealBuildTool` + `fatal error: <Header>.h: No such file or directory`, or `unresolved external symbol` / `undefined reference` to engine types | the module owning those types isn't in the consumer's `.Build.cs` dependency list | add it to `PublicDependencyModuleNames` (types used in your public headers) or `PrivateDependencyModuleNames` in that module's `*.Build.cs`, then rebuild |
| `UnrealBuildTool: ... Could not find definition for module 'X'` | the **inverse** of the above - `X` *is* referenced but can't be resolved: a typo, or a plugin/module that isn't present/enabled | correct the module name, or enable the plugin that provides `X` - do **not** just add it as a dependency |
| `LogModuleManager: ... missing or built with a different engine version` · *"Would you like to rebuild them now?"* · `.dylib`/`.dll ... built for engine version A, running B` | BuildId / `.modules` mismatch - go to §2 (version) + §4 (BuildId) | resolve the version mismatch **first**; do **not** blind-accept the rebuild prompt - a forward rebuild + save upgrades assets one-way |
| `LogPluginManager: Error: Plugin 'X' failed to load because module 'Y' could not be found ... consider disabling the plugin` (headless `-unattended`/`-skipcompile`; **no** "Rebuild?" prompt) | the **headless face of the same §2/§4 version/BuildId mismatch** - the module usually *exists* but was built for a different engine version, so the engine **silently dropped** it (verified: UE 5.8 running a 5.6-built Parrot, 2026-07). Only if §2 (EngineAssociation vs running engine) **and** §4 (`.modules` BuildId) *both* come back clean is the plugin genuinely absent/never-built | do **NOT** disable the plugin - the log's own suggestion is the trap. Run the matching engine, or *deliberately* rebuild for the running one (forward rebuild + save re-saves assets one-way - §2) |
| Cook: `GetLastError=206` · *"The filename or extension is too long"* · SavePackage *"Could not create file ..."* | Windows **MAX_PATH** (260) - see §6 | shorten the project root (only reliable fix); *count the failing path first* - under 260 ⇒ it's something else |
| `LogDerivedDataCache: Warning: ... unreachable ... falling back to Local` (usually with a later `Hit Rate: 0.x%`) | shared DDC backend down ⇒ every shader recompiled from source | restore DDC connectivity (DNS/firewall/service) before the next cook; this build's *output* is fine - don't re-run it, and don't kill a cook mid-compile |
| `LogUObjectGlobals`/`LogLinker`: *"Could not find file for package"* · *"Failed to load '<pkg>'"* · a dangling object-property reference, then `Can't cook <asset>` | a referenced content asset is missing from the workspace | on a Perforce team this is usually unsubmitted or unsynced - `p4 have <path>` (synced?), `p4 files <path>` (in depot at all?), `p4 opened` (an unsubmitted add?) - *then* hand the fix to the perforce plugin, or clear/repoint the reference via `unreal-editor-scripting` |

**Exit codes** name *which stage* failed; always pair the code with the first
`Error:`/`Fatal:` line, which names *why*: AutomationTool `0` = success, `25` =
`Error_UnknownCookFailure` (a cook commandlet errored - read the `LogCook: Error:` above
it, don't stop at the code); UnrealBuildTool `CompilationResult` (verified on real UE
5.6/5.8) `6` = `OtherCompilationError` (compile/link failed, or an illegal build-setting
change), `8` = `RulesError` (a bad `.Build.cs`/`.Target.cs` - e.g. a **typo'd or absent
module** in a dependency list, per the "Could not find definition for module" row above).

## Example - a filled doctor briefing

> **Doctor: MyGame @ /ws/MyGame - engine mismatch, otherwise healthy**
> - Project: `MyGame.uproject`, EngineAssociation **5.4** (version string -
>   launcher build expected)
> - Engine found: `$UE_ROOT=/opt/UE_5.6` → Build.version **5.6.1** (source build:
>   no InstalledBuild.txt) - **WARN: 5.4 project vs 5.6 engine - opening and
>   *saving* upgrades assets one-way; teammates on 5.4 lose access. Gate this.**
> - Setup: `Source/` ✓ (targets: MyGame=Game, MyGameEditor=Editor), `Content/` ✓,
>   `Config/DefaultEngine.ini` ✓
> - BuildId: engine `abc123...` vs `Plugins/FancyFX` `def456...` - **plugin will be
>   silently dropped; needs a rebuild against this engine**
> - Hygiene: no P4IGNORE found and `Intermediate/` reconciles as 1,400 adds -
>   recommend the perforce plugin's preset
> - Editor: not running · MAX_PATH: longest generated path 212 chars - OK

(Shape and thresholds from ButterStack's production doctor; numbers illustrative.)

## Caveats

- **Version-compatibility judgment is deliberately conservative.** "Same major
  version" passing a compatibility check does not make a minor-version mismatch
  safe for assets - always surface the one-way-upgrade consequence and let the
  human decide.
- **Log-derived counts are approximations** - grep-counting `Cooking|Cooked|
  SavePackage` lines over- or under-counts depending on log verbosity. Fine for
  trends and triage; don't present them as exact inventories.
- **`reg query` / `Install.ini` GUID resolution is Windows/Linux-specific** - on a
  machine that never registered the source build, a GUID resolves to nothing; the
  fix is registering the build there, not editing the `.uproject` on a whim.
- This skill is **authored from ButterStack's production doctor and log parser**
  (validated on their Linux UE 5.6 build image) - targets UE 5.4-5.8; re-validate
  exact log phrasings on your engine version before automating against them.

## Notes

- Keep everything here read-only. If diagnosis reveals work (a rebuild, a DDC to
  configure, an ignore file to add, an asset to check out), hand off to
  `unreal-build`, `unreal-editor-scripting`, or the perforce plugin's
  `p4-workflows` - and re-confirm with the user before mutating.
