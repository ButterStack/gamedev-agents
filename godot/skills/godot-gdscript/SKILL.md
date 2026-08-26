---
name: godot-gdscript
description: >
  GDScript language and object-lifetime traps that no linter catches - native
  method shadowing that silently kills a code path on device, closures
  capturing by value, signals not retaining a RefCounted target, 4.7's
  stricter constant checker and type-inference gaps, float precision through
  Vector2, and the timer-residual bug that quantizes any computed interval to
  whole physics frames. Use when writing or reviewing GDScript, or when a
  defect survived lint, import, and boot checks.
---

# GDScript traps

Each entry here is a defect that **passed** `gdformat`, `gdlint`, and
`--headless --import`, and in several cases shipped. They are grouped by what
they break, not by language feature.

**Scope of verification:** Godot **4.7.1**, GDScript only. Rules marked *4.7*
are version-specific and may not apply to 4.2/4.3 LTS.

---

## 1. Never shadow a native method - it kills the call path silently

**GDScript has no method overloading.** A script method with the same name as
*any* method on the base class (`Object`/`Node`/`CanvasItem`/`Node2D`/...) does
not add a signature - it collides with the native one, **even with a different
argument count**, and Godot 4 resolves the call against the *native* signature.

> **Verified, shipped, and caught only on device:** a pool's
> `get_position(index: int)` collided with `Node2D.get_position()` (zero-arg,
> native). Every call site hit
> `Invalid call to function 'get_position' in base 'Node2D (BulletPool)'.
> Expected 0 argument(s)` on every physics tick, silently killing **all
> collision detection** - score and pickups stuck at zero deep into a stage.
> Fixed by renaming to `bullet_position`.

**No gate catches this.** `gdlint` has no knowledge of native signatures (it
enforces name shape only), `--import` and a boot check never instantiate the
objects, and pure-math test suites never call the API. Only a scene-tree
integration test that builds the real nodes and exercises the real path catches
it.

Its two faces (a runtime `Invalid call` normally, a hard compile error under
GUT) are described in `godot-test` §2.

## 2. Closures capture locals by value

```gdscript
var hits := 0
var cb := func(): hits += 1     # mutates the lambda's private copy
# ... later: hits is still 0
```

The lambda snapshots `hits` when it is created. **Reference types behave
differently**: mutating the *contents* of a captured `Array`/`Dictionary`/
`Object` is visible outside, because both scopes hold the same reference -
reassigning the captured variable itself is not.

**Practice:** when a callback must record that it ran (call count, last args),
default to an `Array`/`Dictionary` accumulator, never a bare
`int`/`float`/`bool`/`String`.

## 3. A signal does not keep a `RefCounted` target alive

`connect()` stores only the target's ObjectID for a **bound-method** `Callable`.
It takes **no reference**.

> **Verified by headless repro:** a `RefCounted` built as a function-local,
> connected via `some_signal.connect(obj.on_thing)`, and stored nowhere else,
> was freed the moment the function returned. The connection count went
> **1 -> 0** the instant the reference dropped, before the signal ever fired.
> No error, no warning, nothing in stderr - the feature simply never happened,
> for the entire time it shipped.

A **lambda** would have captured strongly and kept it alive. This is
specifically a method-Callable-on-a-`RefCounted` failure, not a general
"signals don't retain" rule.

**Practice:** any non-`Node` object a handler needs to stay alive on must be
retained in a **member field**, not a function-local. And see `godot-test` §6 -
a test that calls the handler directly cannot catch this.

## 4. *4.7* The constant checker rejects cross-class constants and constructors

```gdscript
const MAP := { OtherClass.SOME_ID: PackedInt32Array([0, 1, 2]) }
# Assigned value for constant ... isn't a constant expression
```

**Both halves are rejected**: another class's constant as a key, and a
constructor call as a value. The failure compiles nothing in that script and
**cascades into every dependent script**.

**Fix pattern:** string-literal keys and plain `Array` literals, plus a test
asserting every key maps to a real id - restoring at runtime the referential
safety the const expression can no longer give you at compile time.

**Broader lesson: desk-checking GDScript is not parsing it.** This survived
author review and a second review, and was caught only by running against a
real engine binary.

## 5. *4.7* `:=` cannot always infer, and `preload` types are not `Script`

- `:=` can fail to infer from `floor()`/`ceil()`, though both return `float`.
  Annotate explicitly when inference fails rather than restructuring the math.
- A `const C := preload("res://path.gd")` where the target has **no
  `class_name`** is typed as that script's own class pseudo-type - the type that
  supports `C.new()` sugar - **not** as `Script`/`Object`. Calling a `Script`
  instance method on it is a parse error. Cast at the call site:
  `(C as Script).get_script_constant_map()`, leaving the const itself intact.

## 6. Float precision: `Vector2` components are 32-bit

A scalar read back out of a `Vector2` field can **silently disagree** with the
same decimal literal written as a plain `float`, because `Vector2` components
round-trip through 32-bit while plain GDScript floats are 64-bit. A computed
plain-float `const` can also miss a decimal literal by 1 ULP with no `Vector2`
involved. Compare with a tolerance; never `==` a float that has been through a
`Vector2`.

## 7. Repeating timers: accumulate the residual, never assign

```gdscript
# WRONG - throws away the leftover, quantizing to whole physics frames
_fire_timer -= delta
if _fire_timer <= 0.0:
    _fire_timer = INTERVAL / multiplier

# RIGHT - the negative leftover carries into the next interval
_fire_timer += INTERVAL / multiplier
```

Assigning a fresh interval discards the (negative) leftover from the tick that
just fired, so the real period is `ceil(interval / physics_delta) *
physics_delta`, not the interval you computed.

> **Verified:** at a 0.15s base interval on a 60Hz tick there were only **nine
> reachable cadences** no matter how many upgrade ranks sat between them, and
> the rounding error's sign flipped with rank - so realized ratios could
> *increase* with rank, the opposite of the intended curve.

This applies to **any** interval derived from a continuous stat rather than
hand-picked to land on frame boundaries.

**Test shape:** a magic-number frame-count assertion can pass by coincidence.
Drive `_physics_process(delta)` for many ticks and assert the *average* rate
converges to the mathematical ratio within a small tolerance.

## 8. Layout: a `Control` under a `Node2D` anchors against nothing

`Control.set_anchors_and_offsets_preset()` resolves against the nearest
ancestor's `CanvasItem.get_anchorable_rect()`, and **`Node2D` returns a
degenerate `Rect2(0,0,0,0)`**. `PRESET_FULL_RECT` under a `Node2D` parent
therefore anchors against nothing: the `Control` keeps its natural min-size at
the origin, and all centering computes against a zero-size rect.

`CanvasLayer` is **not** a `CanvasItem` (it derives from `Node`), so under a
`CanvasLayer` ancestor Godot falls through to `Viewport.get_visible_rect()` -
usually the behavior actually wanted.

**Debugging corollary:** centered and left-aligned text render **identically**
inside a zero-width rect. Check the rect's actual size *before* touching
alignment properties.

## 9. Miscellaneous engine semantics

- **`Engine.time_scale` does not affect `AudioStreamPlayer` playback speed.**
  `get_tree().paused` does, and stops it outright.
- **A `SceneTree`-subclass probe script** must defer real tree-membership work
  to the first `_process()` call, not `_initialize()`.
- **A freshly-added `class_name` is invisible** to other scripts in a
  `--headless --script` run until an `--import` has registered it.
