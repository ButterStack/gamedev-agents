---
description: Run a gated Unreal build - FAST_COOK tracer, full BuildCookRun package, or UBT compile, with preflight checks and cost confirmation
argument-hint: "[fast|full|compile] [platform] [config]"
---

Guide the user through a safe, gated Unreal build per `$ARGUMENTS` (mode,
platform, config - ask if ambiguous; default to the cheapest mode that answers
their need). Use the `unreal-build` skill for exact command forms and the
parameter table.

Steps:

1. **Preflight** (`unreal-build` §0): run the doctor core (`unreal-observe`
   §1-§3) - project, engine, version match, targets. A version mismatch here
   makes every build error misleading; surface it before building.
2. **Editor-closed check** - a running editor locks module DLLs. If it's
   running, ask the user to close it; never kill it.
3. **Choose the cheapest sufficient mode**: `compile` = UBT only (code change);
   `fast` = FAST_COOK tracer (cook-only, one map, `-iterate -FastCook
   -skipcompile`) to prove the content pipeline; `full` = `-build -cook -allmaps
   -stage -pak -archive`. Always include `-unattended -nop4 -utf8output` on UAT.
4. **Show, then confirm** - print the exact command line you intend to run plus
   an estimated cost (`unreal-build` §7: minutes for a tracer, hours for a full
   cook on a cold DDC) and **wait for explicit confirmation** before running.
5. **Run and capture** - pipe through `tee` to a log file so the output is
   parseable afterward.
6. **Report observed results**, not "done": exit code, first error lines if it
   failed (fix the FIRST error - later ones cascade), cook time, DDC hit rate,
   shader/asset counts, warnings/errors, and PAK/archive size
   (`unreal-observe` §7 for extraction).

If the build fails, classify it with the agent's failure table (BuildId
mismatch, editor-locked DLLs, MAX_PATH, cold DDC, content error) and explain the
underlying concept, then propose the targeted fix - don't just re-run.

**Example:** *"Do a quick sanity build for Linux."* → doctor, editor check, then
propose the FAST_COOK tracer with the auto-detected map, confirm, run, and report
"cooked N assets in 4m, DDC 97%, 0 errors / 3 warnings".
