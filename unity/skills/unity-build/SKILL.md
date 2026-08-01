---
name: unity-build
description: >
  Gated Unity CLI build/test/run playbooks - `unity build` (--target +
  --execute-method are required; Unity has no built-in command-line build),
  the C# build-method contract that defeats the batchmode exit-0 trap,
  `unity test` (EditMode/PlayMode, NUnit XML, --timeout off by default),
  `unity run` as the classic-batchmode escape hatch, Android signing-secret
  discipline, the gated flags (--allow-install, --allow-dirty-build), and
  verification + cost expectations. Use whenever actually building, testing,
  or running a Unity project. EVERY command here spawns the Editor and locks
  the project - show the exact command plus estimated cost and get
  confirmation before running. For read-only diagnosis use `unity-observe`;
  for the CLI surface itself use `unity-cli`.
---

# Unity Build, Test & Run

Concrete, copy-pasteable playbooks for the Unity CLI's batchmode trio.
Placeholders use `<ANGLE_BRACKETS>`. These commands work against **any** Editor
the CLI can resolve, **including 2022.3 LTS** - they are the whole build
surface on a 2022.x project (the Pipeline/MCP half needs Unity 6 -
`unity-cli` §5).

**Everything in this skill is gated.** A build/test spawns the Editor, locks
the project, and runs minutes to tens of minutes. Before running anything:
show the user the exact command line and what it costs (§7), and wait for
confirmation - the same show-then-confirm pattern the unreal and jenkins
agents use. Prefer the cheapest command that answers the question: an EditMode
test run before a platform build; yesterday's log (`unity-observe` §8) before
a re-run.

---

## 0. Preflight - run every time, before any invocation

1. **Doctor** (`unity-observe` §1-§7): Editor version resolved and routed,
   matching Editor installed, **license active** (`unity license status` -
   not `auth status`), project setup sane, no `Temp/UnityLockfile` held.
2. **One Editor per project.** If the GUI Editor has the project open, the
   batchmode run fails on the `Library/` lock. Ask the user to close it -
   never kill it.
3. **Clean working tree.** The CLI **refuses to build a dirty working tree by
   default** - that guard is a feature. If the tree is dirty, the fix is
   commit/stash; `--allow-dirty-build` only on explicit, confirmed request.
4. **Set `--timeout` on `test`/`run` in CI** - it is disabled by default and a
   hung PlayMode test hangs forever.
5. **Plan the verification before the run** (§6) - know which artifact path
   and which log you will check afterward.

## 1. `unity build`

```
unity build [options] [project]
```

Key flags (from the real `1.0.0-beta.2` `--help`):

- `--target <target>` - **required**. e.g. `StandaloneWindows64`, `Android`,
  `iOS`, `WebGL`.
- `--execute-method <method>` - **required**. A static C# method, e.g.
  `Builder.PerformBuild`. The help text says it outright: **"Required - Unity
  has no built-in command-line build."** The CLI does not build the game; the
  project's C# `BuildPipeline` code does. No build method in the project ⇒
  the answer is "write one first" (§2), not a command.
- `--build-target-group <group>` - forwarded as `-buildTargetGroup`.
- `-o, --output-path <path>` - forwarded as `-buildOutput`, and **"your
  executeMethod is responsible for honoring it"** - the CLI does not enforce
  it. Verify the artifact at the path the method actually writes.
- `-l, --log-file <path>` - default
  `<project>/Logs/build-<target>-<timestamp>.log`.
- `--editor-version <version>` - default read from
  `ProjectSettings/ProjectVersion.txt`. **Overriding it is a version change -
  gated** (one-way reserialization; `unity-observe` §4).
- `-e, --editor-path <path>`, `-a, --architecture <x86_64|arm64>`.
- `--args <string>` - extra args passed to Unity (shell-split).
- `--no-tail` - don't stream the log to stdout live (default IS tailing).
- `--allow-install` - **GATED**: installs the project's Editor version if
  missing - a silent multi-GB download. Name the cost and confirm first.
- `--allow-dirty-build` - **GATED**: skips the uncommitted-changes guard (§0.3).
- `--versioning-strategy <semantic|tag|custom|none>` (default `none`),
  `--build-version <version>` (only honored with `custom`).

Verbatim examples from `--help`:

```
unity build --target StandaloneWindows64 --execute-method Builder.PerformBuild
unity build ./MyGame --target Android --execute-method Builder.AndroidBuild --output-path ./out/app.apk
unity build "My Game" --target WebGL --execute-method Builder.WebGLBuild --editor-version 6000.0
unity build --target iOS --execute-method Builder.iOSBuild --allow-install --no-tail
```

## 2. The `--execute-method` contract - defeating the exit-0 trap

`BuildPipeline.BuildPlayer` returns a `BuildReport`; if the method doesn't
inspect it and exit honestly, **Unity exits 0 even though nothing was built**.
Any build method you write or fix must follow this shape (an Editor-only
script, e.g. `Assets/Editor/Builder.cs`):

```csharp
using System.Linq;
using UnityEditor;
using UnityEditor.Build.Reporting;

public static class Builder
{
    public static void PerformBuild()
    {
        var options = new BuildPlayerOptions
        {
            scenes = EditorBuildSettings.scenes.Where(s => s.enabled).Select(s => s.path).ToArray(),
            target = EditorUserBuildSettings.activeBuildTarget,   // honor --target, don't hardcode
            locationPathName = "<output path - honor -buildOutput / your convention>",
        };
        BuildReport report = BuildPipeline.BuildPlayer(options);
        if (report.summary.result != BuildResult.Succeeded)
            EditorApplication.Exit(1);   // WITHOUT this, a failed build exits 0
    }
}
```

- The method must be `public static`, parameterless, reachable after compile -
  a compile error anywhere in the project prevents it from ever running
  (`error CS####` in the log is upstream of everything).
- If asked to diagnose a "successful" build with no artifact, this contract is
  the first suspect (`unity-observe` §8).

## 3. `unity test`

```
unity test [options] [project]
```

- `--mode <EditMode|PlayMode>` - if omitted, the Editor's default test
  platform runs. EditMode is faster; PlayMode is closer to runtime.
- `--filter <pattern>` - match test names.
- `--output <path>` - NUnit XML report, default `test-results.xml`. Parse the
  XML for pass/fail counts, not the exit code.
- `--editor-version` (env `UNITY_EDITOR_VERSION`), `-e/--editor-path`,
  `-a/--architecture` (env `UNITY_ARCHITECTURE`), `--allow-install` (gated,
  §1).
- `--timeout <seconds>` - kill the Unity process after N seconds. **Disabled
  by default** (env `UNITY_TEST_TIMEOUT`) - always set it in CI or a hung
  PlayMode test hangs the pipeline forever.

Verbatim examples from `--help`:

```
unity test
unity test ./MyProject --mode EditMode
unity test "My Game" --mode PlayMode --output ./results/play.xml
unity test . --filter "MyNamespace.MyTests" --editor-version 6000.0
unity test . -- -nographics
```

Note the `--` passthrough form for raw Editor args (`-nographics`).

## 4. `unity run` - the classic-batchmode escape hatch

```
unity run [options] [project]
```

Same editor-resolution flags as `build`/`test`; `--timeout` (env
`UNITY_RUN_TIMEOUT`). Everything after `--` goes to the Editor verbatim:

```
unity run ./MyProject -- -executeMethod Builder.Build
unity run "My Game" --editor-version 6000.0 -- -nographics -quit
unity run . --allow-install -- -logFile ./build.log -quit
```

Use it when `build`/`test` don't fit (a custom commandlet, an asset import
pass, a package export). The exit-0 trap (§2) applies with full force here -
raw batchmode has no report contract at all unless your method provides one.

## 5. Android signing - secrets never inline

`unity build --target Android` supports `--android-export-type
<apk|aab|android-studio-project>`, `--android-target-sdk-version <N>`,
`--android-symbol-type <none|public|debugging>`, `--android-version-code <N>`,
and the signing set `--android-keystore-base64`,
`--android-keystore-password`, `--android-key-alias`,
`--android-key-alias-password`.

**Unity's own help warns: "CLI args may appear in shell history and CI
logs."** Never inline these values - reference environment variables populated
from the CI secret store:

```sh
unity build ./MyGame --target Android --execute-method Builder.AndroidBuild \
  --android-export-type aab \
  --android-keystore-base64 "$ANDROID_KEYSTORE_B64" \
  --android-keystore-password "$ANDROID_KEYSTORE_PASS" \
  --android-key-alias "$ANDROID_KEY_ALIAS" \
  --android-key-alias-password "$ANDROID_KEY_ALIAS_PASS"
```

Never echo these variables back, never write them into a script or log.

## 6. Verification - what "done" means

Never report success from the exit code alone. **This is not a theoretical
concern and `unity build` does not fix it** - demonstrated on the validation rig
(Unity 2022.3.62f3, CLI 1.0.0-beta.2):

```
# execute-method builds to an unwritable path and never checks the BuildReport
$ unity build --target StandaloneWindows64 \
      --execute-method Builder.PerformBuildSwallowFailure --no-tail
$ echo $?                       # -> 0
$ ls Z:/nope/Trap.exe           # -> does not exist
```

Exit `0`, nothing built. The CLI forwards the Editor's exit code and the Editor
has no complaint, because nothing in the user's method ever called
`EditorApplication.Exit(nonzero)`. Conversely a method that *does* check its
report surfaces as CLI exit **6** with the Editor's real code buried in stderr:
`Error: Build failed (exit 1). See log: ...`.

After a run:

```sh
# 1. Artifact exists (at the path the execute-method actually writes):
ls -la <output_path>

# 2. Log is clean (default: <project>/Logs/build-<target>-<timestamp>.log):
grep -n "Build completed with a result of 'Failed'" <log> && echo "FAILED despite exit code"
grep -n -iE "error CS[0-9]+" <log>

# 3. Tests: the NUnit XML, not the log:
grep -oE 'total="[0-9]+" passed="[0-9]+" failed="[0-9]+"' <results>.xml | head -1
```

Report what you observed: artifact path + size, build time, first error line
if any, test pass/fail counts, warnings - not "exit code 0".

## 7. Cost expectations & reporting

| Action | Typical cost |
|---|---|
| `unity test --mode EditMode`, small-to-medium project | ~1-5 min |
| `unity test --mode PlayMode` | ~2-15 min |
| `unity build`, warm `Library/` | ~2-15 min |
| `unity build`, cold `Library/` (fresh clone - full reimport first) | tens of minutes, project-size dependent |
| `--allow-install` (Editor missing) | multi-GB download + install on top of the build |
| Android/iOS with SDK/toolchain work | add platform toolchain time on top |

State the cost in the confirmation prompt; if a previous log exists, its
timestamps beat these estimates.

## Validation status

Command surface, flags, examples, and the licensing/exit-code behavior in this
skill were **verified against a real rig** (Unity CLI `1.0.0-beta.2`, Unity
2022.3.62f3, Windows 11, 2026-07) - flag names and help-text quotes are
verbatim from that binary. The C# contract in §2 is the standard
`BuildPipeline` pattern, not rig-verified in this pass. The CLI is beta:
re-check `unity <cmd> --help` when the CLI version differs, and prefer the
binary over this file.
