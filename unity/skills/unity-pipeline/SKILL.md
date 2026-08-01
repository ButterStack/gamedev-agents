---
name: unity-pipeline
description: >
  The Unity 6 Pipeline live-Editor control surface, verified against a live
  Editor - the preconditions (Editor 6.0+, com.unity.pipeline installed, a
  RUNNING Editor: the server lives inside it, there is no batchmode Pipeline),
  the four-command state ladder (pipeline list / status / list / command), the
  140-tool surface by functional area, Unity's own server-side confirm/dry_run
  gates (400 + exit 6), the response envelope and the `unity command` exit-0
  trap (parse the payload, never the exit code), the nine *_status async
  pollers, warm Pipeline builds vs cold batchmode, and the MCP stdio server
  (16 clients, loopback only). Use when driving a running Unity 6 Editor -
  reading or mutating scenes, assets, settings, packages, or builds live - or
  when wiring up `unity mcp`. For batchmode build/test use `unity-build`; for
  the CLI itself use `unity-cli`; for the read-only doctor use `unity-observe`.
---

# Unity Pipeline - the live-Editor control surface

How an agent drives a **running** Unity 6 Editor over the Pipeline package's
local HTTP API - the Unity analog of the unreal agent's editor-scripting
surface, with one big difference: Unity ships its own server-side safety
gates, and the agent's job is to respect them, not re-invent them.

Everything here was **executed against a live Editor** (Windows 11, Unity CLI
`1.0.0-beta.2`, Editor `6000.3.20f1`, `com.unity.pipeline` `0.3.1-exp.1`,
2026-07-22) unless marked otherwise. The full tool dump came from
`unity list --format json`; tool names and description quotes are verbatim
from that output.

---

## 1. Preconditions - what must be true before any of this exists

1. **Editor 6.0 or later.** On 2022.3 `pipeline install` refuses with
   `Pipeline package requires Unity 6.0 or higher.` (exit 6) and leaves
   `Packages/manifest.json` untouched (`unity-cli` §8). Route on
   `ProjectVersion.txt` first (`unity-observe` §1-§2).
2. **`com.unity.pipeline` installed in the project.** `unity pipeline install`
   is a **gated** step - it mutates `Packages/manifest.json`, a tracked
   project change - and triggers an Editor recompile.
3. **A running Editor with the project open.** The Pipeline server lives
   *inside* the Editor process - **there is no batchmode Pipeline**. No
   Editor, no server, and nothing in this skill applies; the batchmode trio
   (`unity-build`) is the fallback.
4. **Sign-in is NOT required** (verified). `unity pipeline install` succeeded
   with `unity auth status` reporting "not signed in", on the machine ULF
   alone - the docs' `auth login` -> `pipeline install` ordering is not
   enforced. Do not send a user to the browser for this.
5. **Transport is loopback only.** Verified target:
   `{"host": "127.0.0.1", "port": 7800}`. Keep it that way (§9).

## 2. The state ladder - four commands, four different questions

Reach for the one that answers the question you actually have, in order:

```
$ unity pipeline list       # is the PACKAGE installed? works even on 2022.3 (exit 0)
Project        Path                   PID    Running  Pipeline  Version      Server Port  Server Reachable
Unity63Probe   C:\work\Unity63Probe   32852  true     true      0.3.1-exp.1  7800         true

$ unity status              # is an Editor CONNECTED? exit 6 when none
Port  State  Project                Version      PID
7800  ready  C:\work\Unity63Probe   6000.3.20f1  32852

$ unity list                # what TOOLS does it expose? exit 6 when no server
$ unity command <name>      # execute one (alias: cmd)
```

Degradation when no Editor is running (all verified): `pipeline list` still
works - it shows `Pipeline=true, Server Reachable=false` with an empty
`Server Port`; `unity status` exits 6 with a header-only table; `unity list`
exits 6 with `Error: No Unity Editor instances found with reachable Pipeline
servers.` and a hint pointing back at `pipeline list`. So `pipeline list` is
the diagnostic that never lies about *why* the others failed: package absent
vs Editor not running vs server unreachable.

Always add `--format json --no-banner --non-interactive` when parsing, as
everywhere else in this plugin.

## 3. The 140-tool surface, by functional area

`unity list` returned **140 tools**, all `group: "built-in"`, on
`com.unity.pipeline 0.3.1-exp.1`. Don't memorize the list - re-derive it with
`unity list --format json` (the package is experimental and will move) - but
know the map:

| Area | Representative tools |
|---|---|
| Scene + GameObject graph | `find_gameobjects`, `get_scene_hierarchy`, `create_gameobject`, `create_gameobjects`, `set_active`, `set_parent`, `set_transform`, `delete_gameobject`, `open_scene`, `save_scene`, `set_active_scene`, `list_open_scenes` |
| Components + serialization | `get_component_properties`, `get_serialized_fields`, `set_component_properties`, `set_serialized_field`, `add_component`, `remove_component`, `attach_script` |
| Assets + text files | `find_assets`, `create_asset`, `copy_asset`, `move_asset`, `rename_asset`, `delete_asset`, `import_asset`, `get_import_settings`, `set_import_settings`, `read_text_file`, `write_text_file`, `create_folder` |
| Prefabs | `create_prefab`, `create_prefab_variant`, `instantiate_prefab`, `apply_prefab_overrides`, `revert_prefab_overrides`, `save_prefab_contents`, `unpack_prefab` |
| Animation + Timeline | `create_animation_clip`, `create_animator_controller`, `add_animator_layer` / `_state` / `_transition` / `_parameter`, `set_animation_curve`, `remove_animation_curve`, `create_timeline`, `add_timeline_track` / `_clip`, `get_timeline` |
| Materials + shaders | `list_shaders`, `get_shader_properties`, `get_material_properties`, `set_material_properties` |
| Baking | `bake_lighting`, `bake_navmesh`, `bake_navmesh_surfaces`, `bake_occlusion_culling` + their `clear_` and `cancel_` counterparts + `set_lighting_settings`, `set_navmesh_settings` |
| Project settings | `get_` / `set_` pairs for `player`, `quality`, `graphics`, `physics`, `audio`, `time`, `input`, `build` settings and `tags_layers` |
| Packages (UPM) | `package_add`, `package_remove`, `package_resolve`, `package_search`, `package_list`, `package_status` |
| Build | `build`, `build_status`, `switch_build_target`, `switch_build_target_status`, `list_build_targets`, `list_build_profiles`, `add_scene_to_build`, `remove_scene_from_build` |
| Tests | `run_tests`, `list_tests`, `cancel_tests`, `test_status` |
| Editor lifecycle | `editor_play`, `editor_pause`, `editor_stop`, `editor_focus`, `editor_status`, `recompile`, `recompile_status`, `save_all`, `menu` |
| Capture + console | `screenshot`, `capture_game_view`, `capture_scene_view`, `get_console_logs`, `console`, `clear_console`, `get_performance_stats`, `search`, `get_selection`, `set_selection` |
| Scripting | `create_script`, `eval`, `eval_file` |

Two of these deserve a special flag: **`eval` and `eval_file` execute
arbitrary C# in the Editor process** ("Evaluate C# code dynamically using
Roslyn compiler") and take **no `confirm` parameter** - Unity's own gate
(§4) does not cover them. Treat any `eval` as a gated, show-then-confirm
action under the agent's rules, exactly like a destructive tool.

## 4. Unity's own confirm/dry_run convention - the heart of this surface

Unity has independently arrived at the same posture this plugin takes:
destructive tools refuse to run until the caller opts in explicitly.

- **29 tools take a `confirm` parameter** - the full list: `bake_lighting`,
  `bake_navmesh`, `bake_occlusion_culling`, `build`, `clear_baked_lighting`,
  `clear_navmesh`, `clear_occlusion_culling`, `copy_asset`,
  `create_animation_clip`, `create_animator_controller`, `create_asset`,
  `create_timeline`, `delete_asset`, `import_asset`, `package_add`,
  `package_remove`, `remove_animation_curve`, `set_audio_settings`,
  `set_build_settings`, `set_graphics_settings`, `set_input_settings`,
  `set_material_properties`, `set_physics_settings`, `set_player_settings`,
  `set_quality_settings`, `set_tags_layers`, `set_time_settings`,
  `switch_build_target`, `write_text_file`.
- **40 tools take a `dry_run` parameter** (all of the above except
  `switch_build_target`, plus the animator/timeline `add_*` tools,
  `move_asset`, `rename_asset`, `set_animation_curve`, `set_import_settings`,
  `set_lighting_settings`, `set_navmesh_settings`).
- 17 of the 29 say the gate outright in their description, e.g.
  `switch_build_target`: "Switch the active build target (destructive,
  long-running: triggers a full reimport + domain reload). Requires
  confirm=true."
- **The descriptions distinguish Undo-able from not.** `delete_gameobject` is
  "reversible via Undo"; `set_component_properties` is "one Undo step". The
  eight `set_*_settings` project-settings tools all end with "Not undoable
  via Ctrl+Z" (e.g. `set_quality_settings`: "Change QualitySettings. Requires
  confirm=true; use dry_run to preview. Not undoable via Ctrl+Z."). Quote the
  right one when explaining a refusal.

**The gate is enforced server-side** - it is not advisory, and the refusal is
loud (verified):

```
$ unity command clear_navmesh          # no confirm
Error: Pipeline server returned 400 Bad Request: Parameter Validation Failed.
Refusing to clear the NavMesh. Pass confirm=true (destructive, not undoable via Unity's Undo).
$ echo $?   # -> 6
```

**Agent rules, stated plainly:**

1. **Never pass `confirm=true` on the user's behalf.** A 400 refusal is Unity
   asking the same question this plugin's gates ask - surface the exact
   operation and its consequence (undoable or not, what it costs) and wait
   for explicit approval. Verified flag form: `--confirm true`
   (`unity command build --confirm true`).
2. **Prefer a `dry_run` pass first** on any tool that supports one - it is
   the Pipeline's built-in preview, the same discipline as `p4 -n`.
3. **Unity's gate is the floor, not the ceiling.** A tool without `confirm`
   (`eval`, `set_serialized_field`, `set_transform`, ...) is not thereby
   safe - the agent's own classify-and-gate rules still apply on top.

## 5. The response envelope - and the second exit-0 trap

A successful read, verbatim:

```
$ unity command get_tags_layers
Command           Success  Result
get_tags_layers   true     {"success":true,"group":"tags_layers","applied":false,"dryRun":false,
                            "requiresDomainReload":false,"requiresReimport":false,
                            "values":{"tags":[...],"layers":[...]},"message":"Read tags_layers settings."}
```

Inner envelope fields: `success`, `group`, `applied`, `dryRun`,
`requiresDomainReload`, `requiresReimport`, `values`, `message`. The ones
that matter for reporting: **`applied`** says whether anything actually
changed, and **`requiresDomainReload`** / **`requiresReimport`** say what it
will cost the Editor next.

**TRAP (verified):** `unity command` exits **0** when the *transport*
succeeded, even if the *tool* reported `"success": false`. Observed: an
invalid `set_quality_settings` call returned outer `Success=true`, inner
`"success":false`, message "No 'settings' object provided." - and **exit 0**.

That makes **two** distinct exit-code traps in this plugin:

1. batchmode `unity build` exits 0 on a failed build unless the
   execute-method exits non-zero (`unity-build` §2, §6);
2. `unity command` exits 0 on a failed tool call whose transport worked.

Same lesson both times: **parse the payload, never trust the exit code.**
And note the asymmetry - a *validation* failure (the §4 confirm gate)
surfaces as a 400 and exit `6`, while a *semantic* failure inside the tool
surfaces as exit `0` with `success:false`. Non-zero means read stderr; zero
means read the JSON.

## 6. Async tools - fire, then poll

Long-running operations return immediately and are tracked by **nine
`*_status` pollers**: `build_status`, `editor_status`,
`lighting_bake_status`, `navmesh_bake_status`, `occlusion_bake_status`,
`package_status`, `recompile_status`, `switch_build_target_status`,
`test_status`.

The convention, from the tool descriptions: the mutating call "Returns
immediately; poll `<x>_status`". Documented state sets include
`idle | switching | completed` (target switch), `idle | baking | completed`
(bakes), and `idle | triggered | compiling | completed | up_to_date`
(recompile). `switch_build_target_status` also returns `success` plus
`activeBuildTarget` - assert on that, not on time passing.

Specifics worth knowing:

- **The `attach_script` recompile dance** is documented in the tool itself:
  "If the type isn't compiled yet, returns a recoverable error: recompile,
  poll recompile_status, then retry." `create_script` has the same shape -
  the new type does not exist until a recompile completes, so the sequence
  is create -> `recompile` -> poll `recompile_status` -> `attach_script`.
- **`package_add` is async by default** (returns `in_progress`; poll
  `package_status`, states `idle | in_progress | completed | failed`) and a
  recompile/domain reload follows - poll `recompile_status` after it too. A
  `wait` parameter blocks until added instead.
- **`build_status` retains the full `BuildReport`** (files, packedAssets,
  buildSteps, errors, warnings) "until the next build" - so a just-finished
  build is inspectable after the fact.

## 7. Two ways to build on Unity 6 - choose deliberately

| | Batchmode (`unity build`) | Pipeline (`unity command build`) |
|---|---|---|
| Editor | cold - spawned per run, isolated | warm - the already-running Editor |
| Works on | 2022.3 **and** 6.x | Unity 6 + Pipeline + running Editor only |
| Startup cost | full Editor boot (+ import on cold `Library/`) | none - no startup, no domain reload |
| Side effects | none on anyone's session | mutates the Editor the developer is sitting in front of |
| Failure trap | exit-0 unless the execute-method exits honestly | exit-0 on `success:false` (§5) |
| Playbook | `unity-build` | `--confirm true`, then poll `build_status` (§6) |

**Default to batchmode for anything CI-shaped.** Reach for the Pipeline build
only when an Editor is already open and the user wants a fast iteration
loop - and say out loud that it runs inside their session. The Pipeline
`build` tool supports `dry_run` ("Use dry_run to validate without
building") - use it as the preview before asking for `confirm`.

## 8. Build preconditions - `list_build_targets`, not guesswork

`list_build_targets` reports **`isInstalled` per target** - the correct
precondition check before proposing any build or target switch. Verified on
the rig: only `StandaloneWindows` and `StandaloneWindows64` installed;
Android/iOS/WebGL etc. all report `isInstalled: false`. A missing target maps
directly onto a **gated** `unity install-modules` for that Editor version
(`unity-cli` §6) - name the download, confirm, then build.

Related: `list_build_profiles` - "List Build Profile assets in the project
(Unity 6 only). Returns feature_unavailable on earlier versions." - a
graceful degradation, not an error. And remember `switch_build_target` is one of the
most expensive tools on the surface: "destructive, long-running: triggers a
full reimport + domain reload" - gate it like a build, then poll
`switch_build_target_status`.

## 9. MCP - the stdio server and the loopback rule

The Pipeline package also fronts an MCP server:

```
unity mcp                                     # start the MCP stdio server
unity mcp --project-path <path>               # pin it to a project
unity mcp configure <client>                  # write that client's MCP config
unity mcp configure --list                    # supported clients
```

`unity mcp configure --list` is real and includes `claude-code` (verified):

```
Supported MCP clients:
  claude             Claude Desktop      %APPDATA%\Claude\claude_desktop_config.json
  claude-code        Claude Code CLI     (no file - delegation/manual)
  cursor, vscode, vscode-insiders, copilot-cli, windsurf, cline, codex, kiro,
  trae, openclaw, antigravity, zed, continue, inspect
```

16 clients. Note `claude-code` is listed as "delegation/manual" - `configure`
does **not** write a file for it; registration is manual (e.g. the user's own
`claude mcp add` flow).

**The loopback rule.** The MCP server is stdio and the Pipeline transport
underneath it is `127.0.0.1:7800` - an editor-control endpoint with no auth.
Same posture as the unreal agent's Remote Control rule: **never expose it
beyond the machine** - no `0.0.0.0`, no port-forwards, no "just for the
demo" tunnels. Anyone who can reach that port can run §3 against the user's
Editor, `eval` included.

**Not exercised:** actually starting the MCP server and driving it from a
client end-to-end. The command surface above is verified from the binary;
the runtime behavior of `unity mcp` is not - probe before promising
specifics.

## Validation status

Verified live (Windows 11, Unity CLI `1.0.0-beta.2`, Editor `6000.3.20f1`,
`com.unity.pipeline` `0.3.1-exp.1`, 2026-07-22): the preconditions incl. the
no-sign-in finding, the state ladder and its degradation modes, the 140-tool
dump (counts, confirm/dry_run lists, and every description quoted here are
verbatim from `unity list --format json`), the server-side confirm gate
(400 + exit 6), the response envelope and the `unity command` exit-0 trap,
`list_build_targets`/`isInstalled`, and the `unity mcp configure --list`
client table. **Not verified:** the MCP server end-to-end (§9); parameter
passing beyond the `--confirm true` flag form - check
`unity command --help` for the full argument syntax on your CLI version; and
most of the 140 tools individually - the package is experimental
(`0.3.1-exp.1`) and the surface will move, so re-run `unity list` rather
than trusting this file's inventory on a newer package.
