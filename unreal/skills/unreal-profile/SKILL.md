---
name: unreal-profile
description: >
  Runtime performance profiling for Unreal Engine (UE 5.x) - capturing and
  reading Unreal Insights traces (trace channels: counters/stats/loadtime/task),
  stat and obj console-command triage (obj list, obj refs shortest, LogGarbage
  Verbose, stat unit/gpu/fps), UObject-count and GC-cost budgets, GPU-side
  diagnosis (GPU Profiler 2.0, WinPIX, Nanite raster/shading-bin heuristics),
  and a checklist of recurring perf anti-patterns. Use for hitches, frame time,
  FPS, GC pauses, memory counters, and load-time questions about a RUNNING
  game/editor session. For static cook/build-log triage use `unreal-observe`
  §7-§8; to compile/cook use `unreal-build`; to automate the editor use
  `unreal-editor-scripting`.
---

# Unreal Runtime Performance Profiling

**Reading a capture is free; taking one is gated.** Parsing an existing
`.utrace`, a saved `stat` readout, or `obj list` output someone already captured
is read-only - do it freely. *Launching* a build/editor with tracing enabled
monopolizes the machine like a build and writes a `.utrace` that grows large
(hundreds of MB to multi-GB for long sessions, more with `stats` on) - show the
exact launch line **plus the disk cost** and wait for confirmation, the same
show-then-confirm pattern as `unreal-build`. Placeholders use
`<ANGLE_BRACKETS>`.

> ⚠ **Spelling-confidence note:** the *methodology, heuristics, and thresholds*
> in this skill are high-confidence; several exact flag/command **spellings** are
> the weak link and are marked *(verify spelling)* - check them against your
> engine version before automating. Nothing in this skill carries the
> `⚠ Version-verified` stamp the sibling skills use for empirically confirmed
> facts.

---

## 1. The profiling launch line (gated)

Launch the packaged game (or `UnrealEditor <Project>.uproject -game`) with
tracing on. Gate it: name the session length, the `.utrace` disk cost, and the
hardware it runs on (§9) before running.

```sh
<GameBinary> \
  -trace=default,counters,loadtime,task \   # channels (§2); add 'stats' only when needed - high overhead. 'task' shows what a thread/task is waiting on (verify spelling: task vs tasks)
  -statnamedevents \                        # named-event labels on the CPU timeline - much more granular scopes
  -ExecCmds="stat unitgraph, stat fps" \    # frame-history graph + FPS on screen from boot
  -NoVerifyGC \                             # skip dev-build GC verification passes - overhead, not signal (verify spelling)
  -handleensurepercent=0 \                  # ensures have no profiler scope and interrupt the timeline - mute them (verify spelling)
  -corelimit=14                             # cap cores - a 64-core workstation is not your player's machine (§9) (verify spelling)
```

- The trace lands in `<Project>/Saved/Traces/*.utrace` by default (or set
  `-tracefile=<path>`). Open it in **Unreal Insights**
  (`$UE_ROOT/Engine/Binaries/<Platform>/UnrealInsights`).
- A **live** trace connection (`-tracehost=`) must point at loopback
  (`127.0.0.1`) - never a network host. Same non-negotiable as the agent's
  Remote Control/MCP localhost rule.
- Cheapest probe first: before proposing a full multi-channel capture, a
  running session's `stat unit` / `stat unitgraph` readout or `log LogGarbage
  Verbose` output (§3) often answers the question for free.

## 2. Trace channels → what they unlock in Insights

| Channel | Unlocks | Worth knowing |
|---|---|---|
| `counters` | the **Counters** view: platform memory (total/available/used physical), `UPrimitiveComponent` count, draw-call count + GPU adapter, Chaos solver bodies (kinematic/dynamic/non-moving/total), scene-light count, hitch count; **UObject count** (5.8 - a ~2-line change, cherry-pickable) | cheap; leave it on. UObject count correlates directly with GC cost (§4) |
| `stats` | forwards **every** engine `stat` into Insights | high overhead left on blindly - enable for a specific stat. Standouts: D3D used/available/total video memory, **navigation memory** (caught a real ~100MB nav allocation in a game using its own custom nav - §8) |
| `loadtime` | the **Loading track** in the Timing view (toggle: "Asset Loading Tracks" button / hotkey **L**) - which assets the CPU processes, in order - plus an **Asset Loading** tab: *Event Aggregation* (group by event type or folder path) and a *Requests* table (every load request with duration, dependency count, package count) | covers CPU-side asset processing, not I/O-store/pak reads. The Requests table is where duplicate-load patterns show up (§5) |
| `task` *(verify spelling)* | task-system lines - what a thread/task is **waiting on** | pairs with `-statnamedevents` for wait-analysis (§7) |

- **Flushing exception**: the default rule is *never flush async loads* (one
  profiled title spent 12 of 23 startup seconds flushing) - but a flush behind a
  loading screen that keeps ticking/animating is acceptable: the stall reads as
  smooth to the player. Judge flushes by what the player sees.
- Editor-only companion: right-click a map/asset → **Size Map** - the full
  dependency graph with sizes. Not available from a packaged build.

## 3. CPU-side console commands (live session or `-ExecCmds`)

```sh
stat unit          # Game / Draw / GPU / RHIT frame-time split - the first question: which thread is the bottleneck?
stat unitgraph     # same, as a frame-history graph (spikes = hitches)
stat fps           # raw FPS
stat gpu           # GPU timing breakdown - real GPU work only; a CPU-side wait will NOT appear here (§7)

log LogGarbage Verbose        # per-GC-pass phase timings + object counts (§5) - also works as a launch -ExecCmds entry

obj list                       # all live UObjects, sorted by size
obj list -countsort            # sort by instance count instead - GC cost scales with COUNT, memory with size (verify spelling: -COUNTSORT is the documented switch)
obj list class=<ClassName>     # every instance of one class, full object paths
obj list -all -csv             # CSV dump for external tooling (verify spelling)

obj refs name=<FullObjectPath> shortest   # the shortest reference chain keeping an object alive - THE "why isn't this GC'd" tool

obj trace snapshot control     # 5.8+: full UObject snapshot into its own Insights tab - filter/sort/group (verify spelling: new in 5.8; confirm the exact command on your engine)
```

- `obj refs ... shortest` output reads as a chain - e.g.
  `MainMenuContainer → GameMode → GameState → DataAsset` - and the *last hop*
  is usually the fix: a data asset or global container eagerly referencing
  things the current context doesn't need ("reference hell", §5).
- **Chaos Visual Debugger** (standalone tool) visually confirms which physics
  bodies actually exist - the ground truth for "does everything have collision
  on?" (§8).

## 4. UObject count - the judgment scale

Read the count from `LogGarbage Verbose`, the 5.8 `counters` entry, or
`obj list`. The scale (a practitioner heuristic - not official except the hard
limit):

| Live UObjects | Verdict |
|---|---|
| ~100k | great |
| ~200k | fine - you know what you're doing |
| ~300-700k | not great, not terrible - expect ~a dropped frame per minute when GC runs |
| ~1M | too much - something is wrong |
| **~2M** | **hard engine limit** - the UObject array/hash is pre-allocated and does **not** grow; exceeding it is a hard crash |

- **Do not patch engine source (or quietly raise the GC-settings ceiling) to
  lift the limit** - approaching 2M is a real architecture/content bug; raising
  the ceiling papers over it and the GC cost still scales with every object.
- Counts move with game state - measure the *worst* realistic case: a late-game
  save, not the main menu (one profiled title: menu 123k, fresh save ~300k,
  late-game save 761k).

## 5. GC cost - how to reason about it

`LogGarbage Verbose` breaks a GC pass into phases: **reachability analysis →
unhashing unreachable objects → purge**. Attribute cost to the phase, not "GC
is slow":

- **Map-transition GC is a full purge, not incremental** - everything
  unreferenced dies at once. Real numbers from one profiled title: reachability
  0.4ms (fast - the offending reference chain was already broken), unhashing
  88ms, purging ~81k objects 212ms.
- **Steady-state GC scales with live-object count**: at ~800k objects,
  reachability alone ~30ms; a time-sliced full GC totaled 2.1s (~2ms/frame
  across the window). ~40k objects destroyed per minute of play ⇒ ~11 throwaway
  UObjects allocated *per second* - hunt the churn (`obj list -countsort`
  before/after a minute of play), not just the peak.
- **Duplicate-load-across-map-change**: the map-transition full purge unloads
  the previous map + GameState - and everything only *they* referenced. If the
  next map needs those assets, they reload from scratch (one profiled title: 9k
  of 16k gameplay packages were re-loads of things the menu had already loaded
  and GC had just destroyed). Spot it in the `loadtime` Requests table (§2) as
  double load-event rows per asset. Fix: hold a deliberate persistent
  reference - or better, stop the first context (main menu) eagerly pulling
  assets that belong to the second (gameplay). `obj refs ... shortest` names the
  eager chain (§3).

## 6. GPU-side - capture options, PIX, GPU Profiler 2.0, Nanite bins

```sh
# In-engine GPU named events / per-draw timing (adds RHI-thread overhead - §9):
r.RHISetGPUCaptureOptions 1     # real cvar name; the GPU-side analog of -statnamedevents

# On the launch line, to let WinPIX attach to the process:
<GameBinary> -attachPIX          # loads the PIX capture DLL; without it PIX won't see the process
```

- **GPU Profiler 2.0** (5.6+, lit up by the capture-options cvar): per-draw-call
  GPU timings directly in the Insights timeline - including **GPU idle vs
  working**, which is what separates "the GPU is slow" from "the CPU starved
  the GPU" (§7). For deeper shader/draw analysis, capture in **WinPIX**.
- **Nanite bins** - every unique material instance in the scene (MIC **and**
  MID) needs its own **shading bin**, and each bin costs ~**3µs** of GPU floor
  regardless of size. Healthy targets: **~50 raster bins, ~1,000 shading bins**
  (one profiled title ran ~2,100 raster / ~4,000 shading - too many; even with
  empty-bin compaction, 6,000+ active shading bins stayed a problem). Fixes:
  a fixed, reusable material topology instead of per-object MIDs - custom
  primitive data, per-instance custom data, material parameter collections
  (and 5.8's *experimental* Nanite bindless shaders, §10).
- **"If it can be Nanite, it should be Nanite."** Non-Nanite geometry doesn't
  amortize Nanite's fixed per-frame cost and gets *more* expensive alongside
  Lumen and Virtual Shadow Maps.
- **Landscape**: a landscape material compiled per-component with all layer
  weights is a huge base-pass cost (landscape covers enormous screen area) -
  bake through **Runtime Virtual Textures** and keep post-sample work minimal.
- **Non-Nanite shadows with huge bounds**: an instanced static mesh with
  elements far apart inflates the bounding box and the shadow cost - visible as
  vertex-shader output in a PIX capture. Split the instances or fix the bounds.

## 7. Methodology - never guess, always investigate

The loop is **what is slow → why is it slow → how do you fix it** - in that
order, each step evidenced before the next. Two worked cautionary tales:

- **The occlusion-wait mislabel.** A mystery gap between HZB and base pass:
  not in `stat gpu` (so not real GPU work), not in PIX (PIX only replays
  GPU-submitted events), but visible as draw-thread time in `stat unit`. GPU
  Profiler 2.0 showed the GPU *idle* in the gap; scrolling the Insights
  CPU/RHI-thread tracks found `GPUBound_WaitingForGPUOcclusionQueries` - which
  is **not occlusion cost, just the render thread waiting**. Disabling
  occlusion queries dropped draw time and raised GPU time *equally* - the gap
  relocated, proving nothing real was removed. The actual cause: RHI-thread
  translation work. Lesson: a profiler label names where time is *spent
  waiting*, not what to fix - if a "fix" moves the time without shrinking the
  frame, you removed nothing.
- **The attach-PIX red herring.** With `r.RHISetGPUCaptureOptions 1` + PIX
  attached, logging GPU named events adds *real* RHI-thread overhead - which
  inflated the apparent shading-bin translation cost. The underlying problem
  (too many shading bins) was still real; the instrumentation exaggerated it
  without fabricating it. Lesson: **corroborate any suspicious finding by
  toggling the instrumentation (or the suspect feature) off and re-measuring.**

## 8. Recurring anti-patterns - symptom → root cause → fix

All of these were found in one real mid-production title; check for them
proactively, not just reactively:

| Symptom | Root cause | Fix / next step |
|---|---|---|
| Startup stuck "initializing actors"; thousands of Chaos bodies at rest in `counters` | collision (simple+complex) is **enabled by default** on new static meshes - every leaf/plant had physics | disable collision on anything non-interactive; confirm the survivors in Chaos Visual Debugger |
| Six-figure `UOverlaySlot`/`UOverlay`/`UImage` counts in `obj list` | every UI structure pre-instantiates its full widget/button hierarchy (one 302-button widget ≈ 104k overlays) | construct on demand + pool and reuse - typically a ~day fix |
| Slate layout/prepass cost on every widget | Canvas Panel at every `UUserWidget` root (a UE4-era habit) - full transform/layout recompute | root in a cheaper panel; Canvas only where free-form placement is real |
| Shading-bin explosion (§6) | material layers used as Photoshop-style layers; one MID per character/instance | fixed material topology + custom primitive / per-instance data / MPCs |
| One Niagara system instance per creature (`NS_Seagull`, `NS_Shark`, ...) | per-actor FX spawning | shared/pooled systems or Niagara data channels |
| Thousands of widget-*component* ticks | one widget component per world-space UI button (2,800 in one profiled title) | Widget Component **Automatic** tick mode; don't use widget components for high-count/high-frequency UI - "as a treat" |
| Navigation memory in `stats` with no engine nav in use | nav-mesh generation left on while the game uses custom nav (~100MB found) | disable nav generation / strip nav data |
| GC hitch on a cadence (§4-§5) | UObject count too high / throwaway-object churn | `obj list -countsort`, `obj refs ... shortest`, cut the churn |
| Duplicate load rows across a map change (§5) | map-transition full purge destroys assets the next map re-loads | persistent reference, or stop the eager cross-context references |

## 9. Profiling-setup discipline

- **Consistent hardware** - captures are only comparable to captures from the
  same machine and thermal state. Consoles are the ideal stable baseline; for
  PC-only titles a handheld (**Steam Deck / ROG Ally**) is the poor-man's
  console. The alternative is deliberately running a *variety* of configs
  across the team daily - a choice, not an accident.
- `-corelimit=14` *(verify spelling)* approximates current-gen consoles;
  smaller values approximate consumer CPUs (Steam hardware survey: roughly half
  of players have **6 cores or fewer**). Relevant since 5.4/5.5 parallelized
  render/RHI work across workers (§10) - core count now moves render perf.
- Standard stress settings: **Ultra** quality + **TSR at 75% screen
  percentage** (`r.ScreenPercentage 75`), on the weakest hardware available.
- Profile the *worst* realistic scenarios: late-game save, UI-heavy modes
  (e.g. building placement), and - for sim/pause games - both **paused and
  unpaused**.
- **Cross-hardware GPU captures don't compare**: a capture taken on one GPU
  and analyzed against another is apples-to-oranges (the tools warn about it -
  believe them).
- **Instrumentation adds overhead** - `stats` channel, capture-options cvar,
  and an attached PIX all inflate the thing they measure (§7). Corroborate any
  finding that appeared *after* you turned instrumentation on.

## 10. Version notes (5.4 → 5.8)

- **5.4** - render thread parallelized (per-frame render setup on workers).
- **5.5** - parallel RHI translation (render commands → GPU commands on
  workers). Together with 5.4 this is why core count - and `-corelimit`
  testing - now matters for render/RHI perf.
- **5.6** - **GPU Profiler 2.0**: per-draw GPU timing in Insights via
  `r.RHISetGPUCaptureOptions 1`, no separate capture tool needed.
- **5.8** - `obj trace snapshot control` *(verify spelling)* UObject snapshot
  tab in Insights; **UObject count** as a first-class `counters` entry (~2-line
  change, cherry-pickable to earlier versions); **Nanite bindless shaders**
  (*experimental*) for the shading-bin/material-instance problem.

## Caveats

- **Exact spellings are the weak link.** Every item marked *(verify spelling)*
  is a best-effort spelling - the technique is sound, the flag name
  may be off by a character. Confirm against your engine
  (`<flag> -help`, engine source, or the console autocomplete) before putting
  any of them in automation.
- **The thresholds are heuristics, not contracts** - the UObject scale (§4) and
  the Nanite bin targets (§6) are one experienced practitioner's judgment
  values, except the ~2M UObject ceiling, which is a real pre-allocated engine
  limit.
- **A `.utrace` is not free to take** - disk (large), runtime overhead
  (especially the `stats` channel and GPU capture options), and a machine-long
  session. Reading an existing capture always beats taking a new one.
- Targets UE 5.4-5.8; re-validate exact channel/counter names and command
  spellings on your engine version before automating against them.

## Validation status

**Not yet re-validated live by this plugin on a real engine.** The *methodology,
heuristics, and thresholds* are high-confidence; the exact flag/command
spellings marked *(verify spelling)* are the weak link. That is the inverse of
the sibling skills' provenance (production tooling, empirically spot-verified):
treat the methodology as trustworthy and every exact flag/command spelling as
verify-before-relying. Real-engine confirmations of the *(verify spelling)*
items are the single most valuable contribution here.
