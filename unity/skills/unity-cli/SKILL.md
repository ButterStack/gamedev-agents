---
name: unity-cli
description: >
  The standalone Unity CLI (`unity`, 1.0.0-beta.x) - what it actually is
  (Hub replacement + batchmode front-end + live-Editor control plane), verified
  install lines (beta channel pinning, the undocumented Windows install.ps1),
  the real command surface vs the incomplete published docs, global options and
  JSON output, exit codes, Editor management (archived versions need a
  changeset), licensing (auth status vs license status), and the Unity 6-only
  Pipeline/MCP half. Use when installing or interrogating the CLI itself, or
  when deciding which CLI commands exist for a given Editor version. To run a
  build/test use `unity-build`; for the read-only project doctor use
  `unity-observe`.
---

# The Unity CLI - surface, install, and version routing

Everything here was verified on a real rig (Windows 11, Unity CLI
`1.0.0-beta.2`, Unity 2022.3.62f3, 2026-07) unless marked otherwise. The
published docs are materially incomplete (§3) - **derive the surface from
`unity <cmd> --help` on the box**, and prefer what the binary says over what
any doc (including this one) says. The CLI is beta and moving.

---

## 1. What the Unity CLI actually is

A standalone binary (`unity`) that is simultaneously:

1. a **Hub replacement** - install/manage Editors, modules, licenses, projects;
2. a **batchmode front-end** - `unity build` / `test` / `run` spawn the Editor
   in batch mode and forward conventional CI flags (`unity-build` skill);
3. a **live-Editor control plane** - `unity command`, `unity status`,
   `unity list`, `unity mcp` talk to a running Editor over a local HTTP API.
   This half requires the `com.unity.pipeline` package, which requires
   **Editor 6.0 or later** (§5, §8).

It is **experimental / beta-only**. There is no stable channel:
`https://public-cdn.cloud.unity3d.com/hub/prod/cli/latest.json` returns 404;
only `latest-beta.json` (and `latest-alpha.json`) exist. Every install line
pins `UNITY_CLI_CHANNEL=beta`.

## 2. Install (verified)

macOS / Linux:

```sh
curl -fsSL https://public-cdn.cloud.unity3d.com/hub/prod/cli/install.sh | UNITY_CLI_CHANNEL=beta bash
```

Installs to `$UNITY_CLI_HOME` (default `~/.unity`), binary in `~/.unity/bin`.

Windows - the docs give the same `| bash` line, which is **wrong for
PowerShell**. There is an **undocumented `install.ps1`** on the same CDN path
that is the correct Windows installer (verified working). Because it is
undocumented and Unity does not version it, download and inspect it before
running rather than piping straight into `iex`:

```powershell
Invoke-WebRequest -Uri https://public-cdn.cloud.unity3d.com/hub/prod/cli/install.ps1 -OutFile install.ps1
Get-FileHash install.ps1 -Algorithm SHA256
# last verified 2026-08-21: 3b5b42c066f04a43aaa587cfa50c5873e0148b80138a8befc610f7a7477b58e6
# Unity can change this file without notice - a different hash on a later pull
# is not itself a red flag, but means re-reading install.ps1 before running it.
$env:UNITY_CLI_CHANNEL="beta"; .\install.ps1
```

Installs to `%LOCALAPPDATA%\Unity\bin\unity.exe`, which then verifies its own
SHA-256 against Unity's manifest at first run. Requires a terminal restart
(or the absolute path) before `unity` is on `PATH`.

Self-update: `unity upgrade`. Removal: `unity self-uninstall`.

## 3. The published docs are incomplete - trust `--help`

`docs.unity.com/en-us/unity-cli/unity-cli-reference` lists only the Hub-ish
commands (`install`, `install-modules`, `uninstall`, `editors`, `install-path`,
`open`, `projects`, `auth`, `language`, `upgrade`, `help`). The actual
`1.0.0-beta.2` binary has all of those **plus** the commands that matter most
for an agent, none of which appear on that reference page:

| Command | What it does |
|---|---|
| `build [options] [project]` | Build a project. Spawns the Editor in batch mode, forwards CI flags. |
| `test [options] [project]` | Run EditMode/PlayMode tests, write an NUnit XML report. |
| `run [options] [project]` | Run a project in batch mode, forward arbitrary args to the Editor. |
| `doctor [options]` | Diagnostics about the CLI environment. |
| `diagnose` | One-shot, paste-safe **redacted** support output. |
| `license [options]` | `list` / `status` / `activate` / `return` / `server`. |
| `mcp [options]` | Start an MCP stdio server for the Editor; `mcp configure <client>`. |
| `command` (alias `cmd`) | Execute commands on connected Editor instances. |
| `status` | Live state of every connected Editor (port, project, version, PID, state). |
| `list` | List tools registered by the Pipeline package on the connected Editor. |
| `pipeline` (alias `pipe`) | `install` / `upgrade` / `list` / `list-versions` the Pipeline package. |
| `shell` | Interactive REPL running many commands in one warm process. |
| `templates`, `projects`, `releases`, `cache`, `hub`, `env`, `logs`, `config`, `editor`, `modules`, `completion`, `analytics`, `bug`, `changelog`, `self-uninstall` | assorted |

## 4. Global options, output, exit codes

Apply to every subcommand:

```
--format <format>     human, json, tsv, ndjson      (env: UNITY_FORMAT)
--no-banner                                          (env: UNITY_NO_BANNER)
--non-interactive     disable prompts; use in CI     (env: UNITY_NON_INTERACTIVE)
--quiet                                              (env: UNITY_QUIET)
--verbose             full errors + stack traces     (env: UNITY_VERBOSE)
--proxy <url>         http/https/socks/pac           (env: UNITY_PROXY)
--proxy-disable, --log-proxy, --no-log-proxy
-V, --version
```

- Format selection is **automatic**: `human` on an interactive TTY, `tsv` when
  piped/redirected, `json` only when asked. An agent should always pass
  `--format json --no-banner --non-interactive` rather than parse the human
  table (or the surprise tsv it becomes in a pipe).
- **Exit codes**: the docs claim only `0` success, `1` general error (details on
  stderr), `130` user cancelled (SIGINT). **That list is incomplete.** Verified on
  the rig, `1.0.0-beta.2` also returns **`6`** as a general operation-failed code,
  in at least three distinct situations:
  - `unity build` when the Editor itself exits non-zero (the CLI reports
    `Error: Build failed (exit 1). See log: <path>` and then exits `6`, so the
    CLI code is *not* the Editor's code),
  - `unity status` when no Editor is connected (prints an empty table),
  - `unity list` / `unity pipeline install` when there is no reachable Pipeline
    server or the Editor is too old.

  So: **treat any non-zero as failure and read stderr; never branch on `1`
  specifically, and never map the CLI's exit code back to the Editor's.** The
  Editor's real exit code appears only in the CLI's stderr text and the log.
- Errors go to **stderr** (`{"error": "..."}` in JSON mode), data to
  **stdout**. Capture both: `unity install 6000.3.7f1 > install.log 2>&1`.
- `unity logs` reads/tails the Hub log directly. Hub log directories:
  Windows `%UserProfile%\AppData\Roaming\UnityHub\logs`, macOS
  `~/Library/Application Support/UnityHub/logs`, Linux `~/.config/UnityHub/logs`.

## 5. The version split - what exists for which Editor

**The central branching fact.** Resolve the project's Editor version
(`unity-observe` §1) before proposing any command from the second group.

- **Any Editor the CLI can resolve, including 2022.3**: `install`, `editors`,
  `install-modules`, `uninstall`, `install-path`, `releases`, `license`,
  `auth`, `projects`, `templates`, `cache`, `hub`, `env`, `logs`, `doctor`,
  `diagnose`, `config`, and the batchmode trio **`build` / `test` / `run`**.
  `unity install 2022` is a valid version alias (aliases include `latest`,
  `lts`, `default`, `6`, `6.5`, `2022`, ...).
- **Editor 6.0+ only**: `pipeline`, `command`/`cmd`, `list`, `status`, `mcp` -
  they depend on **`com.unity.pipeline`**, whose docs state the requirement
  verbatim: "Install the Unity Editor version 6.0 or later". On a 2022.x
  project these do not apply - no live-Editor HTTP control, no MCP server, no
  `unity command`. The batchmode trio (or raw
  `unity run . -- -batchmode -quit -executeMethod ...`) is the whole surface.

## 6. Editor management (verified)

```sh
unity editors -i --format json      # installed
unity editors -r                    # available releases
unity editors add <path...>         # register an out-of-Hub editor
unity editors default [version]
unity editors path <version>        # print install dir
unity editors info <version>
unity editors upgrade [editor]      # newest patch in its release line - GATED, large
unity editors module                # per-editor module management
unity install-path -g | -s <path>
```

- `unity editors upgrade` moves an Editor to a new patch - that is a
  project-affecting change (one-way reserialization on open+save) and must be
  confirmed, not run as housekeeping.
- **Archived versions need an explicit changeset.** `editors -r` only shows
  currently **promoted** releases - on a 2026 Hub that is Unity 6.x only, so
  any 2022.3 install needs `-c`:

```sh
unity install 2022.3.62f3 -c 96770f904ca7
```

  Changesets are discoverable from Unity's release API
  (`https://services.api.unity.com/unity/editor/release/v1/releases?version=2022.3&stream=LTS`,
  fields `version` + `shortRevision`).
- Any `unity install` / `install-modules` is a **gated** action: multi-GB
  download + disk. Name the cost and confirm first.

## 7. Licensing - auth status is NOT license status (verified)

Batchmode does **not** require `unity auth login` if a machine license file
exists. Verified state on a real rig with **no** signed-in user:

```
$ unity auth status
You are not signed in. Run unity auth login to sign in.

$ unity license list --format tsv
Product         Type    Organization    Expires
Unity Personal  ULF

$ unity license status
License: active
  - Unity Personal (ULF)
Signed in: no
```

The license file is `C:\ProgramData\Unity\Unity_lic.ulf` on Windows. So:
**`unity license status` is the right doctor probe, and "not signed in" is NOT
"unlicensed."** An agent that tells the user to log in because `auth status`
is negative is wrong. `auth login` is only needed for cloud/org features - and
notably **not** for the Pipeline package (§8), despite what its docs imply.

### Signing into the Hub does NOT sign into the CLI (verified)

These are **separate credential stores**, and conflating them will make the
agent give confidently wrong advice. Verified on the rig: a user signed into the
**Unity Hub desktop app** with a real account, and at that same moment:

```
$ unity auth status
You are not signed in. Run unity auth login to sign in.     # <- CLI: still signed out

$ unity license status
License: active
  - Unity Personal (ULF)          # machine licence, was already there
  - Unity Personal (Assigned)     # NEW - came from the Hub sign-in
  - Asset Store (Assigned)        # NEW
Signed in: no
```

Two things to take from this:

- **The Hub login propagates *entitlements* to the licensing client but not a
  session to the CLI.** If a user says "but I'm signed in", they may well mean
  the Hub. To sign the *CLI* in you still need `unity auth login` (browser) or
  the service-account flags above.
- **Licence `type` is meaningful.** `ULF` is the machine-bound licence file;
  `Assigned` is an entitlement attached to a signed-in Unity account. Report
  the type, not just the product name - a box with only `Assigned` licences
  loses them when the account signs out, whereas a `ULF` survives. `unity
  license list --format json` gives `product`, `type`, `organization`,
  `expires` per entry.

`unity license` subcommands: `list`, `status`, `activate`, `return`, `server`
(floating license server). `activate`/`return` consume/release a seat -
**gate them**: name the seat consequence and confirm before running.

### Signing in without a browser (service accounts)

When sign-in genuinely is required (the Pipeline package, cloud/org features),
do **not** tell a CI or headless user to "open the browser" - `auth login` has a
non-interactive path that the published docs do not mention:

```
unity auth login --client-id <key-id> --secret-from-stdin   # secret on stdin
unity auth login --client-id <key-id> --client-secret <secret>
unity auth login --client-id <key-id> --secret-from-stdin --no-store
```

- `--secret-from-stdin` is the form to recommend. Unity's own help says it
  "keeps it out of argv / ps" - the same leak class as the `--android-keystore-*`
  flags (`unity-build` §5). Never put the secret in `--client-secret` on a shared
  box or in CI, where it lands in process listings, shell history and logs.
- `--no-store` mints credentials in-process without persisting them to the
  keyring - the right choice on a shared or ephemeral build agent.
- Plain `unity auth login` with no flags opens a browser, which is exactly the
  thing that cannot be automated. Reach for it only on a developer workstation.

So the decision tree is: **machine licence (ULF) covers batchmode builds and
needs no login at all; a service account covers the login-requiring features
headlessly; the browser flow is a workstation-only fallback.**

## 8. Pipeline + MCP (Unity 6.0+ only) - verified live

The live-Editor half is now **verified against a running Unity 6.3 Editor**
(Editor `6000.3.20f1`, `com.unity.pipeline` `0.3.1-exp.1`, 2026-07-22). This
section covers install and the version boundary; **everything past install -
the state ladder, the 140-tool surface, Unity's own confirm/dry_run gates,
the response envelope and its exit-0 trap, async polling, warm Pipeline
builds, and MCP - lives in the `unity-pipeline` skill.** Load that skill
before driving a live Editor.

Setup - the install step gated (it mutates the project's
`Packages/manifest.json`, a tracked project change):

```
unity pipeline install    # GATED - edits Packages/manifest.json; wait for the Editor to recompile
unity pipeline list       # package installed + server reachable?
unity list                # tools the Editor now exposes
unity command <cmd>       # execute one
```

**`pipeline install` does NOT require sign-in** (verified: it succeeded with
`unity auth status` reporting "not signed in", on the machine ULF alone).
The docs' `auth login` -> `pipeline install` ordering is not enforced -
consistent with §7: do not send users to the browser for this.

`unity pipeline install [--project-path <p>] [--force] [--package-version <v>]`,
`unity pipeline upgrade`, `unity pipeline list-versions`.

**Verified refusal behaviour on a 2022.3 project:**

```
$ unity pipeline install --project-path C:\work\UnityCliProbe
Error: Pipeline package requires Unity 6.0 or higher.
Project version: 2022.3.62f3
Project path: C:\work\UnityCliProbe
$ echo $?   # -> 6
```

It **refuses cleanly and leaves `Packages/manifest.json` byte-identical** - no
partial write, nothing to roll back. So an accidental `pipeline install` against
a 2022.x project is safe, but it is still a wasted round trip: read
`ProjectVersion.txt` first and do not offer the Pipeline path at all below 6.0.

`pipeline list` is the probe that stays useful everywhere - it works even on
2022.3 (exit 0, reports `Pipeline=false`) and, on Unity 6 with no Editor
running, shows `Pipeline=true, Server Reachable=false`. `unity status` /
`unity list` exit 6 without a reachable server (`unity-pipeline` §2 has the
verified outputs).

The control plane talks to the Editor over a **local** HTTP API
(`127.0.0.1:7800`, verified) and the MCP server (`unity mcp`) is stdio -
keep it that way. Same posture as the unreal agent's Remote Control rule:
never expose an editor-control endpoint beyond the machine
(`unity-pipeline` §9).

## 9. CLI self-diagnostics

- `unity doctor` - diagnostics about the CLI environment (read-only, run
  freely).
- `unity diagnose` - one-shot support output, **redacted by design** - safe to
  paste into an issue.
- `unity shell` - interactive REPL that runs many commands in one warm
  process; useful interactively, not for CI scripts.

## Caveats

- **Beta means moving.** Command surface may shift between betas; `--help` on
  the installed binary always wins over this file.
- The `templates`, `projects`, `cache`, `hub`, `env`, `config`, `editor`,
  `modules`, `completion`, `analytics`, `bug`, `changelog` subcommands exist
  (verified in `unity help`) but their full option surfaces were **not**
  exercised on the rig - `--help` them before relying on specifics.
- Classic Editor batchmode (`-batchmode -quit -executeMethod` against the
  Editor executable directly) still exists underneath and `unity run ... --`
  forwards to it - the CLI is the front door, not a replacement for knowing
  the trap doors (`unity-build` §4).
