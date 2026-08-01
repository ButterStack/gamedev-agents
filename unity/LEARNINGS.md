# Unity Agent - Validation Learnings (running log)

Companion to [`NOTES.md`](./NOTES.md) (design rationale and a summary of what's been
live-validated). Same split as the unreal plugin:

- **(A) Agent/skill learnings** - things the plugin would have got *wrong* if it had
  been written from the documentation. These graduate into the skills; that's the
  whole feedback loop.
- **(B) Operational/rig learnings** - the reality of standing up a Unity rig. Mostly
  not skill material, but a few graduate (flagged ⤳skill).

No secrets - reference credential *locations*, never paste them.

## A. Agent / skill learnings (baked into the skills)

- **The documented Windows install line does not work.** Unity's own docs give the
  *same* `curl ... | UNITY_CLI_CHANNEL=beta bash` line for macOS, Linux, **and
  Windows (PowerShell)** - but there's no `bash` in a stock PowerShell. There *is*
  an undocumented `install.ps1` at the same CDN path, which is the real Windows
  installer (SHA-256 verified, installs to `%LOCALAPPDATA%\Unity\bin`). Found by
  probing the CDN, not by reading docs.
- **The published CLI reference omits most of the CLI.** The docs page lists only
  the Hub-ish commands. The actual beta binary additionally has `build`, `test`,
  `run`, `doctor`, `diagnose`, `license`, `mcp`, `command`, `status`, `list`,
  `pipeline`, `shell`, and more. An agent built from the docs page alone would
  conclude the Unity CLI can't build or test anything - which is exactly the
  wrong first-pass conclusion this plugin corrected.
- **Exit codes are not the documented `0`/`1`/`130`.** The binary returns `6` for
  several distinct failure classes (a build whose Editor exited non-zero, no
  connected Editor, no reachable Pipeline server). Worse, **the CLI's exit code is
  not the Editor's** - a build where the Editor exited `1` surfaces as CLI exit
  `6`, with the Editor's real code only inside the stderr string. Any agent
  branching on `== 1` would silently mis-handle every real failure: treat any
  non-zero as failure and read stderr, never map the CLI code to the Editor's.
- **"Not signed in" is not "unlicensed."** A rig with an active Unity Personal
  license and nobody signed in reports `auth status: not signed in` while `license
  status: active` - and batchmode builds work fine. The obvious-looking probe
  (`auth status`) is the wrong one; acting on it sends every build-node user
  through a pointless login. Probe `license status` instead.
- **The exit-0 trap survives the new CLI.** The classic Unity CI footgun -
  batchmode exits 0 on a failed build unless your `-executeMethod` says otherwise -
  is *not* fixed by `unity build`. Directly demonstrated: a build method targeting
  an unwritable path returned exit `0` with no artifact produced. The wrapper
  forwards the Editor's code, and the Editor itself has nothing to complain about.
  This was the single most valuable thing to have actually run rather than
  assumed - the natural assumption is that a purpose-built build command would
  have solved it. Verify the artifact and the log, never the exit code.
- **The Unity 6 boundary is enforced, quotable, and safe.** Exercised directly
  rather than inferred from package docs: `unity pipeline install` against a
  2022.3 project returns a clear "requires Unity 6.0 or higher" error and leaves
  the manifest byte-identical, while `unity pipeline list` still works on 2022.3
  (reporting `Pipeline=false`). The half-degraded behavior is not something you'd
  guess from the docs.
- **Output format changes when you pipe.** `--format` defaults to `human` on a TTY
  but silently switches to `tsv` when redirected or piped - an agent that eyeballs
  a command interactively and then scripts the same command gets different bytes.
  Every parsed invocation should pass `--format json` explicitly, always.
- **The batchmode path is genuinely version-agnostic.** The same build script and
  test assembly, unmodified, produced equivalent results on both a 2022.3 LTS
  Editor and a Unity 6 Editor. That's what justifies the agent's structure:
  `build`/`test`/`run` need no version routing at all - routing is reserved for
  the Pipeline half alone.
- **There's a SECOND exit-0 trap, in `unity command`.** The same shape as the
  batchmode trap above turns up again in the live-Editor Pipeline path: `unity
  command` exits `0` whenever the *transport* succeeded, even when the tool
  itself returned `"success": false`. A **validation** failure (a missing
  required parameter) comes back as `400` with exit `6`; a **semantic** failure
  inside the tool comes back as exit `0`. Two different failure classes, two
  different signals - parse the payload, never the exit code.
- **Unity's Pipeline tools carry their own confirm/dry_run gate, enforced
  server-side, not just advisory.** A destructive tool call without `confirm`
  returns a real `400` naming the exact reason (e.g. "refusing to clear the
  NavMesh - not undoable via Unity's Undo"). Unity independently arrived at the
  same read-first design; this agent's own "never pass `confirm=true` on the
  user's behalf" rule sits on top of an enforced floor, not as the only
  safeguard.
- **Unity 6 has two build paths, and they are not interchangeable.** Batchmode
  (cold Editor, CI-shaped, subject to the exit-0 trap above) versus the Pipeline
  path (a warm, already-running Editor, no domain-reload cost, Unity 6 only, and
  it mutates the Editor a developer may be sitting in front of). Neither
  subsumes the other.
- **Sign-in has three separate, easily-confused layers.** The Hub desktop app,
  the CLI's own `auth login`, and the machine-bound license file (ULF) are all
  independent: signing into the Hub does not create a CLI session; `unity
  pipeline install` works with **nobody** signed in via the machine ULF alone
  (contradicting the docs' implied login-first ordering); and the CLI's `auth
  login` has an undocumented headless/service-account path
  (`--client-id`/`--secret-from-stdin`) that's the actually-correct advice for a
  CI user, versus the docs' browser-only framing. A user insisting "I'm signed
  in" may mean any of the three - the agent has to probe, not believe it.

## B. Operational / rig learnings

- **A Unity Editor's install directory can exist and still mean "not installed."**
  A directory can exist with a stub manifest and effectively zero payload - the
  residue of an install that never finished - and the CLI correctly ignores it.
  Separately, the Hub can create the Editor binary itself well before the install
  actually finishes unpacking, so a readiness check that only waits for the binary
  to appear will grab a broken Editor and produce a misleading
  "corrupt installation"-style error instead of "still installing." ⤳skill:
  wait for the installer *process* to exit, not for a file to appear.
- **Driving the Editor binary directly needs an explicit wait.** It's a
  GUI-subsystem binary, so a naive shell invocation returns immediately with no
  useful exit code - use a process-wait mechanism that actually blocks and then
  reads the real exit code. (The `unity` CLI itself blocks correctly; this only
  bites when driving the Editor binary directly.)
- **An old Hub install has no usable CLI surface.** The headless install/list
  commands this plugin relies on are a Hub 3.x feature; an older Hub needs
  upgrading first, and doing so did not disturb the existing (broken) editor
  entries it already had.
- **SSH sessions on Windows silently kill long-lived processes, and the failure
  looks exactly like Unity failing to start.** Both a GUI Editor and a headless
  batchmode Editor launched over an SSH session died instantly with zero-byte
  logs - indistinguishable from a real startup failure. A control test proved
  it wasn't Unity: a plain long-running shell command spawned the same way was
  already dead by the time a second SSH connection checked on it. The actual
  cause is that Windows' SSH implementation ties a spawned process's lifetime to
  the session that launched it, and an interactive desktop session is a
  genuinely different session from the one SSH commands run in - so a
  diagnostic that only checks "is a desktop session present" can come back
  silent for two very different reasons (no session, or the probe itself doesn't
  work from here), which is its own trap. The practical fix: the *Editor*
  process needs something that outlives the SSH session to start it (a
  scheduled task, a service, or a held-open interactive session) - but once a
  human starts the Editor in a real desktop session, ordinary SSH-launched CLI
  calls against it work fine, because Unity's live-control server is a loopback
  TCP port that doesn't care which session issued the connection. ⤳skill: on a
  build node reached only over SSH, don't propose the live-control path without
  a persistence mechanism for the Editor itself.
- **The Hub's "add project" folder picker wants the parent directory, not the
  project directory** - it silently rejects the project folder itself and scans
  for children. Registering a project directly by path sidesteps the picker
  entirely.
- **Disk, not CPU, was the binding constraint on the primary test rig** - a single
  volume with limited free space before the install, consumed significantly by
  an Editor plus a probe project. A second machine on hand had much more disk but
  a weak CPU and little RAM, making it the wrong box for Editor work despite the
  free space.
