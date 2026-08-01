---
description: Run a gated Unity CLI build - preflight doctor, the required --execute-method, cost confirmation, and artifact+log verification (never exit code alone)
argument-hint: "[target] [output-path]"
---

Guide the user through a safe, gated `unity build` per `$ARGUMENTS` (target,
output path - ask if ambiguous). Use the `unity-build` skill for exact command
forms and the flag table.

Steps:

1. **Preflight** (`unity-build` §0): run the doctor core (`unity-observe`
   §1-§7) - Editor version resolved, matching Editor installed, **license
   active** (`unity license status`, not `auth status`), no
   `Temp/UnityLockfile` held. If the GUI Editor has the project open, ask the
   user to close it; never kill it.
2. **Confirm a build method exists** - `--execute-method` is required; Unity
   has no built-in command-line build. No static build method in the project
   ⇒ the deliverable is writing one (the §2 contract: check
   `report.summary.result`, call `EditorApplication.Exit(1)` on failure) -
   propose that first, don't invent a method name.
3. **Respect the CLI's own guards** - a dirty working tree is refused by
   design: the fix is commit/stash, and `--allow-dirty-build` only on the
   user's explicit say-so. A missing Editor version is a gated
   `--allow-install` (multi-GB) or a gated `unity install ... -c <changeset>`
   for archived versions - name the download before running either.
4. **Show, then confirm** - print the exact command line (e.g.
   `unity build --target StandaloneWindows64 --execute-method Builder.PerformBuild`)
   plus an estimated cost (`unity-build` §7 - a cold `Library/` means a full
   reimport first) and **wait for explicit confirmation** before running.
5. **Run and capture** - the CLI tails the log to stdout by default; the log
   lands at `<project>/Logs/build-<target>-<timestamp>.log` unless
   `--log-file` overrides. For Android, signing secrets come from env/CI
   secret store - never inline (`unity-build` §5).
6. **Verify and report observed results** (`unity-build` §6): the artifact
   exists at the path the build method writes, the log has no
   `Build completed with a result of 'Failed'` and no `error CS####` - never
   report success from the exit code alone (the batchmode exit-0 trap).
   Report artifact path + size, build time, warnings/errors.

If the build fails (or "succeeds" with no artifact), classify it with the
agent's failure table (the exit-0 trap, a compile error, a dirty-tree
refusal, a version mismatch, a missing module, a license problem) and explain
the underlying concept, then propose the targeted fix - don't just re-run.

**Example:** *"Build the Windows player."* -> doctor, `Builder.PerformBuild`
found, tree clean, then propose
`unity build --target StandaloneWindows64 --execute-method Builder.PerformBuild`,
confirm, run, and report "player at Builds/Win64/ (412 MB), 6m12s, 0 errors /
3 warnings - artifact verified, not just exit 0".
