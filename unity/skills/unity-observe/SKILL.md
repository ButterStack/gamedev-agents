---
name: unity-observe
description: >
  Read-only Unity diagnostics - the project+Editor-version DOCTOR
  (ProjectSettings/ProjectVersion.txt FIRST, then the 2022-vs-Unity-6 CLI
  routing, installed Editors via `unity editors -i`, the license probe
  (`unity license status`, NOT `auth status`), project setup and
  Packages/manifest.json sanity, Library/lockfile/.meta hygiene) and build/test
  LOG diagnosis (the batchmode exit-0 trap, error CS grammar, NUnit XML
  reports). Use for inspecting and reasoning about a Unity project WITHOUT
  building or changing it. To run a build/test use `unity-build`; for the CLI
  surface itself use `unity-cli`.
---

# Unity Observe & Diagnose

Read-only playbooks for understanding a Unity project and its build output.
**Nothing here builds, imports, licenses, or mutates** - every command is safe
to run for inspection. Placeholders use `<ANGLE_BRACKETS>`. Always add
`--format json --no-banner --non-interactive` to `unity` invocations you parse.

Run §1-§5 (the doctor core) before ANY build the `unity-build` skill proposes -
validate before build.

---

## 1. Find the project & resolve its Editor version FIRST

This is the routing decision for everything else - do it before proposing any
CLI command:

```sh
# The project marker (a Unity project root has Assets/ + ProjectSettings/)
find . -maxdepth 3 -name "ProjectVersion.txt" -path "*/ProjectSettings/*"

# The version the project was last saved with - THE file to trust:
grep '^m_EditorVersion:' <proj>/ProjectSettings/ProjectVersion.txt
# e.g. m_EditorVersion: 2022.3.62f3
grep '^m_EditorVersionWithRevision:' <proj>/ProjectSettings/ProjectVersion.txt
# e.g. m_EditorVersionWithRevision: 2022.3.62f3 (96770f904ca7)  <- version (changeset)
```

- Version string form: `<major>.<minor>.<patch><release><build>` -
  `2022.3.62f3` = 2022 LTS; `6000.x.yfz` = Unity 6. `a`/`b`/`f` =
  alpha/beta/final.
- No `ProjectVersion.txt` ⇒ not a Unity project root, or you're a level off -
  widen the `find` or ask. Do not guess a version.

## 2. Route on the version - which half of the CLI exists here

| `m_EditorVersion` | CLI surface available |
|---|---|
| **2022.x** (or anything < 6000) | Batchmode half only: `build` / `test` / `run`, plus all Editor/license/project management (`install`, `editors`, `license`, `releases`, `doctor`, `diagnose`, ...). **No** `pipeline` / `command` / `list` / `status` / `mcp` - the `com.unity.pipeline` package requires Editor 6.0+. |
| **6000.x+** (Unity 6) | Everything above **plus** the live-Editor control plane and MCP, once `unity pipeline install` has run (`unity-cli` §8). |

On a 2022.x project, say the second half does not exist rather than suggesting
commands that will fail. This rig class (2022.3 LTS) is the primary path;
Unity 6 is the secondary path.

## 3. CLI presence & health

```sh
unity -V                                            # CLI version (beta: e.g. 1.0.0-beta.2)
unity doctor --format json --no-banner --non-interactive    # CLI-environment diagnostics
unity diagnose                                      # paste-safe redacted support output
```

- No `unity` on PATH ⇒ the CLI isn't installed (or the terminal predates the
  install - Windows installs to `%LOCALAPPDATA%\Unity\bin\unity.exe` and needs
  a restart). Installing it is quick but still a change - `unity-cli` §2 has
  the verified lines; confirm before running an installer.
- The CLI is beta: when this skill and `unity <cmd> --help` disagree, the
  binary wins - report the drift.

## 4. Resolve installed Editor(s) and compare

```sh
unity editors -i --format json --no-banner --non-interactive   # installed Editors
unity editors info <version>                                   # details incl. modules
unity editors path <version>                                   # install dir
unity editors -r                                               # currently promoted releases
```

**Compare** `m_EditorVersion` against the installed list:

- Exact match -> OK, use it.
- **Only a newer Editor installed** -> opening (and especially saving)
  reserializes the project forward, **one-way** - an older Editor then can't
  read it. Name it as a decision; never silently build with "whatever's
  installed" via `--editor-version`.
- **Only an older Editor installed** -> generally unsafe; Unity often refuses.
  Propose installing the matching version instead.
- **Not installed at all** -> a gated `unity install` (multi-GB). If the
  version is archived (anything `editors -r` doesn't list - on a 2026 Hub that
  is everything pre-Unity-6), it needs an explicit changeset:
  `unity install 2022.3.62f3 -c 96770f904ca7`. The changeset is even sitting
  in `m_EditorVersionWithRevision` (§1) - or query the release API
  (`unity-cli` §6).
- **Watch for stub installs**: a `Hub/Editor/<version>/` directory containing
  only `modules.json` and no Editor executable is a leftover Hub registration,
  not an install (observed in the wild). `unity editors info <version>` +
  checking the executable exists beats trusting the directory listing.

No Editor at all on a box that only edits/offloads builds is a fact to report
("can't build locally; builds run on <node>"), not a project defect.

## 5. License probe - status, not auth

```sh
unity license status --format json --no-banner --non-interactive
unity license list --format json --no-banner --non-interactive
unity auth status        # cloud login only - NOT a license probe
```

- **`license status: active` with `Signed in: no` is a healthy, normal CI
  state** - batchmode runs off the machine license file
  (`C:\ProgramData\Unity\Unity_lic.ulf` on Windows). Verified on a real rig:
  active Personal ULF, nobody signed in.
- Do not conclude "unlicensed" from `auth status` saying "not signed in" -
  that is the most likely wrong diagnosis on this path. `auth login` matters
  only for the Pipeline package (Unity 6) and cloud/org features.
- If `license status` genuinely shows no active license, activation is a
  **gated** step (consumes a seat) - hand off to the agent's gate, don't run
  `unity license activate` from a doctor.

## 5b. `unity projects info` - one call instead of five

Before hand-parsing project files, try the CLI's own summary. `unity projects
info [pathOrName]` (defaults to the current directory) returns, in one call, most
of what §1/§4/§6 otherwise assemble by hand:

```
$ unity projects info C:\work\Unity63Probe
Title:            Unity63Probe
Path:             C:\work\Unity63Probe
Editor version:   6000.3.20f1
Project GUID:     875a937b1a3c11a4aa0a694dd010febf
Architecture:     x86_64
Last modified:    2026-07-22 22:19
Build target:     StandaloneWindows64
Scripting backend:(default Mono2x)
Render pipeline:  Built-in
Favorite:         No
Cloud project:    -
Organization:     -
VCS provider:     -
Repository:       -
Packages (37):
  com.unity.modules.accessibility   1.0.0
  ...
```

**Scripting backend** and **render pipeline** in particular are expensive to
derive from files (they live in `ProjectSettings/ProjectSettings.asset`, a YAML
blob) and both materially change build behaviour and build time. Add `--format
json` to parse it.

Caveat: this reads the **Hub registry**, so it only covers projects the Hub knows
about. Register one with `unity projects add <path...>` (`projects list` /
`projects remove` alongside it; `remove` de-registers and does **not** delete
files). For an unregistered project, fall back to the file-level checks below.

## 6. Validate project setup

```sh
PROJ_DIR="<proj>"
test -d "$PROJ_DIR/Assets"          || echo "ISSUE: missing Assets/"
test -d "$PROJ_DIR/ProjectSettings" || echo "ISSUE: missing ProjectSettings/"
test -f "$PROJ_DIR/Packages/manifest.json" || echo "note: no Packages/manifest.json - pre-UPM or unusual layout"

# Direct dependencies + any local/git package refs:
jq -r '.dependencies | to_entries[] | "\(.key) \(.value)"' "$PROJ_DIR/Packages/manifest.json" 2>/dev/null

# Resolved versions actually in use (if present):
jq -r '.dependencies | to_entries[] | "\(.key) \(.value.version // .value)"' \
  "$PROJ_DIR/Packages/packages-lock.json" 2>/dev/null

# Is there a CLI-invokable build method? (unity build REQUIRES one - see unity-build §2)
grep -rl "BuildPipeline.BuildPlayer" "$PROJ_DIR/Assets" --include="*.cs" 2>/dev/null

# Can this project run tests at all? (unity test REQUIRES the test framework)
jq -e '.dependencies["com.unity.test-framework"]' "$PROJ_DIR/Packages/manifest.json" >/dev/null 2>&1 \
  || echo "ISSUE: com.unity.test-framework absent - unity test has nothing to run"
```

**Test-framework precondition.** A project created by `-createProject` (and some
minimal//trimmed projects) ships **only `com.unity.modules.*`** - no
`com.unity.test-framework`. Two consequences, both rig-confirmed:

- `unity test` has no runner and cannot do anything useful.
- If the project nonetheless contains a test assembly (`.asmdef` referencing
  `UnityEngine.TestRunner`/`UnityEditor.TestRunner`), the missing package turns
  into `error CS0246: ... 'NUnit' could not be found`, which fails the **player
  build** as well - a broken test assembly is not isolated from `unity build`.

So check this *before* proposing `unity test`, and treat it as an issue rather
than a warning when tests were requested.

Report **issues** (missing `Assets/`/`ProjectSettings/`, unparseable
`ProjectVersion.txt`, no build method when a build was requested) separately
from **warnings** (version mismatch, a `file:`/git dependency with no lock
entry) - issues block a build, warnings need a human judgment call.

## 7. Library / lockfile / .meta hygiene

```sh
# Library/ is a fully regenerable cache - never committed, safe to delete
# (but deletion costs a full reimport; the agent confirms it first).
du -sh "$PROJ_DIR/Library" 2>/dev/null

# Is another Editor/batchmode process holding this project? One Editor per
# project directory - a second one hits the Library lock and fails.
test -f "$PROJ_DIR/Temp/UnityLockfile" && echo "LOCKED: another process likely holds this project"
lsof "$PROJ_DIR/Temp/UnityLockfile" 2>/dev/null    # who holds it (Linux/Mac)

# .meta discipline: every asset file should have exactly one .meta beside it.
# A missing .meta = Unity will regenerate a NEW GUID (references break);
# an orphaned .meta = its asset was removed outside Unity.
find "$PROJ_DIR/Assets" -name "*.meta" | wc -l
find "$PROJ_DIR/Assets" -type f ! -name "*.meta" | wc -l   # rough pairing check

# Regenerable dirs that must never be committed (the perforce plugin's Unity
# P4IGNORE preset agrees): Library/ Temp/ Logs/ obj/ Builds/ UserSettings/
```

- Lockfile held + a build request ⇒ **stop and ask** - never race a second
  process onto the project, never kill the user's Editor.
- `Library/` missing (fresh clone) ⇒ the first build/open reimports everything
  from scratch - slow but expected, not an error.
- Never `rm` a `.meta` file and never let a tool do it - the bundled
  `guard-unity` hook hard-blocks it. Asset renames/moves belong to the Editor
  or source control so the `.meta` travels with the asset.

## 8. Build/test log & report diagnosis

Where to look:

- `unity build` logs to `<project>/Logs/build-<target>-<timestamp>.log` by
  default (`-l/--log-file` overrides) and **tails it to stdout live** unless
  `--no-tail` was passed.
- `unity test` writes an NUnit XML report - default `test-results.xml`,
  `--output <path>` overrides.
- Classic batchmode runs (via `unity run ... --` or direct Editor invocation)
  log wherever `-logFile` pointed; the OS-default `Editor.log` locations are
  macOS `~/Library/Logs/Unity/Editor.log`, Linux `~/.config/unity3d/Editor.log`,
  Windows `%LOCALAPPDATA%\Unity\Editor\Editor.log`.

**The exit-0 trap, restated for log reading**: the Editor exits 0 once it
quits cleanly - regardless of whether the build the `--execute-method` was
supposed to perform succeeded - unless that method inspected
`report.summary.result` and called `EditorApplication.Exit(1)`. Do not stop at
the exit code:

```sh
grep -n "Build completed with a result of 'Failed'" <log>   # the build-report failure line
grep -n -iE "error CS[0-9]+" <log>                          # C# compile errors - block everything downstream
grep -n -iE "Exiting batchmode successfully" <log>          # Editor quit cleanly - NOT build success by itself
grep -n -iE "Aborting batchmode|Multiple Unity instances" <log>   # lock / concurrent-instance conflicts
ls -la <output_path>                                        # does the artifact actually exist?
```

For tests, parse the NUnit XML, not the log:

```sh
grep -oE 'result="[^"]*"' <results>.xml | sort | uniq -c    # quick pass/fail tally
grep -oE 'total="[0-9]+" passed="[0-9]+" failed="[0-9]+"' <results>.xml | head -1
```

- `error CS####: <message>` - a real compile error; report the file:line, and
  note that import, build, and tests are all blocked until it's fixed.
- A run that never reaches the end and never errors ⇒ suspect a hung
  test/dialog with no `--timeout` set (it is off by default - `unity-build`
  §3), or the lock conflict (§7).

### Failure signatures (rig-confirmed on 2022.3.62f3)

Each of these was reproduced on the validation rig; the log phrasing is verbatim.

| Signature in the log | What it actually means | Fix |
|---|---|---|
| `result=Unknown`, `size=0`, `DisplayProgressNotification: Build Failed`, no `error CS` anywhere | The build was handed an **empty scene list** (`BuildPlayerOptions.scenes = new string[0]`). Unity aborts before producing anything and never emits a tidy named error. | Populate `scenes` - from `EditorBuildSettings.scenes`, or explicitly. |
| `error CS0246: The type or namespace name 'NUnit' could not be found` (and `TestAttribute`/`Test`) | The project has a test assembly but **`com.unity.test-framework` is not in `Packages/manifest.json`**. A bare `-createProject` project ships only `com.unity.modules.*`. | Add `com.unity.test-framework` to the manifest. |
| `*** Tundra build failed (N seconds)` + `## Script Compilation Error for: Csc ...` + `Scripts have compiler errors.` | The **script compile** failed, so nothing downstream ran. Note this fails the *player build* too, not just the test run - a broken test assembly breaks `unity build`. | Fix the compile error; re-read the `error CS` lines above it. |
| `Could not find Unity Package Manager local server application at ...UnityPackageManager.exe. Missing files could be the result of an antivirus action or a corrupt Unity installation` | Usually **not** corruption or antivirus: most often an **incomplete install** that is still unpacking. `Unity.exe` appears well before a Hub install finishes. | Wait for the installer process to exit, then re-check; only then suspect AV. |

A useful invariant when triaging: a **compile** failure names files and `error CS`
codes; a **build** failure names a `BuildReport` result. If you see neither, and
the process still failed, suspect the empty-scene case or a licence/lock problem
rather than the user's code.

## Example - a filled doctor briefing

> **Doctor: MyGame @ /ws/MyGame - healthy, batchmode-only CLI surface**
> - Project: `ProjectVersion.txt` -> `m_EditorVersion` **2022.3.62f3**
>   (changeset `96770f904ca7`) -> **2022 LTS: CLI batchmode half only - no
>   pipeline/command/mcp on this project** (Editor 6.0+ required)
> - CLI: `unity` 1.0.0-beta.2 on PATH; `unity doctor` clean
> - Editors: 2022.3.62f3 installed (matches exactly); modules: Windows IL2CPP
>   present, no Android
> - License: **active** - Unity Personal (ULF); signed in: no (normal - auth
>   is not the license)
> - Setup: `Assets/` ok, `ProjectSettings/` ok, `Packages/manifest.json` ok
>   (14 deps, all locked); build method found: `Builder.PerformBuild`
> - Hygiene: `Library/` 3.1G (warm), no `Temp/UnityLockfile` - safe to build

(Shape mirrors the `unreal-observe` doctor briefing; numbers illustrative.)

## Caveats

- **The CLI is beta** - when the installed binary's `--help` disagrees with
  any command form here, the binary wins; report the drift so the skill can be
  updated.
- **Version-compatibility judgment is deliberately conservative** - always
  surface the one-way-reserialization consequence of a newer Editor and let
  the human decide.
- **Log-derived diagnosis is only as good as what the build method logs** - a
  build script that swallows its own errors defeats §8; the durable fix is the
  `--execute-method` contract in `unity-build` §2.
- The `.meta` pairing check in §7 is a rough count, not an exact audit -
  folder `.meta` files and hidden-file rules make the two numbers legitimately
  differ; use it to spot gross drift, not as a per-file verdict.
