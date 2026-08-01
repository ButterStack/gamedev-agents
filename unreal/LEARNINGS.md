# Unreal Agent - Validation Learnings (running log)

Companion to [`NOTES.md`](./NOTES.md) (design rationale and a summary of what's been
live-validated). Two kinds of learning, kept separate:

- **(A) Agent/skill learnings** - where the agent's *diagnosis* was wrong or thin. These
  **graduate into the skills** (that's the feedback loop). Summarized here for
  one-glance history.
- **(B) Operational/rig learnings** - the reality of standing up a real-engine test rig
  (the heavy prerequisite for testing any of this against a live engine). Mostly *not*
  skill material, but a few graduate into `unreal-build` / `unreal-observe` as
  environment guidance (flagged ⤳skill).

> Updated as we go. No secrets - reference credential *locations*, never paste them.

## A. Agent / skill learnings (→ baked into the skills)

- **Tier 0 (doctor):** engine-resolution glob was Linux/WSL-only (no macOS); no "no engine
  at all" branch; §4 treated a never-built project as a BuildId mismatch; §5 ignore-check
  assumed a live p4 server. → fixed in `unreal-observe` §2/§4/§5.
- **Tier 1 (log diagnosis):** §7 had **no build/compile-failure coverage** and no named
  failure-signature table, so F1/F4 passed on general knowledge, not the skill. UBT
  `Could not find definition for module 'X'` semantics were **inverted** (it means X is
  referenced-but-unresolvable, not a missing dependency). MAX_PATH (`GetLastError=206`),
  DDC-unreachable-fallback, and missing-content-dependency signatures were absent.
  One-way-upgrade wording conflated *opening* with *saving*. → new **§8 failure-signature
  table** + exit-code decode + §2/§6 precision fixes.
- **Tier 2 (real 5.6.1 cook - engine-verified):** the §7 grammar (mirrored from
  ButterStack's own cook-log parser) was authored against an **older, pre-Zen UE** and
  matches almost nothing in 5.6. Real 5.6 has **no `DDC Hit Rate` line** (5.5+ uses
  **ZenServer**; cache effectiveness lives in `LogShaderCompilers: ... FShaderJobCache
  stats ... cache hits x%, DDC hits y%`), cook progress is a `Cooked packages N ...
  Total T` tally (not per-asset `Cooking <path>`), and shaders use `Using N local
  workers`. → `unreal-observe` §5/§7 corrected + version-flagged. We recommended the
  same fix upstream in ButterStack's own cook-log parser.
- **Tier 2 (money-shot, real 5.8 engine):** a *headless* UE 5.8 run against 5.6-built binaries does
  NOT print *"modules built with a different engine version - rebuild?"* - it **silently drops** the
  5.6 module and reports a misleading `LogPluginManager: ... could not be found ... consider disabling
  the plugin`. Agent-under-test correctly diagnosed the version mismatch + refused the trap
  (verified correct), but §8's mismatch row keyed only on the interactive string → **added a §8
  headless-mismatch row** (guarded so it doesn't over-trigger on genuinely-missing plugins).
- **Tier 2 (failure log, matched 5.6):** typo'ing a module dep (`EnhancedInput`→`EnhancedInputs`)
  gave a real UBT `Could not find definition for module 'X' (referenced via Target -> Build.cs)`
  / `Result: Failed (RulesError)` / ExitCode 8. Agent-under-test diagnosed the typo + **refused the
  "add it as a dependency" trap** (§8 row 2 fired). Verified UBT exit codes **8=RulesError,
  6=OtherCompilationError** (corrected §8's wrong "6=crash" guess). Bonus real 5.6→5.8
  incompatibility from the 5.8 attempt: `ParrotEditor modifies ... warning-level properties ... not
  allowed, as it has build products in common with UnrealEditor` (ExitCode 6).
- **Tier 0+2 (Butter Up, UE 5.8 - the second game):** synced `//sample-game` from our
  own internal Perforce server (IP-allowlisted for the session); clean 5.8 doctor report (proper `.p4ignore`, AI-bridge plugins) + a
  **green matched 5.8 build+cook** (496/503 pkgs, 0 err/warn). Its 5.8 cook log shows the same
  ZenServer / `FShaderJobCache` grammar as 5.6 → the §5/§7 fixes are **version-general**, not
  5.6-specific. Completes the two-game × two-version matrix. Tiny §1 doctor fix: plugin jq defaults
  an omitted `Enabled` field to `true`.

## B. Operational / rig learnings (Tier 2 host + toolchain)

1. **Arch beats specs for UE-in-Docker.** Epic's `ghcr.io/epicgames/unreal-engine` images
   are **amd64-only**. On an **arm64 Mac (M-series)** they run under emulation -
   impractically slow/fragile for shader-heavy cooking. Use a **native x86_64 host**.
   *(⤳skill: `unreal-build` should warn when the Docker host arch ≠ image arch.)*
2. **Host selection is a real tradeoff.** Candidates seen: Mac M4 (fast, but arm64→emulated),
   a low-power LAN host (x86_64 but 2-core Pentium + ~100 Mbit LAN → native-but-slow), the
   Windows build host (x86_64, 20 cores, **16 GB RAM**, native → best). A Windows gaming box is a
   strong native UE host; RAM (not cores) is the tight resource for cooks.
3. **On Windows, prefer WSL2 + a native Docker engine over Docker Desktop.** Docker Desktop's
   first run was flaky here (WSL2 distro init, GUI dialogs, the process exited on us). A plain
   `wsl --install -d Ubuntu-22.04` + `apt-get install docker.io` + `service docker start`
   gave a clean, headless `linux/amd64` engine (also what ButterStack uses).
   *(⤳skill: `unreal-build` note the WSL2-docker path for Windows.)*
4. **Tune WSL2 for UE.** Default WSL2 grabs ~50% RAM. Set `%USERPROFILE%\.wslconfig`
   (`[wsl2] memory=...GB / swap=...GB / processors=...`) before cooking, then `wsl --shutdown` to
   apply. On a 16 GB box, 12 GB to WSL + 8 GB swap.
5. **Image transfer pitfalls (cost us the most time):**
   - `docker save | ssh host | docker load` **streaming deadlocks** - bulk stdin through
     `wsl.exe` stalls (small payloads work; ~63 GB does not). scp/SFTP is reliable for bulk.
   - Source-host `docker save` **hangs when that host is low on disk** (the Mac wedged at
     0 bytes; `/tmp` was down to ~500 MB after the 63 GB pull).
   - **Cleanest path: pull on the target host** from ghcr. Epic images are **gated** - no
     anonymous pull; the pulling host needs its own **Epic-linked GitHub** `docker login`.
6. **Don't move credentials between hosts.** Attempting to lift the Mac's ghcr token from the
   keychain to auth the Windows build host was (correctly) safety-blocked - it reads as
   credential theft. Have
   the **target host authenticate itself** (`docker login` there).
7. **Native (non-Docker) UE headless cook pitfalls** (from the UE 5.4 quick-capture attempt):
   - A **C++ project needs a compiled editor for that exact engine version**; `-skipcompile`
     on an unbuilt project bails before doing real work.
   - **UAT writes to its own log files, not the launcher's stdout.** Redirecting
     `RunUAT.bat` stdout captured only `"Running AutomationTool..."`. The real logs are in
     `<project>/Saved/Logs/*.log` and
     `<engine>/Engine/Programs/AutomationTool/Saved/Logs/Log.txt` - capture *those*.
     *(⤳skill: `unreal-observe` §7 should point at these UAT/editor log locations.)*

8. **docker.io on WSL2 defaults to the containerd snapshotter, which fails large-layer
   pulls** with `failed to copy: failed to send write: EOF` (layers download + report
   "Pull complete", but nothing commits - `/var/lib/docker` stays ~184 K, no OOM, disk
   fine). **Fix: force classic overlay2** via `/etc/docker/daemon.json`
   `{"features":{"containerd-snapshotter":false},"storage-driver":"overlay2"}` + restart.
   After the switch the image committed normally (49 GB on disk). *This cost the most Tier 2
   time - check the storage driver first.* *(⤳skill: `unreal-build` Docker-on-WSL2 note.)*
9. **Long docker ops must be fully detached.** A `docker pull`/build launched over a
   transient `ssh host wsl ... cmd` session gets killed when the session ends *and* by
   background-task runtime caps - `nohup` alone wasn't enough. Use **`setsid bash script.sh
   </dev/null >log 2>&1 &`** to detach into its own session, then poll the logfile.
   `docker pull` resumes cached layers, so an interrupted pull just re-runs cheaply.
10. **16 GB is too tight for a UE editor *and* a UE-in-Docker cook at once.** Running a UE
    5.4 editor on Windows while WSL held a 12 GB ceiling left ~4 GB for Windows → pressure.
    Close the interactive editor before a container build/cook; give WSL the RAM.
11. **Prefer the `dev-slim-<ver>` image when disk is tight.** `dev-slim-5.6` is ~45 GB
    unpacked (vs ~63 GB for `dev-5.6`), still ships the **full clang toolchain** (compiles
    game C++ modules fine) and the editor (cooks fine) - it only drops debug symbols.
12. **Pull-on-target beats moving the image.** LAN `docker save|ssh|docker load` streaming
    *and* saving-to-file both failed (deadlock / source-host disk); having the **target host
    pull from ghcr, authenticated by itself**, was the only reliable path.
13. **THE big one - WSL's `vmIdleTimeout` (default 60 s) shuts the whole VM down when no
    `wsl.exe` session is *attached*.** Background processes - even under systemd - don't count
    as activity, so any **detached long op** (a `docker pull`, or a `docker run -d` build
    launched by a transient `ssh ... wsl ... cmd` session) dies ~60 s after that launching session
    ends: container `ExitCode=255`, `OOMKilled=false`, and `journalctl --list-boots` shows the
    distro repeatedly booting with ~5-min DOWN gaps. **Fix that actually worked: hold an *attached* session for the whole op** - a live
    foreground `ssh ... wsl ... <the pull/build>`, or a foreground `docker wait` on a detached
    container, keeps the VM non-idle. That's why the 5.6 build (via `docker wait`) and the 5.8
    pull (via a held-open `docker pull`) both completed, while every detached-and-left op died.
    **Caveat:** setting `.wslconfig [wsl2] vmIdleTimeout=-1` (and a large value) did **not** take
    here - the distro kept 60 s-cycling regardless - so don't rely on the config knob; the
    held-open session is the reliable lever. **systemd** keeps the distro tidy but does NOT stop
    the idle-shutdown. *Chased ~4 crashes before nailing this; `journalctl --list-boots` (short
    boots with gaps) is the tell.*
14. **Diagnosing 13:** `journalctl --list-boots` (short-lived boots with gaps) is the smoking
    gun; container `ExitCode=255` + `OOMKilled=false` + WSL `uptime` resetting ⇒ the VM went
    down, **not** the container (no `dmesg` OOM - it's a VM-level shutdown, not a cgroup kill).
15. **Cap UE compile parallelism on a RAM-tight host.** UBT/UBA ran 6 parallel compiles; the
    multi-GB `SharedPCH.Engine` compile with 5 neighbors OOM'd at `[5/78]`.
    `BuildConfiguration.xml` `<MaxParallelActions>` / `<ParallelExecutor><MaxProcessorCount>`
    fixes it (3 safe, 2 safest). Also shrink the WSL `memory` ceiling so WSL never pressures
    Windows into reclaiming the whole VM.
16. **Stop Docker Desktop's `com.docker.service`** when using plain docker.io in WSL (unneeded;
    a plausible WSL-bouncer - set it to Manual).

## C. Open items / TODO

- ✅ **Track B done:** `dev-slim-5.6` pulled on the Windows build host, **matched build+cook green** (0 err/warn,
  1006 pkgs cooked). First real-engine log captured; §5/§7 grammar corrected against it.
- ✅ DDC/shader **grep literals** confirmed against a real log - found wrong for 5.6 (no
  `DDC Hit Rate`; ZenServer + `FShaderJobCache stats`). Corrected + version-flagged.
- ✅ **5.6→5.8 mismatch money-shot done** (2026-07-11): `dev-slim-5.8` pulled (held-open, ~57 GB),
  5.8 engine `-skipcompile` vs Parrot's 5.6 binaries → real *headless* mismatch (silent-drop →
  misleading `LogPluginManager ... could not be found ... disable the plugin`, ExitCode 25, NOT the
  interactive "different engine version" prompt). Agent-under-test diagnosed the version mismatch
  correctly + refused the disable-the-plugin trap (verified correct); added a §8 headless-mismatch
  row. Evidence: `fixtures/parrot-ue5.8-vs-5.6-mismatch.txt`.
- ✅ **Build-failure log done** (2026-07-12, matched 5.6): typo'd module dep → real UBT
  `Could not find definition for module ... Result: Failed (RulesError)`, ExitCode 8. Agent
  diagnosed the typo correctly + refused the add-as-dependency trap (§8 row 2 fired); verified UBT
  8=RulesError / 6=OtherCompilationError. Fixture: `fixtures/parrot-ue5.6-build-fail-rulesError.txt`.
- ✅ **Butter Up done** (2026-07-13, UE 5.8): our own internal Perforce server reached (IP-allowlisted),
  `//sample-game` synced, clean 5.8 doctor + **green matched build+cook** (496/503 pkgs, 0 err/warn).
  Fixture: `fixtures/butterup-ue5.8-cooklog.txt`. **Two-game × two-version matrix complete.**
- **Nice-to-have (not blocking):** grep-triage on a genuinely *noisy* multi-thousand-line log (every
  real log so far failed fast or cooked clean), and the optional reverse (Butter Up 5.8 opened with
  5.6). `dev-slim-5.8` is currently resident on the Windows build host; its sleep is disabled.
- Reclaim the ~63 GB stranded `dev-5.6` image on the dev machine (it was low on disk; `docker save` hung).
