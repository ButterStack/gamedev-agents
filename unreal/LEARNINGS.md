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
- **An installed (binary) engine refuses a target that changes shared build settings, and
  UBT's own suggested fix is the trap.** A `.Target.cs` whose `DefaultBuildSettings` /
  `IncludeOrderVersion` differ from the installed engine fails in seconds, before compiling
  anything: `<Target> modifies the values of properties: [ <Prop>: A != B ]. This is not
  allowed, as <Target> has build products in common with UnrealEditor`, with
  `CompilationResult=6`. UBT suggests `BuildEnvironment = TargetBuildEnvironment.Unique`,
  which means "compile the engine too" and is impossible on an installed or container
  engine. Align the target to the engine instead. Now both a signature row and a preflight
  check, since it is cheap to spot in `Source/*.Target.cs` before a build starts.
- **One missing `#include` masquerades as missing types *and* as broken inheritance.**
  Headers using a shared struct header without including it produced `unknown type name
  '<FStruct>'` for a struct that **is** defined, `cannot initialize object parameter of
  type '<Base>'`, and a `TIsDerivedFrom<...>::IsDerived` static_assert against a class that
  **does** derive from that base. Two includes collapsed ~30 of 57 error lines. The durable
  lesson is ordering: fix includes and rebuild *before* believing any "unknown type" or
  "not derived from" claim.
- **UHT cannot parse a nested enum used in a `UFUNCTION` signature**, and says so
  misleadingly: `Unable to find 'class', 'delegate', 'enum', or 'struct' with name 'X'`
  paired with `C++ Default parameter not parsed`. The type is usually a few lines above,
  declared inside the UCLASS. Hoist it to file scope and tag it `UENUM()`.
- **`Error_UnknownCookFailure` (25) is not always missing content.** A Blueprint-only
  template project on a *matched* engine failed with `Could not find a function named "..."
  in 'X'` and `In use pin ... no longer exists on node`, plus `Failed to find script package
  for import object 'Package /Script/<Plugin>'` - Blueprint nodes outliving a plugin no
  longer enabled by default. When the missing import is a `/Script/<Plugin>` package rather
  than a `/Game/` asset, check plugin enablement, not an unsynced file. Related preflight: a
  project with no `.umap`/`.uasset` has nothing to cook at all - compile it instead.

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
9. **A WSL2 `df` reports free space that does not exist.** The WSL ext4 volume is a sparse
   virtual disk on the Windows drive: `df` inside WSL showed ~895 GB free while the host
   volume had **19 GB**. Disk prechecks on a WSL-hosted rig must read the Windows volume
   (`df /mnt/c`), never the WSL root, or a cook sized against the WSL number fills the host
   drive.
10. **Windows OpenSSH kills detached children when the SSH session closes** - the
    Windows-side counterpart to item 5. A hidden `Start-Process` launched over SSH appears
    to start, then silently produces nothing. Launch long jobs as scheduled tasks
    (`schtasks /Create ... /SC ONCE /RL HIGHEST`, then `schtasks /Run`), which outlive the
    session.
11. **A dead registry credential is indistinguishable from a missing tag, and image
    preflights need bounds.** With an expired token, `docker manifest inspect` returns
    `denied: denied` for *every* tag, including images already present locally - which reads
    as "this tag does not exist" and produced a wrong conclusion about which engine images
    are published. Verify auth against a known-present image before calling any tag absent.
    `docker login` also writes to the **invoking user's** config, so automation running as
    another user keeps its own stale token - point at the good config with `DOCKER_CONFIG=`
    rather than copying the credential (see item 3). And bound the check itself: `docker
    image inspect` is normally instant but blocks on the content-store lock while a
    multi-GB layer commits, and an SSH failure (255) or timeout (124) says **nothing** about
    whether the image exists - never report those as "image missing".
12. **Windows sshd ignores the per-user `authorized_keys` for administrators.** With the
    default `Match Group administrators` block it reads only
    `%ProgramData%\ssh\administrators_authorized_keys`; a per-user key is silently ignored
    and fails as a plain `Permission denied (publickey)`. That file also needs inheritance
    removed and its ACL limited to SYSTEM + Administrators.
13. **Win64 `BuildCookRun` in CI wants a native-Windows host-mode runner** (verified on a
    real project, 2026-08-25): jobs run directly on the box that already has the engine,
    the VS toolchain, and the shared DDC. Keep the build logic in a repo script (a
    one-command `tools\build_windows.ps1` that locates the engine and calls
    `RunUAT.bat BuildCookRun`); the workflow step just invokes it. A warm shared DDC is
    why CI packaged in ~5 minutes - budget an hour cold. *(⤳skill: `unreal-build` should
    know CI-on-host means the engine, toolchain, and DDC are the host's own.)*
14. **Windows/PowerShell CI traps (each cost a debug cycle):**
    - A CI runner daemon started over ssh dies with the ssh session (item 10's lesson
      again, in runner form) and fails *silently*: it stays registered, jobs sit in
      `waiting` forever. Run it from a scheduled task (`schtasks`, ONLOGON, a start.bat
      that sets the working directory).
    - `powershell -File script.ps1` returns **0 even when RunUAT fails** -
      `$ErrorActionPreference = "Stop"` does not catch native-command exit codes. End the
      build script with `if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }` or CI lies green.
    - Host-mode job workspaces (`~/.cache/act/<hash>/hostexecutor`) are **deleted at job
      end**, build output included. A green build produces nothing unless an
      upload-artifact step runs.
    - `actions/upload-artifact@v4` **hard-refuses non-github.com servers** (GHES gate);
      use **@v3** on Forgejo/Gitea. Same for download-artifact.
    - A packaged Win64 artifact is ~370 MB compressed per build; set `retention-days` or
      builds eat the CI server's disk.
    - GPU jobs in docker-mode runners need a **node-bearing image** (`actions/checkout`
      is a node action; bare `nvidia/cuda` images die on step one). catthehacker
      act-22.04 + the NVIDIA container toolkit + `container.options: "--gpus all"` works;
      driver injection gives nvidia-smi-level access, CUDA only if the image adds it.
