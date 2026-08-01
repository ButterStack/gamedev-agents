---
description: Drive a running Unity 6 Editor via the Pipeline control surface - state ladder first, dry_run before confirm, results read from the response envelope (never exit code alone)
argument-hint: "[tool-name] [args...]"
---

Guide the user through a safe live-Editor operation per `$ARGUMENTS` (a
Pipeline tool name and its arguments - if none given, run the state ladder
and report what is available). Use the `unity-pipeline` skill for the exact
command forms, the tool map, and the gate rules.

Steps:

1. **Version gate first** (`unity-observe` §1-§2) - read `m_EditorVersion`.
   Below 6000.x the Pipeline surface does not exist: say so and stop; offer
   the batchmode trio (`unity-build`) instead. Never suggest a
   `pipeline`/`command`/`mcp` invocation that will fail.
2. **Climb the state ladder** (`unity-pipeline` §2) - `unity pipeline list`
   (package installed?), `unity status` (Editor connected?),
   `unity list --format json` (which tools?). Each rung names its own fix:
   package missing = a gated `unity pipeline install` (edits
   `Packages/manifest.json`); server unreachable = the user must have the
   project open in a running Editor - the server lives inside it, and there
   is no batchmode Pipeline.
3. **Classify the tool call** - reads (`get_*`, `list_*`, `find_*`,
   `*_status`, `screenshot`) run freely. Mutations are gated: if the tool
   takes `dry_run`, run the preview first and show the result; if it takes
   `confirm`, show the exact command plus the consequence from the tool's
   own description (Undo-able or "Not undoable via Ctrl+Z", domain reload,
   reimport) and **wait for explicit approval - never pass `confirm=true`
   on the user's behalf**. Treat `eval`/`eval_file` (arbitrary C# in the
   Editor) as gated even though Unity does not gate them.
4. **Run and parse the payload, not the exit code** (`unity-pipeline` §5) -
   `unity command` exits 0 whenever the transport worked, even if the tool
   returned `"success": false`. Read the inner envelope: `success`,
   `applied`, `requiresDomainReload`, `requiresReimport`, `message`. A 400
   + exit 6 is Unity's own confirm gate refusing - relay its message, don't
   retry with `confirm=true`.
5. **Poll async operations to completion** (`unity-pipeline` §6) - builds,
   bakes, target switches, package ops, recompiles and tests return
   immediately; poll the matching `*_status` tool and report its terminal
   state, not "command sent".
6. **Report observed results** - what changed (`applied`), what it cost
   (reload/reimport), and the values read back - remembering this Editor is
   the user's live session, not a sandbox.

If asked to set up MCP: `unity mcp configure --list` shows the 16 supported
clients; `claude-code` is "delegation/manual" (no file written). The MCP
server is stdio over a loopback-only control port - never expose it beyond
the machine (`unity-pipeline` §9).

**Example:** *"Clear the navmesh."* -> ladder shows a reachable server ->
`clear_navmesh` takes `confirm` + `dry_run` and is "not undoable via Unity's
Undo" -> run the `dry_run`, show what would be cleared, ask - and only on an
explicit yes run `unity command clear_navmesh --confirm true`, then report
the envelope's `success` and `message`.
