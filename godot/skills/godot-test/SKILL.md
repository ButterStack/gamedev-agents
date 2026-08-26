---
name: godot-test
description: >
  Running and trusting a Godot 4 test suite (GUT) - the two independent ways a
  run exits GREEN while real failures are happening (GUT silently skipping a
  script that failed to parse, and `tee` swallowing the exit status in CI), the
  suite-integrity canary that closes the first hole, what a headless boot gate
  can and cannot catch, and how to write tests that survive being run outside a
  scene tree. Use when running, reading, or trusting Godot test results.
---

# Godot Test - and why a green run may be lying

The central lesson of this skill: **on a Godot project, "all tests passed" is
not by itself evidence that the tests ran.** Two independent mechanisms produce
a green exit while real failures are happening, and they compose.

**Scope of verification:** Godot **4.7.1** with GUT, GDScript only, on a suite
of ~270-400 tests in CI and locally.

---

## 1. GUT exits green on a script it could not parse

GUT's `test_collector.gd` **cannot distinguish "this script failed to
load/parse" from "this script legitimately isn't a GutTest"**. `_parse_script()`
loads the file; if the load fails *or* the loaded script doesn't inherit
`GutTest`, `add_script()` logs one line and moves on:

```
Ignoring script <path> because it does not extend GutTest
```

A real `SCRIPT ERROR: Parse Error` at load time and a stray helper file someone
dropped in `tests/` are **byte-for-byte identical** in the run summary, and the
run still **exits 0**.

> **Verified:** an entire 11-test integration file went uncounted in every
> "all tests passed" report, local and CI, for multiple merges - because nobody
> reads WARNING lines in a green run.

**Antidote - a suite-integrity canary.** Add a test that lists `test_*.gd` on
disk and diffs it against the scripts GUT actually collected for the current
run:

```gdscript
# fails loudly, by name, on any mismatch
var on_disk := <files under res://tests>
var collected := gut.get_test_collector().scripts.map(func(s): return s.get_filename())
assert_eq(on_disk_not_in(collected), [], "tests silently skipped")
```

It only has full power in a **full-suite** run (`-gdir=res://tests`). Invoked
standalone with `-gtest=`, it correctly reports every other file as missing,
because only one file was asked to run - so gate on the full-suite invocation.

Demonstrated live: a deliberately unparseable file dropped into `tests/` made
the canary fail with `["test_zzz_broken.gd"] != []` and the suite exit 1;
removing it restored a clean green run.

## 2. GUT escalates a native-override warning into a hard error

A script method that shadows a native base-class method (see `godot-gdscript`)
behaves differently depending on how it is loaded:

- **Normal boot/export:** a non-fatal parse *warning* ("The method ... overrides
  a method from native class ... This won't be called by the engine"). The
  script loads; the failure only appears at runtime as an `Invalid call`.
- **Under GUT** (`addons/gut/warnings_manager.gd`): the same warning is
  escalated to a **hard compile error** ("Warning treated as error"). The whole
  script fails to load and every dependent test fails with a cascading,
  confusing `Invalid call. Nonexistent function 'new' in base 'GDScript'`.

So the *same defect* reads as a runtime bug in one path and a nonsense
constructor error in the other. Recognise the `Nonexistent function 'new' in
base 'GDScript'` shape as "a script failed to compile", not "the class is
missing".

## 3. `tee` makes every CI gate unfailable

GitHub Actions' default `run:` shell is `bash -e {0}` - **`-e` only, no
`pipefail`**. A piped command's exit status is the last command's, which is
always `tee`'s `0`:

```yaml
- run: gdlint src/ 2>&1 | tee -a ci_output.log    # ALWAYS green
```

> **Verified:** unit tests, `gdformat --check`, `gdlint`, an app-id guard,
> `--headless --import`, a boot check, and GUT could all fail loudly in the log
> while the job reported green. Real lint debt merged green for multiple PRs
> before this was found.

**Fix**, once, at the workflow level:

```yaml
defaults:
  run:
    shell: bash        # expands to: bash --noprofile --norc -eo pipefail {0}
```

**Before turning this on, check what reads the captured log.** A step that
consumes the piped file may now see it truncated, because the command can fail
before `tee` finishes writing. If nothing consumes it, this is a pure win.

## 4. What each gate actually catches

Gates are not interchangeable, and the cheap ones have large blind spots:

| Gate | Catches | Blind to |
|---|---|---|
| `gdformat --check` / `gdlint` | formatting, name-shape rules | native method signatures; anything semantic |
| `--headless --import` | parse errors at import | broken string paths; anything not constructed |
| headless boot check (N frames) | boot-time script errors | anything that only constructs when a *run* starts |
| GUT full suite | behavior, including broken sprite/audio paths | only what a test actually exercises |

> **Verified:** a broken sprite/audio path was caught **only** by the GUT
> suite - `gdformat`, `gdlint`, `--import` and the boot check all missed it,
> because those nodes only construct when a run starts.

And the converse: a collision-killing native-method shadow was caught by
**none** of the existing gates, because the pure-math test suites never called
the pooled APIs at all. Only a scene-tree integration test that builds the real
nodes and calls the real path catches that class of bug.

## 5. Writing tests that work outside a scene tree

GUT tests often instantiate a node with `.new()` and never add it to a tree.
Three consequences:

- **`create_tween()` errors outside the tree.** Guard it: create the tween only
  when `is_inside_tree()`, store it, and `if tween != null and tween.is_valid():
  await tween.finished`. With no tree there is no tween, the coroutine never
  suspends, and the caller's `await` returns inline - so a test can assert the
  finished state on the very next line. **A GDScript function containing `await`
  still runs to completion synchronously if it never actually suspends.** No
  test-only branches in production code.
- **A node that never entered the tree reports `is_processing_input()` and
  `is_physics_processing()` as false**, even with those callbacks defined -
  Godot only enables them on tree entry. A test asserting "input was live
  before, locked after" must first call `set_process_input(true)` /
  `set_physics_process(true)` to restore the in-tree baseline, or the "before"
  assertion fails and the "after" one proves nothing.
- **Closures capture by value.** A lambda recording that it ran must accumulate
  into an `Array`/`Dictionary`, never a bare `int` - see `godot-gdscript` §2.

## 6. Testing a signal bridge

A test that calls a handler method **directly** cannot catch a lifetime bug in
the wiring, because the test's own local variable supplies the strong reference
the bug depends on to hide. Any test covering a signal bridge must build the
wiring exactly as production does, fire the signal from outside, and assert the
effect. See `godot-gdscript` §3 for the underlying failure.
