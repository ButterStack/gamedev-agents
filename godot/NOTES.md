# Godot Agent - design notes and validation status

## Why these four skills

The split follows the same observe / operate / verify shape as the other
plugins, with one addition:

- **`godot-observe`** is the anchor, as `p4-observe` and `unreal-observe` are in
  theirs. Nearly every confusing Godot failure traces back to import state, so
  the doctor leads with the `.godot/` cache rather than with the engine binary.
- **`godot-build`** holds anything that writes. `--headless --import` lives here
  rather than in observe precisely because it mutates the project.
- **`godot-test`** exists as its own skill because the strongest cluster of
  findings is not "how to run tests" but "why a green run is lying", which is
  too big to bury in a section of another skill.
- **`godot-gdscript`** is the one departure from the three-skill shape. The
  language and lifetime traps are about reading and writing code rather than
  operating a rig, and there are enough of them (nine, several of which shipped
  as real defects) to stand alone.

## Validation status

**Verified against Godot 4.7.1, GDScript only**, on Pilot Light - a vertical
shmup built AI-end-to-end, shipping Android and iOS through CI, with a GUT
suite in the 270-400 test range and the engine pinned via
`barichello/godot-ci:4.7.1`, so the findings come from a reproducible engine.

### Verified against a real engine and project

Ten findings, each with a deterministic repro or an on-device confirmation:
the stale-class-cache suite failure (31 failures to 271/271 on one import),
both green-run lies (GUT's silent skip and `tee` under `bash -e {0}`), the
native-method shadow and the unpacked plain non-resource file caught only on
device, the merge aborting with no conflict list, the `--headless`
`get_image()` hang, the dropped `RefCounted` signal target, 4.7's constant
checker, and the timer-residual quantization. Exact strings and numbers live
in the skills and [`LEARNINGS.md`](./LEARNINGS.md).

### Not verified - do not imply otherwise

- **Any engine version other than 4.7.1.** Several findings are explicitly 4.7
  static-analyzer or constant-checker rules; none of this has been re-run on a
  4.2/4.3 LTS build, where they may simply not apply.
- **C# / Mono.** Every finding is GDScript. The `.godot` cache and
  export-preset behaviors are plausibly engine-general, but untested.
- **Web export.** `godot-build` deliberately says nothing about it; the
  validation project has no Web preset, so there is no basis for a claim.
- **Godot 3.x.** Out of scope entirely.
- **Whether the `.uid` sidecar flood generalizes.** Observed on a repo whose
  `.gitignore` has no `*.uid`/`*.import` pattern; a project that ignores or
  commits them will not see it.

### Deliberately not vendored

Pilot Light's boot-check script and allowlist are project-shaped, so the
boot-check *pattern* is described in `godot-test` §4 instead; the shipped
`godot-export-retry.sh` is generic (preset and output path as arguments).
