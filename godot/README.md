# Godot Agent

A ButterStack gamedev agent for **Godot 4** - observe, diagnose, and safely
operate a project from the command line: the `.godot/` import cache and the
phantom test failures a stale one produces, `.uid`/`.import` sidecar hygiene,
export-preset packing rules, gated headless import/export, GUT runs and the two
ways a green suite is lying, and the GDScript traps that survive every linter.

> Part of the series of public gamedev agents from ButterStack, alongside
> [`perforce`](../perforce), [`unreal`](../unreal), [`unity`](../unity),
> [`lore`](../lore), and [`jenkins`](../jenkins).

> **Verified against Godot 4.7.1, GDScript only.** No C#/Mono coverage, and no
> claim about 4.2/4.3 LTS - several findings are explicitly 4.7 rules. Findings
> were validated on Pilot Light, ButterStack's vertical shmup built
> AI-end-to-end in Godot and shipping Android and iOS builds through CI.

## Skills

| Skill | Use for |
|---|---|
| **`godot-observe`** | Read-only doctor: engine/project version match, `.godot/` cache state, sidecar hygiene, export presets, log diagnosis, and a failure-signature table. |
| **`godot-build`** | Gated `--headless --import` and `--export-release`/`--export-debug`, the merge-ordering rule, Android/iOS notes, and the headless rendering limits. |
| **`godot-test`** | GUT runs, and the two independent ways a suite exits green while real failures happen. |
| **`godot-gdscript`** | Language and object-lifetime traps that pass lint, import, and boot checks - and in one case shipped. |

## Commands

- `/godot-doctor [path]` - read-only project diagnosis
- `/godot-build [import|export] [preset]` - gated import or export
- `/godot-test [path]` - run GUT and verify the result is trustworthy

## The three findings worth reading first

1. **A stale `.godot/` class cache fails whole suites with phantom errors.** The
   cache is gitignored, does not travel with a checkout, and nothing
   invalidates it on a branch switch. One observed case: 31 failing tests on a
   commit that was a green tip of main, fixed to 271/271 by a single
   `--headless --import` with no other change. Suspect the cache before the
   code.
2. **A green GUT run is not evidence the tests ran.** GUT cannot tell "this
   script failed to parse" from "this script isn't a GutTest" - it logs one
   `Ignoring script ...` line and exits 0. Separately, `tee` without `pipefail`
   makes every piped CI gate unfailable. Both were live in a real repo for
   multiple merges.
3. **Never shadow a native method.** GDScript has no overloading, so a
   same-named script method collides with the native one even at a different
   arity. A pool's `get_position(index)` colliding with `Node2D.get_position()`
   silently killed all collision detection on device, and no gate caught it.

## Safety

A `PreToolUse` hook (`scripts/guard-godot.sh`) hard-blocks removing
`project.godot`/`export_presets.cfg`, deleting `.import` sidecars on their own
(Godot's `.meta` analog), and unscoped `git clean -f`. It deliberately allows
`rm -rf .godot`, which is regenerable and a legitimate fix.

## Install

```
/plugin marketplace add ButterStack/gamedev-agents
/plugin install godot@gamedev-agents
```

---

*The open agents trail what ButterStack learns running gamedev tooling in production - get the managed version at [butterstack.com](https://butterstack.com?utm_source=github&utm_medium=repo&utm_campaign=gamedev-agents).*
