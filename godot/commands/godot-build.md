---
description: Import or export a Godot 4 project (gated) - headless import, export-release/debug against a preset, with cost shown before running
argument-hint: "[import|export] [preset-name]"
---

Drive a Godot import or export for the user, per `$ARGUMENTS`. Use the
`godot-build` skill for exact command forms and `godot-observe` for the
preflight.

Before running anything:

1. Run the doctor preflight (`godot-build` §0). Do not proceed past an
   engine/project version mismatch without saying so.
2. **If a merge is pending, stop** and apply the ordering rule (`godot-build`
   §1): import *after* merging, never before, or the merge aborts with no
   conflict list.
3. **Show the exact command and a cost estimate, then wait for confirmation**
   before any export. An import is cheap enough to run without ceremony unless
   the merge case applies.

After running: report the exit status, the engine version, and the first real
error lines rather than just "it failed". For an export, state the artifact
path and note that only this export proves packing - an editor or headless run
against the project directory does not.
