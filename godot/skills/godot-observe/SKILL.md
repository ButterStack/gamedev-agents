---
name: godot-observe
description: >
  Read-only Godot 4 diagnostics - the project + engine DOCTOR (project.godot
  and its config_version, the resolved engine binary, and above all the
  .godot/ import cache, whose staleness fails whole test suites with phantom
  "could not find type" errors), .uid/.import sidecar hygiene, export-preset
  packing rules, and build/run LOG diagnosis with a failure-signature table.
  Use for inspecting and reasoning about a Godot project WITHOUT importing,
  building, or changing it. To run an import/export use `godot-build`; for the
  test suite use `godot-test`; for GDScript language traps use
  `godot-gdscript`.
---

# Godot Observe - read-only diagnosis

Everything here is **read-only**: it inspects files and logs and runs no
mutating command. `godot --headless --import` *writes* to the project (see §3),
so it lives in `godot-build`, not here.

**Scope of verification:** every finding below was verified against **Godot
4.7.1** on a real, shipping GDScript project (ButterStack's Pilot Light, a
vertical shmup shipping Android and iOS builds through CI). **GDScript only** -
no C#/Mono coverage. Where a behavior is a 4.7-specific rule, it says so.
Do not represent any of this as verified on 4.2/4.3 LTS; it has not been.

---

## 1. Find the project and its engine version

```sh
# the project root is the directory holding project.godot
find . -maxdepth 3 -name project.godot -not -path '*/addons/*'

# engine version the project expects, and its feature tags
grep -E '^config_version|^\[application\]|config/features' project.godot
```

`config/features` carries the engine version the project was last saved with
(e.g. `PackedStringArray("4.7", "GL Compatibility")`). `config_version=5` is
Godot 4.x. Compare against the binary you actually have:

```sh
godot --version          # e.g. 4.7.1.stable.official
```

A mismatch here makes every later error misleading - resolve it before reading
any log. Note the renderer too: `GL Compatibility` matters for web/mobile
targets and is visible in the same `config/features` array.

## 2. Resolve the engine binary

```sh
command -v godot || ls /usr/local/bin/godot /Applications/Godot.app/Contents/MacOS/Godot 2>/dev/null
```

For reproducibility, prefer a pinned container over a local install when one is
available - `barichello/godot-ci:<version>` is the image this agent's findings
were validated against, and matching CI's engine exactly removes a whole class
of "works locally" confusion.

## 3. Import state - the single highest-value check

**Check this first, before believing any script or test error.** Godot keeps a
generated import cache in `.godot/`, which is gitignored, does **not** travel
with a checkout, and **nothing invalidates it on a branch switch**.

```sh
ls -la .godot/ 2>/dev/null || echo "NO .godot - project has never been imported here"
grep -c '=' .godot/global_script_class_cache.cfg 2>/dev/null
```

`.godot/global_script_class_cache.cfg` maps `class_name` declarations to files.
After switching branches it can still list classes from the branch you left.
Godot resolves those names against files that no longer exist and every script
touching the affected types errors at load.

> **Verified on 4.7.1:** checking out an older commit in a worktree produced
> **31 failing tests** reporting only generic "Unexpected Errors", plus leaked
> `CanvasItem` RIDs at exit - on a commit that was a green tip of main. One
> `godot --headless --import` took the same commit to 271/271 passing with no
> other change.

**Rule: treat "missing class_name types" or a burst of unexplained script
errors as a stale cache first, and a code problem second.** The re-import is in
`godot-build` §1.

Related: a freshly-added `class_name` is **invisible** to other scripts in a
`godot --headless --script` run until an `--import` has registered it.

## 4. Sidecar hygiene - `.uid` and `.import`

A first `--import` in a fresh worktree generates a `.uid` sidecar for
essentially every `.gd` script and an `.import` for every asset. On a project
whose `.gitignore` has no `*.uid`/`*.import` pattern, that lands as **~150
untracked files** that nobody created deliberately.

```sh
git status --porcelain | grep -cE '\.(uid|import)$'
git ls-files | grep -c '\.gd\.uid$'      # how many are actually tracked
```

Why an agent must care: this pile is easy to mistake for damage you caused, and
a `git add -A` will sweep ~150 unrelated files into a feature PR. **Stage by
explicit filename, never `-A` or `.`**, and confirm with `gh pr diff <n>
--name-only` rather than trusting local `git status`.

Two corollaries worth knowing:

- `.gdignore` only stops **future** imports. It does not retroactively delete
  `.import` sidecars a directory already has.
- Moving an already-imported asset with `git mv` needs a manual fix to the
  `.import` file's `source_file` entry, or the reimport looks stale.

## 5. Export presets - what actually gets packed

```sh
grep -E '^name=|^platform=|include_filter|export_filter' export_presets.cfg
```

**`export_filter="all_resources"` does NOT sweep plain non-resource files into
the exported PCK/APK.** Any runtime-read plain file (a `.txt`/`.json`/`.csv`
not imported as a resource) needs an explicit `include_filter` entry. The
editor's own label says so: "Filters to export non-resource files/folders".

> **Verified on 4.7.1:** a CI-generated `build_stamp.txt` under `res://` read
> fine from the editor and from headless runs against the project directory,
> but without `include_filter="build_stamp.txt"` the on-device
> `FileAccess.open("res://build_stamp.txt")` returned null and the feature
> silently degraded to its fallback.

**Corollary for reviews: local editor or headless verification cannot prove
packing.** Only a real export (CI artifact or device install) can. Label that
evidence honestly rather than implying an export was tested.

## 6. Reading logs

Godot writes diagnostics to stderr. A headless boot that only *runs* the tree
for N frames and greps stderr is a cheap, safe gate - but note what it cannot
see: it never instantiates objects that only construct when a run starts, so it
misses whole classes of defect (see §7 and `godot-test`).

## 7. Failure signatures - from error string to root cause

Fix the FIRST one; later errors usually cascade.

| Signature | Root cause | Fix / next step |
|---|---|---|
| A burst of `Could not find type "X" in the current scope`, or many tests failing with only GUT's generic "Unexpected Errors", often with leaked `CanvasItem` RIDs at exit | **stale `.godot/global_script_class_cache.cfg`** after a branch/commit switch - §3 | `godot --headless --import`, then re-run. Suspect this *before* reading the errors as a code defect |
| `Parse Error: Cannot call non-static function "X()" on the class "res://path.gd" directly. Make an instance instead.` | a `const C := preload("res://path.gd")` where the script has no `class_name` is typed by 4.7's static analyzer as that script's own class pseudo-type, not as `Script`/`Object` | cast at the call site: `(C as Script).get_script_constant_map()`. Leave the `preload` const alone for its legitimate `.new()` uses |
| `Assigned value for constant ... isn't a constant expression` | **4.7's stricter constant checker** rejects another class's constant as a key and a constructor call (e.g. `PackedInt32Array(...)`) as a value inside a top-level `const` | use string-literal keys and plain `Array` literals, and restore the lost referential safety with a test asserting each key maps to a real id |
| `Invalid call to function 'X' in base 'Node2D (Y)'. Expected 0 argument(s)` at runtime, every tick | a script method **shadows a native base-class method** - GDScript has no overloading, so a same-named method collides rather than adding a signature | rename to a non-colliding name. See `godot-gdscript` - no linter catches this |
| `untracked working tree files would be overwritten by merge`, strategy `ort` fails, merge aborts with **no conflict list** | `--import` was run **before** a merge, generating the very `.uid`/`.import` sidecars the incoming branch also carries | `git clean -f -- '*.uid' '*.import'` (verify none are tracked first), merge, then re-import. Import *after* merging, never before |
| A `--headless -s script.gd` run that sits idle forever at near-zero CPU after calling `get_image()` on a `SubViewport` texture | `--headless` uses a dummy rendering driver; the viewport never rasterizes, so the render target never signals ready and `get_image()` blocks forever | there is no flag that fixes this - do not scripted-screenshot under `--headless`. `kill -9`; it will not resolve on its own. See `godot-build` §4 |
| `load()` returns `null` at runtime on a path constant, after a clean merge with **zero conflicts** | a stale path constant from a branch that predated an asset-layout change won without a fight - zero conflicts means only one side touched the file, not that the result is correct | grep the merged tree for retired path strings explicitly; cover every path constant in a test |

**Exit codes:** Godot's own exit status is only as trustworthy as the harness
around it. See `godot-test` for the two ways a green exit hides a real failure
(GUT's silent skip, and `tee` swallowing pipe status in CI).
