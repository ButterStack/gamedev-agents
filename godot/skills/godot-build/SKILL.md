---
name: godot-build
description: >
  Gated Godot 4 headless playbooks - `--headless --import` (when it is
  required, and the merge-ordering rule that makes it destructive if run
  early), `--export-release`/`--export-debug` against export_presets.cfg,
  Android and iOS export including the signing failure that looks like a
  certificate problem, and the headless rendering limits that make scripted
  screenshots impossible. Use whenever actually importing, exporting, or
  packaging a Godot project. For read-only diagnosis use `godot-observe`.
---

# Godot Build, Import & Export

`$GODOT` is the engine binary resolved by `godot-observe` §2 - resolve it
first, never guess it. Placeholders use `<ANGLE_BRACKETS>`.

**Gating.** An import is cheap (seconds to a couple of minutes); an export is
not, and an export can overwrite artifacts. Show the exact command and its
cost estimate before running anything in §2 onward, and wait for confirmation -
the same show-then-confirm pattern the other plugins use. `--import` (§1) is
routine enough to run without ceremony **except** in the merge case below,
which is genuinely destructive.

**Scope of verification:** Godot **4.7.1**, GDScript only, validated on a
project shipping Android and iOS through CI. Web export is **not** covered
here - it has not been validated and no claim is made about it.

---

## 0. Preflight - every time

1. **Doctor** - `godot-observe` §1-§3: project found, engine version matches
   `config/features`, and the `.godot/` cache state understood.
2. **Has the branch changed since the last import?** If yes, §1 is mandatory
   before trusting any script error or test result.
3. **Is a merge pending?** If yes, read §1's ordering rule before importing.
4. **Capture stderr.** Godot's diagnostics go to stderr; pipe with `2>&1` and
   `tee`, but see `godot-test` §3 - `tee` will swallow the exit status unless
   `pipefail` is on.

## 1. `--headless --import`

```sh
$GODOT --headless --import          # run from the project root
```

Populates `.godot/`, including `global_script_class_cache.cfg`, and writes a
`.uid`/`.import` sidecar for every script and asset.

**Run it after:**

- any branch or commit switch (a stale cache fails whole suites with phantom
  errors - `godot-observe` §3)
- adding a `class_name` that other scripts need to see
- **a merge** - always after, never before

**The merge-ordering rule.** `--import` generates exactly the `.uid`/`.import`
files an incoming branch may also carry. Running it *before* a merge leaves a
working tree full of untracked files that collide with what the merge wants to
create, and git refuses outright:

```
error: untracked working tree files would be overwritten by merge
```

The `ort` strategy fails and the merge aborts **before producing any conflict
list**, which reads as a confusing, cause-less failure. Recovery:

```sh
git ls-files -- '*.uid' '*.import'        # confirm none are tracked FIRST
git clean -f -- '*.uid' '*.import'        # a blind clean -f on a tracked path deletes real content
git merge <branch>
$GODOT --headless --import                # regenerate after
```

The sidecars are regenerable output, not merge input.

## 2. Export - the preset is the contract

```sh
$GODOT --headless --export-release "<PresetName>" <output-path>
$GODOT --headless --export-debug   "<PresetName>" <output-path>
```

Preset names come from `export_presets.cfg` (`godot-observe` §5). Two rules
that bite:

- **`export_filter="all_resources"` does not pack plain non-resource files.**
  Anything read at runtime through `FileAccess` that is not an imported
  resource needs an explicit `include_filter` entry, or it is simply absent on
  device and the feature degrades to whatever its fallback is - silently.
- **Only a real export proves packing.** Editor and headless runs read from the
  project directory, not the PCK, so they cannot distinguish "packed" from
  "present in the repo". Say so when reporting evidence.

## 3. Platform notes

**Android.** Export can fail on transient dependency resolution. A bounded
retry around the export call (rather than an unbounded loop) is the pattern
that held up in CI; `scripts/godot-export-retry.sh` in this plugin implements
it.

**iOS.** Godot generates an Xcode project which is then archived. A Release
archive failure here is frequently misread:

> **Verified:** Xcode automatic signing can **create a certificate and then
> still fail on provisioning profiles.** The certificate now existing is not
> evidence that signing succeeded - read the profile error, not the
> certificate state.

## 4. What headless cannot do

`--headless` uses a dummy rendering driver with no display or GPU context.
Logic frames still fire, so `process_frame` proceeds and a scene tree runs
normally - but a viewport never actually rasterizes.

**Consequence: you cannot take a screenshot under `--headless`.** A script that
builds a `SubViewport`, awaits a couple of `process_frame`s and calls
`viewport.get_texture().get_image()` **hangs forever** - no error, no timeout,
an idle process at near-zero CPU waiting on a frame that will never composite.

There is no flag that fixes this. If in-engine visual ground truth is needed,
use a real editor/runtime instance, not `--headless`. If this pattern is
attempted by accident, `kill -9` it; it will not resolve on its own.

This is *different* from a headless boot check, which only runs the tree for N
frames and greps stderr - that never asks a viewport for pixels and is
unaffected.

## 5. Cost expectations

| Operation | Rough cost | Notes |
|---|---|---|
| `--headless --import` (warm) | seconds | after a branch switch this is mandatory and cheap |
| `--headless --import` (cold/fresh worktree) | a minute or two | also generates ~150 sidecars - `godot-observe` §4 |
| headless boot check (N frames) | seconds | cheap gate; misses anything not constructed at boot |
| export (mobile) | minutes | the only thing that proves packing |

Report the engine version alongside any result. A build claim without the
version it was produced on is not reproducible.
