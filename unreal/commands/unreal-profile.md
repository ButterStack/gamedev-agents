---
description: Triage Unreal runtime performance - parse an existing .utrace/stat capture read-only, or propose a gated live Insights capture; classify the bottleneck (GC/UObject, GPU/Nanite, physics, UI)
argument-hint: "[stat|trace|gpu|memory] [path-to-.utrace]"
---

Profile Unreal runtime performance for the user, scoped by `$ARGUMENTS` (an
aspect keyword and/or a `.utrace` path) if given. Use the `unreal-profile`
skill for the launch line, channel map, console commands, and heuristics.
**Reading a capture is free; taking one is gated.**

1. **Find existing evidence first (read-only)** - a supplied `.utrace`, or the
   newest under the project's `Saved/Traces/` / `Saved/Profiling/`, or pasted
   `stat unit`/`obj list`/`LogGarbage` output. If any exists, analyze that -
   never take a new capture while an unread one answers the question.
2. **Only if nothing exists, propose a gated live capture** - show the exact
   launch line (trace channels per the aspect asked about - `unreal-profile`
   §1-§2), name the `.utrace` disk cost and the session length, note the
   consistent-hardware caveat (§9), and **wait for confirmation**. Live trace
   connections stay on localhost.
3. **Classify the bottleneck** with the cheapest discriminating probe:
   `stat unit` says which thread (Game vs Draw vs GPU vs RHI); GC/UObject via
   `LogGarbage Verbose` + `obj list -countsort` + the §4 judgment scale
   (~2M = hard crash); GPU via GPU Profiler 2.0 / PIX + Nanite bin counts
   (§6); physics via Chaos body counters; UI via widget counts and
   widget-component ticks (§8). Remember the §7 traps: a wait label is not a
   cost, and instrumentation inflates what it measures - corroborate by
   toggling it off.
4. **Report what you observed** - concrete numbers (frame-time split, UObject
   count against the scale, GC phase times, bin counts), the dominant cost
   named in plain language, and the first fix. Flag any command spelling the
   skill marks *(verify spelling)* rather than presenting it as confirmed. If
   the fix needs a build or an asset change, hand off to `unreal-build` /
   `unreal-editor-scripting` - gated there, not here.

**Example:** *"The game hitches every minute or so."* → `LogGarbage Verbose`
shows a time-sliced full GC over ~800k live UObjects (scale: "too much") -
`obj list -countsort` names 132k `UOverlaySlot` from pre-instantiated building
menus; fix is construct-on-demand + pooling, then re-measure the same save on
the same machine.
