---
description: Diagnose an Unreal project + engine install - version match, project setup, BuildId/plugin hygiene, DDC/ignore hygiene, editor-running, MAX_PATH
argument-hint: "[path-to-.uproject-or-project-dir]"
---

Run the read-only engine+project doctor for the user, scoped to `$ARGUMENTS` if a
project path is given (else find the `.uproject` in the current tree). Run no
build and mutate nothing. Use the `unreal-observe` skill (§1-§6) for the exact
command forms - `.uproject`, `Build.version`, and `.modules` are JSON, so prefer
`jq`.

Check and report, in order:

1. **Project & association** - locate the `.uproject`; read `EngineAssociation`
   and say which form it is: version string (portable), source-build **GUID**
   (per-machine; flag a committed GUID - it breaks teammates), or empty.
2. **Engine & version match** - resolve the engine install (never guess the
   path), read `Engine/Build/Build.version`, and compare. **Any mismatch is a
   headline warning**: opening *and saving* a project in a newer engine re-saves
   assets forward one-way (rebuilding binaries is reversible; the asset re-save is
   not). Note installed vs source build (`InstalledBuild.txt`).
3. **Project setup** - `Source/` (else Blueprint-only), `Content/`,
   `Config/DefaultEngine.ini` (missing = blocking issue), and the build targets +
   `TargetType` from `Source/*.Target.cs`.
4. **BuildId / plugin hygiene** - compare `.modules` BuildIds (engine vs project
   vs plugins); a mismatch means silently-dropped modules or the "built with a
   different engine version" prompt.
5. **DDC & ignore hygiene** - where the DerivedDataCache points (cold/local-only
   DDC on a build node = hours of shader compiles), and whether generated dirs
   (`Binaries/ Intermediate/ Saved/ DerivedDataCache/`) are P4IGNOREd -
   cross-reference the perforce plugin's presets rather than restating them.
6. **Environment** - is the editor running (blocks builds - report, don't kill),
   and on Windows-rooted projects the MAX_PATH check (longest generated path vs
   the 260-char limit).

Present a concise briefing separating **issues** (block a build) from
**warnings** (need a human call), each with its one-line fix and where the
consequence bites. If the doctor surfaces work (a rebuild, an upgrade decision, a
DDC/ignore change), name it and hand off to `unreal-build` /
`unreal-editor-scripting` / the perforce plugin - do not mutate anything here.

**Example:** *"Is this project healthy?"* → project is 5.4 (version string),
engine is 5.6.1 source build → warn about the one-way upgrade before anyone opens
it; targets found; one plugin's BuildId is stale; no P4IGNORE; editor not running.
