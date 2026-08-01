# Design notes

## Why a domain-specific Jenkins agent

Jenkins is the default CI/CD workhorse for game studios wiring up Unreal/Unity
builds against Perforce or Git, and it mirrors the shipped [`perforce`](../perforce)
agent's shape and posture: a read-first Claude Code plugin to **observe, operate, and
analyze a Jenkins CI/CD server**, tuned for game development, that pairs with the
Perforce agent via the `change-commit` → Jenkins build loop.

A general-purpose agent tends to either avoid CI orchestration entirely or reach for
generic REST-client patterns that miss Jenkins' sharp edges: a CSRF crumb has to be
fetched in the **same HTTP session** as the write it protects, a broken
Perforce→Jenkins trigger is **silent** to the developer who submitted the changelist
(the trigger always exits 0), and the Script Console (`/script`, `scriptText`, CLI
`groovy`/`groovysh`) is arbitrary remote code execution on the CI server that a
generic "give the agent more tools" instinct would happily wrap.

## Locked decisions

- **REST/CLI-driven; no MCP dependency in v1.** The official
  `jenkinsci/mcp-server-plugin` is a good *tool taxonomy* to imitate and an optional
  accelerant *if* the target controller has it installed - never a requirement. At
  least one community MCP server shows the breadth of read tools but ships a
  `run_groovy_script` tool - i.e. the Script Console RCE footgun by another name;
  **design it out**, don't copy it.
- **Read-first.** Observe/analyze runs freely; every write is gated + confirmed.
- **Auth = API token via HTTP Basic (`user:token`).** The agent never types, echoes,
  logs, or pastes a token; the user creates it at their own `/me/configure`.
- **Hard-block the Script Console** (`/script`, `scriptText`, CLI `groovy`/`groovysh`)
  with a `guard-jenkins.sh` PreToolUse hook - same backstop pattern as `guard-p4.sh`.

## What informed the client/CI-bridge playbooks

These playbooks weren't written from the docs alone - they're informed by a real
Jenkins integration ButterStack runs in production: a client that fetches a CSRF
crumb and triggers a build in one HTTP session (Jenkins requires the cookies to
match), tails console output and artifacts, and a CI-tag grammar that parses commit
messages for `#ci`/`#build`/`#jenkins`/`[ci]`/`ci:`/`--ci` (with optional
`#jenkins:JobName` routing) to decide whether and where a changelist should trigger a
build. That's where the crumb-in-session rule, the expected `201` + `Location` queue
URL response shape, and the CI-tag routing model in `jenkins-p4-bridge` come from.

A real production finding shaped one of the agent's standing checks directly: a
webhook token passed as a plain Jenkins build parameter is readable by any read
user, including anonymous - see [`LEARNINGS.md`](./LEARNINGS.md) for the full
story. That's why `jenkins-observe`'s secret-exposure check exists at all: it
proactively scans build parameters for values that look like credentials and
recommends a masked Jenkins credential instead of a plain string parameter.

## Jenkins operational surface

- **REST**: `.../api/json` everywhere; scope with **`tree=`** (not bare `depth=`);
  `buildWithParameters` to trigger; **`logText/progressiveText?start=<offset>`** (+
  `X-More-Data`) to *tail* long build logs instead of re-pulling `/consoleText`;
  `testReport/api/json`; `/crumbIssuer/api/json`; symbolic builds
  (`lastBuild`/`lastSuccessfulBuild`/`lastFailedBuild`); queue `/queue/api/json`.
- **CLI** (`jenkins-cli.jar`, SSH-preferred): `build -s` (trigger + follow),
  `who-am-i`, `console`. Prefer REST for stateless polling.
- **Status**: `result` ∈ SUCCESS/FAILURE/UNSTABLE/ABORTED (+ `building:true`);
  job `healthReport` = rolling weather.

## Never-do list → `guard-jenkins.sh`

`/script` / `scriptText` / CLI `groovy` (**RCE - hard block**); echoing tokens; a
state-changing POST without a crumb; job/build deletes, `config.xml` PUT,
enable/disable, `quiet-down`, aborting/cancelling *others'* builds/queue items (→
confirm); triggering a prod deploy/publish/release job without naming it.

## Live validation

Validated read and write paths against real Jenkins controllers, including a
purpose-built CSRF-enabled Jenkins + p4d stack. See [`LEARNINGS.md`](./LEARNINGS.md)
for the dated findings - the headline corrections were that `GET config.xml` needs
`Job/ExtendedRead` (not just `Job/Read`) even for anonymous read, that API-token auth
is exempt from the CSRF crumb while username+password is not, and that Jenkins'
`replay` endpoint needs a Stapler form field rather than a bare script parameter.
