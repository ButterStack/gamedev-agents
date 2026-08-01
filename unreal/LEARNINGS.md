# Unreal Agent - Validation Learnings (running log)

Companion to [`NOTES.md`](./NOTES.md) (design rationale and a summary of what's been
live-validated). Two kinds of learning:

- **(A) Agent/skill learnings** - where the agent's *diagnosis* was wrong or thin.
  These graduate into the skills (that's the feedback loop).
- **(B) Operational/rig learnings** - the reality of standing up a real-engine test
  rig. Mostly not skill material, but a few graduate into `unreal-build` /
  `unreal-observe` as environment guidance (flagged ⤳skill).

No secrets - reference credential *locations*, never paste them.

## A. Agent / skill learnings (→ baked into the skills)

- **The cook-log grammar was authored against a pre-Zen engine and matched almost
  nothing on a real 5.6+ cook.** Real UE 5.5+ has **no `DDC Hit Rate` line** - it
  uses **ZenServer**, and cache effectiveness instead lives in
  `LogShaderCompilers: ... FShaderJobCache stats ... cache hits x%, DDC hits y%`.
  Cook progress is a `Cooked packages N ... Total T` tally, not per-asset `Cooking
  <path>` lines. Verified against a real matched build+cook on both 5.6 and 5.8
  (496-1006 packages cooked, 0 err/warn), so the fix is version-general, not a
  5.6-specific patch. `unreal-observe`'s log-grammar section was corrected and
  version-flagged against this.
- **A headless engine/binary version mismatch does not print the interactive
  "rebuild?" prompt - it silently drops the module.** Running UE 5.8 against
  5.6-built binaries reports a misleading `LogPluginManager: ... could not be
  found ... consider disabling the plugin` instead of the familiar interactive
  warning. That's a trap: the correct fix is to rebuild for the running engine, not
  disable the plugin the log suggests disabling. Reproduced live and captured as a
  fixture (`fixtures/parrot-ue5.8-vs-5.6-mismatch.txt`); the failure-signature table
  now has a dedicated headless-mismatch row, guarded so it doesn't over-trigger on
  a genuinely-missing plugin.
- **UBT exit codes, verified against real failures**: `8` = RulesError (a bad
  module dependency reference - `Could not find definition for module 'X'`, where X
  is referenced-but-unresolvable, not "missing"), `6` = OtherCompilationError -
  corrected from an earlier, wrong "6=crash" guess. See
  `fixtures/parrot-ue5.6-build-fail-rulesError.txt` for the real failure log this
  was verified against, produced by deliberately typoing a module dependency name.
- **The failure-signature table had real gaps before this pass**: no
  build/compile-failure coverage at all, no Windows `MAX_PATH` signature, no
  DDC-unreachable-fallback signature, and "one-way asset upgrade" wording that
  conflated *opening* a newer-saved asset with *saving* one. All fixed in
  `unreal-observe`'s failure-signature table.
- **The corrected grammar holds across projects, not just engine versions.** A
  second, independent project synced from a real Perforce server and built+cooked
  clean on UE 5.8 (496/503 packages, 0 err/warn) using the same ZenServer/
  `FShaderJobCache` grammar - confirming the fix generalizes rather than being
  tuned to one project's log shape.

## B. Operational / rig learnings (standing up a real-engine test rig)

1. **Architecture beats specs for UE-in-Docker.** Epic's official Unreal Engine
   Docker images are **amd64-only** - on an arm64 Mac they run under emulation,
   impractically slow for shader-heavy cooking. Use a native x86_64 host; RAM (not
   core count) is the tight resource for cooks.
2. **On Windows, prefer WSL2 + a native Docker engine over Docker Desktop**, whose
   first-run flow (distro init, GUI dialogs) was flaky in practice. A plain `wsl
   --install` + `apt-get install docker.io` + `service docker start` gives a clean,
   headless `linux/amd64` engine. Tune WSL2's RAM ceiling explicitly
   (`.wslconfig`) before cooking - its default grabs about half the host's RAM.
3. **Image transfer: pull on the target host, don't move the image.** Both
   `docker save | ssh | docker load` streaming and save-to-file failed (streaming
   deadlocks on bulk stdin through a Windows SSH session; `docker save` hangs when
   the source host is low on disk). The reliable path is having the target host
   `docker login` and pull for itself - and never lift a credential from one host's
   keychain to authenticate another; that reads as credential theft and should be
   blocked.
4. **`docker.io` on WSL2 can default to a snapshotter that silently fails
   large-layer pulls** - layers report "Pull complete" but nothing actually
   commits to disk. Forcing the classic `overlay2` storage driver
   (`/etc/docker/daemon.json`) fixed it; check the storage driver first if a large
   pull looks done but the image isn't there.
5. **Long-running Docker operations must be fully detached from the shell that
   started them**, or they die when that session ends - `nohup` alone isn't
   enough; a proper session-detach (`setsid ... &`) is needed. Interrupted pulls
   resume from cached layers, so a killed one is cheap to retry.
6. **WSL2's VM idle-timeout can kill a long detached operation even though nothing
   actually failed.** By default WSL shuts its whole VM down about a minute after
   no session is attached to it - background processes don't count as activity, so
   a detached `docker pull`/build launched from a transient session dies partway
   through with a generic-looking failure. The config knob to disable this did not
   reliably take; holding a live, attached session open for the whole operation
   did. Repeated short VM boot cycles in the system log (`journalctl --list-boots`)
   are the tell that this, not a real crash, is what happened.
7. **Cap compile parallelism on a RAM-constrained host.** A default parallel
   compile count can OOM partway through a large shared precompiled-header build;
   UBT's parallelism settings (`BuildConfiguration.xml`) bring it down to a safe
   level, and shrinking the VM's memory ceiling stops it from pressuring the host.
8. **Prefer a slim engine image when disk is tight.** A "slim" build image variant
   was roughly a third smaller than the full one, still shipped a working compiler
   toolchain and editor, and only dropped debug symbols - a good default unless
   you specifically need those symbols.
