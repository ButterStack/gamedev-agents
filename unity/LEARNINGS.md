# Unity Agent - Validation Learnings (running log)

Companion to [`NOTES.md`](./NOTES.md) (design rationale and a summary of what's been
live-validated). Same split as the unreal plugin:

- **(A) Agent/skill learnings** - things the plugin would have got *wrong* if it had
  been written from the documentation. These **graduate into the skills**; that is
  the whole feedback loop.
- **(B) Operational/rig learnings** - the reality of standing up a Unity rig. Mostly
  not skill material, but a few graduate (flagged ⤳skill).

> No secrets - reference credential *locations*, never paste them.

## A. Agent / skill learnings (baked into the skills)

- **A1 - The documented Windows install line does not work.** Unity's own
  "Use the Unity CLI" page gives the *same* `curl ... | UNITY_CLI_CHANNEL=beta bash`
  line for macOS, Linux **and Windows (PowerShell)**. There is no `bash` in a stock
  PowerShell. There *is* an **undocumented `install.ps1`** at the same CDN path which
  is the real Windows installer (verifies SHA-256, installs to
  `%LOCALAPPDATA%\Unity\bin`). Found by probing the CDN, not by reading docs.
  → `unity-cli` §2 carries the per-platform lines, with the PowerShell one marked as
  undocumented-but-correct.

- **A2 - The published CLI reference omits most of the CLI.**
  `docs.unity.com/.../unity-cli-reference` lists only the Hub-ish commands
  (`install`, `editors`, `auth`, `projects`, `open`, ...). The actual `1.0.0-beta.2`
  binary additionally has **`build`, `test`, `run`, `doctor`, `diagnose`, `license`,
  `mcp`, `command`, `status`, `list`, `pipeline`, `shell`, `templates`, `cache`,
  `hub`, `env`, `config`, `modules`**. An agent built from that page would have
  concluded the Unity CLI cannot build or test anything - which is exactly what the
  first-pass attempt at this plugin concluded, and why it fell back entirely to raw
  `-batchmode`. → `unity-cli` §3 states the surface and instructs deriving it from
  `unity <cmd> --help` on the box, because the binary is beta and moving.

- **A3 - Exit codes are not `0`/`1`/`130`.** The docs list exactly three. The binary
  returns **`6`** for at least three different failures: a build whose Editor exited
  non-zero, `status` with no connected Editor, and `list`/`pipeline install` with no
  reachable Pipeline server. Worse, **the CLI's exit code is not the Editor's**: a
  build where the Editor exited `1` surfaces as CLI exit `6`, with the Editor's real
  code appearing only inside the stderr string
  `Error: Build failed (exit 1). See log: <path>`. Any agent branching on `== 1`
  would silently mis-handle every real failure. → `unity-cli` §4 rewritten: treat any
  non-zero as failure, read stderr, never map CLI code to Editor code.

- **A4 - "Not signed in" is not "unlicensed".** The rig has an **active Unity
  Personal ULF** and *nobody signed in*; `unity auth status` says
  "You are not signed in", while `unity license status` says `License: active`.
  Batchmode builds work fine. The obvious-looking probe (`auth status`) is the wrong
  one, and acting on it would send every build-node user through a pointless browser
  login. → `unity-observe` and `unity-cli` §7 both probe `license status`; the agent
  prompt calls this out as a named failure mode.

- **A5 - The exit-0 trap survives the new CLI.** The classic Unity CI footgun -
  batchmode exits 0 on a failed build unless your `-executeMethod` says otherwise -
  is *not* fixed by `unity build`. Directly demonstrated: a build method targeting an
  unwritable path returned **exit 0 with no artifact produced**. The wrapper forwards
  the Editor's code and the Editor has nothing to complain about. This was the
  single most valuable thing to have actually run rather than assumed, because the
  natural assumption is that a purpose-built `unity build` command would have solved
  it. → `unity-build` §2 (the C# contract) and §6 (verify artifact + log, never the
  exit code).

- **A6 - `ProjectVersion.txt` carries the changeset.** `m_EditorVersionWithRevision:
  2022.3.62f3 (96770f904ca7)`. Archived Unity versions need `unity install -c
  <changeset>`, and in 2026 every 2022.3 is archived (`unity editors -r` lists only
  promoted Unity 6 releases). So the exact install command is derivable from the
  project file alone, no release-API lookup. → `unity-observe` §2.

- **A7 - The Unity 6 boundary is enforced, quotable, and safe.** Rather than leaving
  the routing rule as an inference from the package docs, it was exercised:
  `unity pipeline install` against a 2022.3 project returns
  `Error: Pipeline package requires Unity 6.0 or higher.` (exit 6) and leaves
  `Packages/manifest.json` **byte-identical**. Meanwhile `unity pipeline list`
  *works* on 2022.3 (exit 0, `Pipeline=false`) while `status`/`list` exit 6. The
  half-degraded behaviour is not something you would guess. → `unity-cli` §8 now
  carries the verbatim outputs.

- **A8 - A bare Unity project cannot run tests.** `-createProject` yields a manifest
  with **only `com.unity.modules.*`** - no `com.unity.test-framework`. `unity test`
  against such a project has no test framework to run, and adding an EditMode asmdef
  that references `UnityEngine.TestRunner` produces
  `error CS0246: The type or namespace name 'NUnit' could not be found` - which
  fails the *player build* too, not just the test run. → `unity-observe` treats a
  missing `com.unity.test-framework` as a named precondition before proposing
  `unity test`.

- **A9 - Output format changes when you pipe.** `--format` defaults to `human` on a
  TTY but **silently switches to `tsv` when redirected or piped**. An agent that
  eyeballs a command interactively and then scripts the same command gets different
  bytes. → every parsed invocation in the skills passes
  `--format json --no-banner --non-interactive` explicitly.

- **A10 - Zero-scene builds fail opaquely.** `BuildPlayerOptions.scenes = new
  string[0]` gives `result=Unknown`, `totalSize=0`, and
  `DisplayProgressNotification: Build Failed` - no tidy error string naming the
  cause. Worth recognising as a signature, since it is a common mistake in
  hand-rolled build scripts. → `unity-observe` failure-signature table.

- **A11 - `pipeline install` does not require sign-in.** Unity's Pipeline docs give
  the setup order as `unity auth login` then `unity pipeline install`, which reads
  as a hard prerequisite. On Unity 6.3 with **nobody signed in**, `pipeline install`
  returned exit 0 and added `com.unity.pipeline 0.3.1-exp.1` to the manifest on the
  machine ULF alone. Third instance today of the docs being wrong (see A1, A2, A3).
  → `unity-cli` §8: do not gate the Pipeline path behind a browser login.

- **A12 - `auth login` has an undocumented headless path.** The reference page
  describes `auth login` as "opens a browser-based sign-in flow" full stop. The
  binary's own help exposes `--client-id` with `--client-secret`,
  `--secret-from-stdin`, and `--no-store` for **service-account** sign-in. Unity's
  help explicitly recommends `--secret-from-stdin` because it "keeps it out of
  argv / ps" - the same leak class as the `--android-keystore-*` flags. So the
  correct advice for a CI user is never "open the browser". → `unity-cli` §7 now
  carries a three-way decision tree: machine ULF for batchmode (no login at all),
  service account for login-requiring features headlessly, browser as a
  workstation-only fallback.

- **A13 - The batchmode path is genuinely version-agnostic.** The same `Builder.cs`
  and the same test assembly, unmodified, produced the same results on 2022.3.62f3
  (651 KB artifact) and 6000.3.20f1 (652 KB), tests 2/2 both times. That is what
  justifies the agent's structure: `build`/`test`/`run` need **no** version routing,
  and version routing is reserved for the Pipeline half alone. Worth stating
  positively rather than leaving implied.

- **A14 - Hub sign-in and CLI sign-in are different things.** With a real account
  signed into the **Unity Hub desktop app**, `unity auth status` still reported
  "You are not signed in" - while `unity license status` simultaneously gained two
  new entries (`Unity Personal (Assigned)`, `Asset Store (Assigned)`) alongside the
  existing `Unity Personal (ULF)`. So the Hub login propagates **entitlements** to
  the licensing client but does **not** create a CLI session. A user insisting "I am
  signed in" may mean the Hub; the agent must probe rather than believe it. This
  also surfaced that licence **`type`** carries real meaning: `ULF` is machine-bound
  and survives sign-out, `Assigned` is account-attached and does not. → `unity-cli`
  §7 reports type alongside product.

- **A15 - There is a SECOND exit-0 trap, in `unity command`.** Having already found
  that batchmode builds exit 0 on failure (A5), the same shape turned up again in
  the Pipeline path: `unity command` exits **0** whenever the *transport* succeeded,
  even when the tool itself returned `"success": false`. Observed with a malformed
  `set_quality_settings`: outer `Success=true`, inner `"success":false`, exit 0.
  The asymmetry is the subtle part - a **validation** failure (missing `confirm`)
  comes back as `400 Bad Request` with exit **6**, while a **semantic** failure
  inside the tool comes back as exit **0**. Two different failure classes, two
  different signals, one rule: **parse the payload, never the exit code.**
  → `unity-pipeline`, cross-referenced from `unity-build`.

- **A16 - Unity's Pipeline tools carry their own confirm/dry_run gate, enforced
  server-side.** 29 of the 140 tools take a `confirm` parameter, 40 take `dry_run`,
  and the descriptions distinguish reversible ("reversible via Undo", "one Undo
  step") from irreversible ("Not undoable via Ctrl+Z"). The gate is real, not
  advisory:
  `unity command clear_navmesh` without confirm returns
  `400 Bad Request: Parameter Validation Failed. Refusing to clear the NavMesh.
  Pass confirm=true (destructive, not undoable via Unity's Undo).`
  This is a genuinely useful discovery for the agent's posture: Unity independently
  arrived at the same read-first design, so the agent's own rule ("never pass
  `confirm=true` on the user's behalf, prefer `dry_run` first") sits on top of an
  enforced floor rather than being the only thing standing between a user and a
  destroyed lightmap. → `unity-pipeline`.

- **A17 - `unity projects info` replaces a pile of hand-parsing.** One call returns
  Editor version, project GUID, architecture, build target, **scripting backend**,
  **render pipeline**, and the full resolved package list. Scripting backend and
  render pipeline in particular otherwise require reading
  `ProjectSettings/ProjectSettings.asset`, a YAML blob, and both materially affect
  build time and behaviour. Caveat: it reads the **Hub registry**, so it only covers
  registered projects - `unity projects add <path...>` registers one. →
  `unity-observe` §5b, with the file-level checks kept as the fallback.

- **A18 - Unity 6 has two build paths, and they are not interchangeable.** Batchmode
  (`unity build`, cold Editor, works on 2022.3 and 6.x, CI-shaped, subject to A5)
  versus Pipeline (`unity command build` + `build_status` polling against an
  already-running Editor, warm, no domain-reload cost, Unity 6 only, and it mutates
  the Editor the developer is sitting in front of). Related: `list_build_targets`
  reports `isInstalled` per target, which is the correct precondition check before
  proposing any platform build and maps straight onto `unity install-modules`.
  → `unity-pipeline`, cross-referenced from `unity-build`.

## B. Operational / rig learnings

- **B1 - The Hub's editor directory lies.** `C:\Program Files\Unity\Hub\Editor\
  2022.3.14f1` existed with a **single `modules.json` and 0 MB** - the residue of an
  install that never happened. `unity editors -i` correctly ignored it. So "is Unity
  installed?" cannot be answered by looking for a version directory; look for
  `Editor\Unity.exe` (Windows) or ask the CLI. ⤳skill (`unity-observe` names this
  divergence as a doctor signature).

- **B2 - `Unity.exe` is a GUI-subsystem binary, so PowerShell does not wait for it.**
  `& $unity -batchmode -quit ...` returns *immediately* with an empty
  `$LASTEXITCODE`, and a script that checks results next line sees nothing. Use
  `Start-Process -Wait -PassThru` and read `.ExitCode`. Cost one confusing
  "PROJECT NOT CREATED" before it was spotted. (The `unity` CLI itself does block
  correctly - this only bites when driving `Unity.exe` directly.)

- **B3 - Unity Hub writes `Unity.exe` long before the install is finished.** A
  readiness check that waits for `Unity.exe` to appear fires while the installer is
  still unpacking, and the resulting Editor is genuinely broken - it fails with
  `Could not find Unity Package Manager local server application at ...
  UnityPackageManager.exe. Missing files could be the result of an antivirus action
  or a corrupt Unity installation`, which reads like corruption rather than
  incompleteness. Wait for the `UnitySetup64-<version>` **process to exit**, not for
  a file to appear. A 2022.3 install lands at roughly **6.2 GB** after a 3.44 GB
  download.

- **B4 - Unity Hub 2.4.4 has no usable CLI.** The `--headless` surface used here
  (`install --version --changeset`, `editors -r/-i`) is a Hub 3.x feature. Upgrading
  2.4.4 -> 3.19.5 via `winget upgrade --id Unity.UnityHub --source winget` was a
  prerequisite for everything else and did **not** disturb the (stub) editor tree.

- **B5 - `winget` prompts on the `msstore` source and kills non-interactive runs.**
  Any `winget` call over SSH needs `--source winget --accept-source-agreements
  --disable-interactivity`, or it blocks on an agreements prompt and dies with
  `0x8a150042 : Error reading input in prompt`.

- **B6 - PowerShell-over-SSH pollutes stdout with CLIXML.** `Write-Host` output from
  a remote `powershell -EncodedCommand` session comes back wrapped in
  `#< CLIXML ... <Objs>` noise that swamps real output. Redirect to a file on the
  remote host and `type` it back in a second call. Also: `-EncodedCommand`
  (UTF-16LE base64) is the only reliable way to get quoting-heavy commands through
  the SSH + PowerShell layers intact.

- **B8 - Windows OpenSSH kills the whole process tree at session exit.** This is the
  single biggest constraint on validating Unity 6's live-control surface, and it took
  a control experiment to attribute correctly. Both a GUI Editor and a
  `-batchmode -nographics` Editor launched over SSH died instantly with **zero-byte
  logs**, which looks exactly like Unity failing to start. It is not: a plain
  `powershell -Command "Start-Sleep 240"` spawned the same way is already dead when
  checked from a second SSH connection. Short **synchronous** commands are unaffected
  (everything run with `Start-Process -Wait` inside the session worked), so this only
  bites long-lived processes - which is precisely what `unity command`/`list`/
  `status`/`mcp` require. ⤳skill: on a build node reached over OpenSSH, the agent
  should not propose the Pipeline live-control path without a persistence mechanism
  (scheduled task, service, or a held-open interactive session). Same family as the
  unreal rig's "long ops need a held-open session" note.

- **B9 - `query session` / `qwinsta` are NOT usable probes from an SSH session, and
  reading their silence as "no desktop" is a trap I fell into.** Both returned empty
  output from session 0 - including at a moment when an interactive session
  demonstrably existed (`explorer.exe` and Unity Hub were running with
  `SessionId=1`). Empty output meant "this probe does not work here", not "no
  session". Acting on it produced a wrong diagnosis: the GUI Editor was blamed on a
  missing window station when the actual and independently-proven cause was B8
  (process-tree kill), which would have killed it regardless.
  **The reliable probe is process session IDs:** `(Get-Process explorer).SessionId`.
  A desktop session exists iff `explorer.exe` runs in a session other than 0.
  General lesson worth keeping: a diagnostic that returns nothing has two readings -
  "the condition is absent" and "the probe is broken" - and on Windows-over-SSH the
  second is common. Prefer a probe with a positive signal.

- **B10 - The session-0/session-1 split is the whole story, and only the Editor
  cares.** SSH commands land in **session 0**; the interactive desktop (Parsec,
  `explorer.exe`, Unity Hub, the Editor) is **session 1**. Once a human started the
  Editor in session 1, every `unity status`/`list`/`command` call issued from
  session 0 worked, because the Pipeline server is a **loopback TCP port (7800)**
  and TCP does not care about window stations. Practical rule for a build node:
  the *Editor* needs something that outlives the SSH session to start it; the *CLI
  calls against it* do not. ⤳skill.

- **B11 - `unity projects add` beats the Hub's folder picker.** The Hub's "Add
  project from disk" rejected the project directory with "No projects found. Select
  a folder that contains Unity projects" - it wants the **parent** directory and
  scans children. `unity projects add <path...>` registers a project directly, and
  `unity projects list` / `remove` round it out (`remove` de-registers only, it does
  not delete files).

- **B7 - Disk is the binding constraint on this rig.** The primary Windows test
  machine has a single volume with ~42 GB free before the install and no second
  drive; a 2022.3 Editor plus a probe project consumes roughly 8 GB of it. Routing
  through WSL on the same box is not a way around this (same physical volume). A
  second machine on hand had far more room (~880 GB) but only a 4-core CPU and
  8 GB RAM, so it was the wrong box for Editor work despite the free space.
