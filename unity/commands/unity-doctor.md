---
description: Diagnose a Unity project + CLI + Editor install - version routing (2022 vs Unity 6), installed Editors, license status, project setup, Library/lockfile/.meta hygiene
argument-hint: "[path-to-project-dir]"
---

Run the read-only Unity doctor for the user, scoped to `$ARGUMENTS` if a
project path is given (else find `ProjectSettings/ProjectVersion.txt` in the
current tree). Run no build and mutate nothing. Use the `unity-observe` skill
(§1-§8) for the exact command forms; always pass
`--format json --no-banner --non-interactive` to `unity` invocations you parse.

Check and report, in order:

1. **Project & Editor version FIRST** (`unity-observe` §1) - read
   `m_EditorVersion` (and the changeset in `m_EditorVersionWithRevision`).
   This is the routing decision for everything else; if it can't be read,
   stop and ask.
2. **Route the CLI surface** (§2) - 2022.x (or anything < 6000): batchmode
   half only, and say so explicitly (no `pipeline`/`command`/`status`/`mcp` -
   they need Editor 6.0+). 6000.x+: the full surface, Pipeline-package state
   included.
3. **CLI presence & health** (§3) - `unity -V`, `unity doctor`. The CLI is
   beta; note the installed version.
4. **Installed Editors & match** (§4) - `unity editors -i --format json`
   against `m_EditorVersion`. Exact match ok; newer-only = named one-way
   reserialization risk; missing = a gated install (archived versions need
   `-c <changeset>`). Watch for stub installs (a version dir with only
   `modules.json` and no executable). Check target modules if the user cares
   about a specific platform.
5. **License** (§5) - `unity license status`, and report it correctly:
   "active + not signed in" is a healthy CI state. Never diagnose "unlicensed"
   from `unity auth status`.
6. **Project setup** (§6) - `Assets/`, `ProjectSettings/`,
   `Packages/manifest.json` + lock sanity, and whether a CLI-invokable build
   method exists (without one, `unity build` has nothing to run).
7. **Hygiene** (§7) - `Library/` size/presence (fresh clone = slow first
   build), `Temp/UnityLockfile` held or not, rough `.meta` pairing.

Present a concise briefing separating **issues** (block a build) from
**warnings** (need a human call), each with its one-line fix. If the doctor
surfaces work (an Editor install, a license activation, a build-method to
write, a Library wipe), name it and hand off to `unity-build` / `unity-cli` /
the perforce plugin - do not mutate anything here.

**Example:** *"Is this project healthy?"* -> project is 2022.3.62f3 ->
batchmode-only CLI surface; Editor installed and matching; license active
(ULF, not signed in - normal); build method found; no lock - safe to build.
