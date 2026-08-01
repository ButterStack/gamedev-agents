---
description: Parse and triage an Unreal cook/build log - first error, warning volume, DDC hit rate, shader/asset counts, PAK size, phase timing
argument-hint: "[path-to-log]"
---

Diagnose an Unreal cook/build log for the user: `$ARGUMENTS` if a log path is
given, else find the newest candidate (the project's `Saved/Logs/*.log`, or a
`tee`'d UAT capture like `cook_output_*.log`). Read-only - parse and explain; do
not re-run any build from here. Use the `unreal-observe` skill (§7) for the log
grammar and extraction commands.

Analyze and report:

1. **Outcome & first error** - did the run succeed? On failure, find the
   **first** `Error:`/`Fatal:` line (later errors usually cascade from it), quote
   it with a couple of lines of context, and explain the underlying concept in
   plain language (bad asset reference, BuildId mismatch, editor-locked DLLs,
   MAX_PATH, UAT-vs-content failure - check `AutomationTool exiting with` when
   content errors are absent).
2. **Metrics** - DDC hit rate (≈0% = cold cache: the run paid full shader
   compilation), shader compile count, cooked-asset count (grep-approximate -
   present as such), warning count, PAK/archive size if the run packaged.
3. **Phase timing** - use the `[YYYY.MM.DD-HH.MM.SS:mmm]` timestamps to
   attribute wall time across cook / shader / pak phases and name the dominant
   one.
4. **Asset hotspots** - which assets/types dominate `LogCook`/`LogSavePackage`
   lines (infer type from path conventions: `T_`/`SM_`/`M_`/`BP_`/`.umap`), and
   any asset that appears repeatedly with warnings.

Present a tight briefing with concrete numbers and named assets, not raw log
dumps. End with the actionable conclusion: what to fix first, whether the
slowness is cache-cold (recommend a warm/shared DDC - `unreal-build` §6) vs
genuinely regressed, and hand off to `unreal-build` if a re-run is warranted -
gated and confirmed there, not here.

**Example:** *"Why did last night's cook take 3 hours?"* → "DDC hit rate 2%
(cold cache after the engine update) - 41k shaders recompiled, cook itself was
14 min. Point the node at the shared DDC and the next run is ~20 min."
