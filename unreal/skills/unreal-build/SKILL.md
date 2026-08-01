---
name: unreal-build
description: >
  Gated Unreal Engine build playbooks - UBT compiles (Build.bat/Build.sh
  <Target> <Platform> <Config> -WaitMutex), RunUAT BuildCookRun in FAST_COOK
  tracer and full cook/stage/pak/archive forms, the full parameter table,
  platform/config matrix, editor-must-be-closed preflight, and DDC warming.
  Use whenever actually compiling, cooking, or packaging an Unreal project.
  EVERY command here is expensive (minutes to hours) - show the exact command
  plus estimated cost and get confirmation before running. For read-only
  diagnosis use `unreal-observe`; for editor automation use
  `unreal-editor-scripting`.
---

# Unreal Build, Cook & Package

Concrete, copy-pasteable build playbooks. Placeholders use `<ANGLE_BRACKETS>`;
`$UE_ROOT` is the engine install resolved by the `unreal-observe` doctor (§2) -
resolve it first, never guess it.

**Everything in this skill is gated.** A cook/package monopolizes the machine for
minutes-to-hours. Before running anything: show the user the exact command line
you intend to run and a cost estimate (§7), and wait for confirmation - the same
show-then-confirm pattern the jenkins agent uses for triggering builds. Prefer the
cheapest command that answers the question: an existing log (`unreal-observe` §7)
beats a re-cook; a FAST_COOK tracer (§2) beats a full pipeline (§3).

---

## 0. Preflight - run every time, before any build

1. **Doctor** - `unreal-observe` §1-§3: project found, engine resolved,
   `EngineAssociation` vs `Build.version` match (a mismatch here makes every later
   error misleading), targets known from `Source/*.Target.cs`.
2. **Editor must be closed.** A running editor locks the module DLLs; the build
   fails or half-succeeds. `pgrep -fl UnrealEditor` /
   `tasklist | findstr /i UnrealEditor`. Ask the user to close it - don't kill it.
3. **Always pass `-unattended -nop4 -utf8output` to UAT.** `-unattended` so nothing
   blocks on a prompt; `-nop4` so UAT never drives Perforce itself (you manage p4
   explicitly, per the perforce plugin's discipline); `-utf8output` so the log
   parses cleanly.
4. **Capture the log**: pipe through `tee <output>/cook_output_<id>.log` - the
   metrics and triage in `unreal-observe` §7 read from it.

## 1. Invocation forms - Windows vs Linux/Mac

The studio loop is Windows; build nodes are often Linux. Same tools, different
wrappers - emit the form matching the host:

```sh
# UAT (the pipeline driver)
"%UE_ROOT%\Engine\Build\BatchFiles\RunUAT.bat"  BuildCookRun <args>     # Windows
"$UE_ROOT/Engine/Build/BatchFiles/RunUAT.sh"    BuildCookRun <args>     # Linux/Mac

# UBT (compile only)
"%UE_ROOT%\Engine\Build\BatchFiles\Build.bat"        <Target> Win64 <Config> <args>   # Windows
"$UE_ROOT/Engine/Build/BatchFiles/Linux/Build.sh"    <Target> Linux <Config> <args>   # Linux
"$UE_ROOT/Engine/Build/BatchFiles/Mac/Build.sh"      <Target> Mac   <Config> <args>   # Mac
```

## 2. FAST_COOK tracer - the cheap first probe

Cook-only, single map, incremental, no compile - proves the content pipeline works
in minutes instead of committing to a full build (this is ButterStack's production
"tracer bullet" mode):

```sh
"$UE_ROOT/Engine/Build/BatchFiles/RunUAT.sh" BuildCookRun \
  -project="<abs>/<Project>.uproject" \
  -platform=<Platform> -clientconfig=Development \
  -cook -iterate -FastCook -skipcompile \
  -map=/Game/<Maps>/<Level> \
  -unattended -nop4 -utf8output \
  2>&1 | tee <out>/cook_output_<id>.log
```

- `-iterate` = incremental (only re-cook what changed); `-FastCook` skips
  optimization passes; `-skipcompile` uses existing binaries (fails if the target
  was never built - then you need §5 first).
- `-map=` takes the **content path**, not the filesystem path. Auto-derive it:

```sh
# /ws/MyGame/Content/Maps/Arena.umap  ->  /Game/Maps/Arena
find "<proj_dir>/Content" -name "*.umap" | head -1 \
  | sed "s|<proj_dir>/Content|/Game|; s|\.umap$||"
```

- Without `-map=`, add `-allmaps` (cooks everything - much slower).

## 3. Full pipeline - build + cook + stage + pak + archive

The ship path. Compiles code, cooks all content, stages, packs PAKs, and copies
the result out:

```sh
"$UE_ROOT/Engine/Build/BatchFiles/RunUAT.sh" BuildCookRun \
  -project="<abs>/<Project>.uproject" \
  -platform=<Platform> -clientconfig=<Config> \
  -build -cook -allmaps -stage -pak \
  -archive -archivedirectory="<abs_output_dir>" \
  -unattended -nop4 -utf8output \
  2>&1 | tee <out>/build_output_<id>.log
```

For a **distribution/Steam** build add: `-compressed` (smaller PAKs), `-prereqs`
(bundle the prerequisites installer), `-distribution` (strip development
features), `-nodebuginfo` (no PDBs) - and use `-clientconfig=Shipping`.

## 4. BuildCookRun parameter table

| Parameter | Description |
|---|---|
| `-project=` | absolute path to the `.uproject` |
| `-platform=` | target platform (`Win64`, `Linux`, `Mac`, `Android`, `iOS`) |
| `-clientconfig=` | build configuration (`Debug`, `DebugGame`, `Development`, `Test`, `Shipping`) |
| `-build` | compile game code (omit to reuse existing binaries) |
| `-cook` | cook content for the target platform |
| `-allmaps` / `-map=/Game/...` | cook everything vs specific map(s) |
| `-iterate` | incremental cook - only what changed |
| `-FastCook` | skip cook optimization passes (tracer builds) |
| `-skipcompile` | don't compile; use existing binaries |
| `-stage` | copy cooked output to the staging directory |
| `-pak` | pack staged content into `.pak` files |
| `-compressed` | compress PAK contents |
| `-prereqs` | include the prerequisites installer |
| `-distribution` | mark as distribution build (removes dev features) |
| `-nodebuginfo` | exclude debug symbols (smaller output) |
| `-archive` `-archivedirectory=` | copy the final build to a directory |
| `-unattended` | never block on an interactive prompt |
| `-nop4` | do not let UAT touch Perforce (**always**, agent-driven) |
| `-utf8output` | clean UTF-8 log output |

## 5. UBT compile - code only

Fast iteration on C++ without cooking (also the recovery when `-skipcompile` fails
because binaries don't exist yet). Target names come from `Source/*.Target.cs`
(`unreal-observe` §3):

```sh
# Windows                                             # Linux equivalent: Linux/Build.sh
"%UE_ROOT%\Engine\Build\BatchFiles\Build.bat" \
  <Target>Editor Win64 Development \
  -project="<abs>\<Project>.uproject" -WaitMutex
```

- `-WaitMutex` - wait for the UBT global mutex instead of failing when another
  build holds it (essential on shared build nodes). `-FromMsBuild` additionally
  formats errors for VS/MSBuild - optional, harmless.
- **Target × platform × config matrix**: targets are `<Project>` (Game),
  `<Project>Editor`, `<Project>Server`, `<Project>Client` - whichever `.Target.cs`
  files exist. Configs: `Debug`, `DebugGame`, `Development`, `Test`, `Shipping`.
  Editor targets build for the *host* platform only; `Shipping` + Editor don't mix.
- Verify like a headless agent: UBT **exit code** + the first `error` lines from
  the output - read and report them, don't just say "it failed".
- **Live Coding** (editor open, hot-patch) only covers function-body changes;
  header/struct/`UPROPERTY` changes need this full UBT rebuild - with the editor
  closed. See `unreal-editor-scripting` §6.

## 6. DDC warming - why the first cook is brutal

The DerivedDataCache stores compiled shaders/derived assets. **First cook on a
cold machine compiles every shader** - that's the hours-long `LogShaderCompilers`
phase with `DDC Hit Rate ≈ 0%`; a warm cache turns the same cook into minutes.

- Check where the DDC points before diagnosing "slow cook" (`unreal-observe` §5).
- Studios use a **shared DDC** (network path via `UE-SharedDataCachePath` /
  `DerivedDataBackendGraph` config) so one machine's work warms everyone. If the
  studio has one, plugging it in beats any hardware fix.
- A deliberate warm-up run (e.g. the §2 tracer with `-allmaps` overnight) is a
  legitimate, gated proposal for a fresh build node.
- **Never delete a shared/network DDC** (the `guard-unreal` hook hard-blocks it) -
  wiping a *local* DDC is allowed but costs a full re-cook; confirm first.

## 7. Cost expectations & reporting

Rough orders of magnitude for the confirmation prompt (state your host's reality
if a previous log exists - `unreal-observe` §7 timestamps give exact phase times):

| Action | Typical cost |
|---|---|
| UBT compile, incremental C++ change | ~1-5 min |
| UBT compile, clean target | ~10-40 min |
| FAST_COOK tracer (one map, warm DDC) | ~2-10 min |
| Full cook, **warm** DDC | ~10-60 min |
| Full cook, **cold** DDC | hours (shader compilation) |
| Full build+cook+stage+pak+archive | tens of minutes to hours |
| Full **engine** (source) rebuild | hours - always name it explicitly |

After a run, report what the log proves (same metrics ButterStack extracts):
exit code, cook time, **DDC hit rate**, shader count, cooked-asset count,
warnings/errors, and PAK/archive size - not just "done". Extraction commands:
`unreal-observe` §7.

## Validation status

Authored from ButterStack's **production build tooling** - their Jenkins-driven
`build-game.sh` (FAST_COOK vs full flag sets, run on a Linux UE 5.6 image), build
backend, and build-setup guide - targeting UE 5.4-5.8. Not yet re-validated live
by this plugin on every platform/version combination: treat exact flag behavior on
your engine version as verify-before-relying (especially `-FastCook` semantics,
which Epic documents sparsely), and expect console platforms (not covered here) to
need platform SDK setup this skill doesn't describe.
