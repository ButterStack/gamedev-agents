---
description: Diagnose a Godot 4 project - engine/project version match, .godot import-cache staleness, .uid/.import sidecar hygiene, export-preset packing
argument-hint: "[path-to-project-dir]"
---

Run the read-only Godot doctor for the user, scoped to `$ARGUMENTS` if a
project path is given (else find `project.godot` in the current tree, excluding
`addons/`). Run no import, no export, and mutate nothing. Use the
`godot-observe` skill for exact command forms.

Check and report, in order:

1. **Project and engine version** (`godot-observe` §1) - `config_version` and
   `config/features` from `project.godot`, against `godot --version`. A
   mismatch makes every later error misleading; surface it before anything
   else. Note the renderer from `config/features` too.
2. **Engine binary** (§2) - which binary resolved, and whether a pinned
   container is available for reproducibility.
3. **Import-cache state** (§3) - **the highest-value check.** Does `.godot/`
   exist at all? If the working tree was switched since it was written, say
   plainly that any script or test error is untrustworthy until
   `--headless --import` has been run, and recommend that as step one.
4. **Sidecar hygiene** (§4) - count untracked `.uid`/`.import` files and how
   many are actually tracked. If the count is large, warn explicitly about
   `git add -A` sweeping them into a PR.
5. **Export presets** (§5) - preset names, platforms, and `include_filter`.
   Flag any runtime-read plain file under `res://` that no `include_filter`
   names, since it will be absent on device.

Close with a short briefing: what is healthy, what is suspect, and the single
cheapest next command. Say "no action" plainly when the project is clean rather
than manufacturing findings. Always state the engine version the report was
produced against.
