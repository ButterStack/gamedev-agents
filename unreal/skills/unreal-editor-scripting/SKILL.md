---
name: unreal-editor-scripting
description: >
  First-party Unreal editor automation for an AI agent - headless Python
  (-run=pythonscript), the Remote Control API (localhost:30010), the Automation
  test framework (Automation RunTests), and Live Coding; the C++-heavy /
  thin-Blueprint strategy; the Perforce-disciplined binary-asset loop
  (checkout -> modify -> save -> submit); the headless verification-feedback
  model (build exit + parsed errors, test summaries, PIE screenshots, Remote
  Control GETs); and the optional, version-gated MCP servers (Epic's UE 5.8
  built-in + third-party). Use when creating/modifying assets, setting
  properties, spawning actors, running in-editor tests, or verifying editor
  state from script. For compiles/cooks use `unreal-build`; for read-only
  diagnosis use `unreal-observe`.
---

# Unreal Editor Scripting - the first-party AI surface

How an agent drives the Unreal editor **without a human at the GUI**, built
entirely on Epic-maintained automation (the ButterStack "thin first-party bridge"
design): dependency-light, headless-capable, and reusable in CI. MCP servers are
an optional accelerant (§8), never a dependency.

Prerequisites: the **Python Editor Script Plugin** enabled in the project (ships
with UE); **Remote Control API** plugin for §4. Resolve `$UE_ROOT` and the project
via the `unreal-observe` doctor first.

---

## 1. The surfaces at a glance

| Surface | What it gives you | Invocation |
|---|---|---|
| **C++ + UBT / Live Coding** | gameplay logic as *text* - your strength - compiled | `unreal-build` §5; Live Coding §6 |
| **Python Editor Scripting** (`unreal` module) | create/modify assets, set class defaults, spawn actors, import, save - deterministic scripts | headless `-run=pythonscript` (§2) |
| **Remote Control API** | live GET/SET property + CALL function on a **running** editor or packaged build | HTTP `localhost:30010` (§4) |
| **Automation framework** | headless functional/unit tests + screenshots | `-ExecCmds="Automation RunTests ..."` (§5) |
| **UAT `BuildCookRun`** | package the ship build | `unreal-build` §3 |
| **Logs + screenshots** | build/runtime errors (text), PIE `HighResShot` PNGs (read the image) | `Saved/Logs/`, `Saved/Screenshots/` (§7) |

## 2. Headless Python - the workhorse

```sh
# Windows
"%UE_ROOT%\Engine\Binaries\Win64\UnrealEditor-Cmd.exe" "<abs>\<Project>.uproject" \
  -run=pythonscript -script="<abs>\tools\edit.py" -unattended -nopause -nullrhi

# Linux / Mac (binaries dir: Linux/ or Mac/)
"$UE_ROOT/Engine/Binaries/Linux/UnrealEditor-Cmd" "<abs>/<Project>.uproject" \
  -run=pythonscript -script="<abs>/tools/edit.py" -unattended -nopause -nullrhi
```

- Prefer **`UnrealEditor-Cmd`** (console subsystem) over `UnrealEditor` for
  anything headless. Useful extra flags: `-nosplash -stdout -fullstdoutlogoutput`
  (unbuffered log to stdout), `-log` (log window on Windows).
- **`-nullrhi` is not a magic headless switch** - it disables the RHI so no GPU is
  needed, but some code paths still exercise rendering assumptions and timing can
  differ. Use it for logic/asset work; drop it for anything visual (§7).
- Write the edit as a **small, per-task script** - deterministic and reviewable -
  ideally calling a committed helper library that wraps the awkward `unreal` API
  (`create_blueprint(parent_cpp_class, path)`, `set_cdo_defaults(bp, {...})`,
  `add_to_level(map, bp, transform)`, `set_datatable_row(...)`, `save(asset)`).
  Far more reliable than free-form node-graph poking.
- The script's stdout + the log tail are your result - read them; a Python
  exception in the script does not always make the process exit non-zero, so check
  the log for `LogPython: Error`.

## 3. The binary-asset loop - checkout → modify → save → submit

UE content is binary `.uasset`/`.umap` (unmergeable, typically `binary+l`
exclusive-checkout). **The order is the discipline** - wrong order means the tool
writes a read-only file or hits a lock conflict:

```sh
# 0. Who else has it? (perforce plugin, p4-observe §3 - otherLock means STOP and ask)
p4 -ztag fstat //<depot>/<path>/Arena.umap

# 1. CHECKOUT before any tool touches it
p4 edit -c <CL> //<depot>/<path>/Arena.umap        # existing asset
p4 add  -c <CL> <new_asset_path>                    # brand-new asset (after creation)

# 2. MODIFY via the bridge (headless Python §2, or Remote Control §4 on a running editor)
# 3. SAVE from the same script (unreal.EditorAssetLibrary.save_asset / save_loaded_asset)

# 4. VERIFY (§7), show the changelist, then SUBMIT only on confirmation
p4 opened -c <CL> && p4 submit -c <CL>
```

- C++ files are text → normal `p4 edit`, no exclusivity worries.
- One concern per changelist; never obliterate/rewrite history.
- The perforce plugin owns the p4 side (safe write cycle, shelving, lock
  etiquette, the UE typemap/P4IGNORE presets) - `p4-workflows` §0/§2/§7/§9.
  Cross-reference it; don't improvise p4 sequences here.

## 4. Remote Control API - live state on a running editor

Enable *Edit ▸ Plugins ▸ Remote Control API*. HTTP on `localhost:30010`, WebSocket
on `30020`. **Loopback, no auth, by design - never expose beyond localhost** (no
`0.0.0.0`, no port-forwards). If 30010 doesn't respond with the plugin enabled,
run `WebControl.StartServer` in the editor console.

```sh
curl -s http://localhost:30010/remote/info          # liveness + route list

# Read a property (READ_ACCESS): PUT /remote/object/property
curl -s -X PUT http://localhost:30010/remote/object/property \
  -H "Content-Type: application/json" -d '{
    "objectPath": "/Game/Maps/Arena.Arena:PersistentLevel.PointLight_1.LightComponent0",
    "access": "READ_ACCESS",
    "propertyName": "Intensity"
  }'

# Write a property (WRITE_ACCESS) - this MUTATES the level: p4 edit the .umap first (§3)
curl -s -X PUT http://localhost:30010/remote/object/property \
  -H "Content-Type: application/json" -d '{
    "objectPath": "<object_path>",
    "access": "WRITE_ACCESS",
    "propertyName": "Intensity",
    "propertyValue": { "Intensity": 5000.0 }
  }'

# Call a function: PUT /remote/object/call
curl -s -X PUT http://localhost:30010/remote/object/call \
  -H "Content-Type: application/json" -d '{
    "objectPath": "<object_path>",
    "functionName": "SetIntensity",
    "parameters": { "NewIntensity": 5000.0 }
  }'
```

- `objectPath` is the full editor object path
  (`/Game/<Map>.<Map>:PersistentLevel.<Actor>.<Component>`).
- RC writes change the **live editor state**; they still need a save + the §3
  checkout discipline to become a submittable asset change.
- Exact route/payload shapes are authored from Epic's docs - verify against your
  engine version's `/remote/info` before scripting against them.

## 5. Automation framework - headless tests

```sh
"$UE_ROOT/Engine/Binaries/Linux/UnrealEditor-Cmd" "<abs>/<Project>.uproject" \
  -ExecCmds="Automation RunTests <filter>;Quit" \
  -unattended -nullrhi -nopause -log \
  -ReportExportPath="<abs>/reports"
```

- `<filter>` is a test-name prefix (e.g. your project name, or
  `Project.Functional`). `;Quit` makes the run terminate - don't forget it.
- Results land as JSON/HTML under `-ReportExportPath` - parse the JSON summary for
  pass/fail counts and failing test names; also grep the log for
  `LogAutomationController`.
- Screenshot-comparison tests need a real RHI (drop `-nullrhi`, needs a GPU).

## 6. Live Coding - fast C++ iteration, with a hard limit

With the editor open, Live Coding (Ctrl+Alt+F11) hot-patches **function-body
changes** in seconds. **It cannot apply header/struct/`UPROPERTY`/reflection
changes** - those need a full UBT rebuild with the editor closed
(`unreal-build` §5). When an edit touches a header, don't fight it: fall back to
the full rebuild automatically and say why.

## 7. Verification feedback - how a headless agent "sees"

Close the loop with observed evidence before any submit:

- **Build**: UBT/UAT **exit code** + the parsed error lines from the log - the
  first `Error:`/`Fatal:` line, not the last.
- **Tests**: the Automation results summary (§5) - pass/fail counts + failing
  names.
- **Runtime/visual**: a PIE run with `-ExecCmds="HighResShot 1920x1080"` writes a
  PNG under `Saved/Screenshots/` - **read the image** and describe what it shows.
  Visual checks need a GPU; on a `-nullrhi` node, stick to logic checks.
- **State assertions**: Remote Control `READ_ACCESS` GET (§4) to confirm an exact
  property value landed.

Report what you *observed* (exit code, test counts, property value, what the
screenshot shows) - not merely what you executed.

## 8. MCP servers - optional, version-gated accelerants

First-party CLI automation above is the dependency-free baseline. MCP servers can
accelerate interactive editor work *if present and version-matched* - treat them
exactly the way the jenkins agent treats its optional MCP plugin: use it when
detected, never require it, never install it unasked.

- **Epic's built-in MCP server (UE 5.8+, experimental)** - `127.0.0.1:8000/mcp`,
  loopback, no auth, requires an editor restart to pick up new tools. First-party,
  so no recompile concern - but experimental: expect churn between 5.8 point
  releases.
- **Third-party servers** - chongdashu/unreal-mcp (UE 5.5-5.7),
  remiphilippe/mcp-unreal (5.7), StraySpark (5.7/5.8), UnrealClaude (5.7). Every
  one ships an engine-side plugin that **recompiles per engine version** (and per
  *build* on source engines - BuildId, see the agent's version-matching rules).
  Version-gate hard: a 5.7 plugin on a 5.8 engine simply won't load.
- Their common weak spot is **Blueprint-graph tools** - the buggiest surface in
  all of them, which is exactly why it's out of scope here (§9).

## 9. Out of scope: Blueprint node-graph authoring

Authoring Blueprint graphs from script is only partially supported by the Python
API, is the buggiest capability in every MCP server, and Epic is sunsetting
Blueprints in UE6 in favor of **Verse** - so it's out of scope by design, not
omission. The strategy that sidesteps it (**C++-heavy / thin-Blueprint**):

- **Logic in C++** (`UCLASS`/`UFUNCTION(BlueprintCallable)`/`UPROPERTY`) - written
  as text, compiled by UBT/Live Coding.
- **Blueprints stay thin**: subclass the C++ class, set CDO defaults, place in
  levels - the things Python *does* do well (§2).
- Net: ~all logic as C++ text, ~all composition as Python scripts; hand-wiring
  graph nodes is the exception. If a task genuinely requires graph automation,
  say so and stop - a version-matched third-party MCP (§8) is the escape hatch,
  chosen by the user.

## Validation status

Authored from ButterStack's Claude⇄UE bridge design (built for a Windows UE 5.8
studio loop) and Epic's documentation, targeting UE 5.4-5.8. The headless-Python /
Remote Control / Automation invocation shapes are Epic-stable, but exact payloads
and log phrasing vary by version - probe (`/remote/info`, a trivial
`-run=pythonscript` hello) before scripting against them on a new engine. Verse
and UE6 are deliberately not covered.
