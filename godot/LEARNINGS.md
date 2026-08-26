# Godot Agent - Learnings (running log)

Companion to [`NOTES.md`](./NOTES.md) (design rationale and validation status).
Two kinds of learning, kept separate: **(A)** findings that shaped what the
skills say, and **(B)** the operational reality of running Godot headlessly in
CI and in worktrees. Full detail lives in the skills; this log records why
they say what they say. No secrets.

## 2026-08-25 - v0.1.0, distilled from Pilot Light

Everything below comes from building and shipping Pilot Light, ButterStack's
Godot 4.7.1 shmup, to Android and iOS through CI.

### A. Agent / skill learnings

- **Import state outranks everything else in a Godot doctor.** A stale
  `global_script_class_cache.cfg` after a branch switch produced 31 failing
  tests on a commit that was a green tip of main; one `--headless --import`
  took it to 271/271 with no other change. So the doctor leads with cache
  state, and the failure-signature table's first row maps "burst of
  could-not-find-type errors" straight to it. *(⤳ `godot-observe` §3, §7.)*
- **A green test run needed its own trust model.** Two independent mechanisms
  produce a green exit while real failures happen, and they compose: GUT
  cannot distinguish a parse failure from a non-GutTest file (exit 0), and
  GitHub Actions' default `bash -e {0}` has no `pipefail`, so any `| tee` gate
  reports `tee`'s status. Both were live simultaneously across multiple
  merges - which is why `godot-test` is a skill. *(⤳ `godot-test` §1, §3.)*
- **Several real defects are invisible to every cheap gate.** A native-method
  shadow that killed all collision on device passed `gdlint`, `--import`, a
  boot check, and the pure-math suites; only a scene-tree integration test
  caught it. Hence the explicit gate-coverage table in `godot-test` §4.
- **Honest non-reproduction is worth recording.** The skills carry only the
  reproduced class-cache trigger, not a plausible-sounding explanation that
  was quoted but never reproduced.

### B. Operational / rig learnings

1. **A first `--import` in a fresh worktree is a git hazard**: roughly 150
   untracked `.uid`/`.import` files that a `git add -A` would sweep into a
   feature PR. Hence stage-by-filename and the guard hook. *(⤳ `godot-observe` §4.)*
2. **Import ordering around a merge is destructive.** `--import` before a
   merge creates untracked files the incoming branch also carries; git refuses
   ("untracked working tree files would be overwritten by merge") and the
   merge aborts with **no conflict list**. Import after merging, never before.
   *(⤳ `godot-build` §1.)*
3. **`--headless` cannot render, and fails by hanging rather than erroring.**
   A scripted screenshot via `SubViewport.get_texture().get_image()` sits at
   near-zero CPU forever; no flag fixes it. *(⤳ `godot-build` §4.)*
4. **Only an export proves packing.** Editor and headless runs read the
   project directory, not the PCK - a CI-generated plain text file read fine
   everywhere except on device, because `export_filter="all_resources"` does
   not sweep non-resource files. *(⤳ `godot-observe` §5, `godot-build` §2.)*
5. **Pin the engine.** All of the above was validated against
   `barichello/godot-ci:4.7.1`, matching CI exactly; a local result and a
   CI result that disagree are usually a version difference.
