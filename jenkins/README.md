# Jenkins Agent

**A Claude Code plugin to observe, operate, and safely diagnose your Jenkins CI/CD
server - built for game development.**

> Third in the ButterStack series of public gamedev agents, after
> [`perforce`](../perforce) and [`unreal`](../unreal).

Jenkins remains the default CI/CD workhorse for game studios wiring up Unreal/Unity
builds against Perforce or Git. This is a domain-specific
[Claude Code](https://claude.com/claude-code) agent that understands Jenkins' model
(job → build → queue → console) and, specifically, the **Perforce `change-commit` →
Jenkins build loop** that most gamedev CI pipelines are actually built on.

It is **read-first**: its job is to *observe* your controller - job/build status,
queue depth, console logs (tailed, not re-pulled), test reports, and health trend -
with gated, confirmed write operations (triggering a build, aborting one, replaying
a pipeline) as the supporting act. The Jenkins **Script Console** (`/script`,
`/scriptText`, CLI `groovy`/`groovysh`) is arbitrary remote code execution on your
CI server and is categorically out of scope - refused by the agent itself and
hard-blocked by a bundled guard hook as a backstop.

## Who this is for

Game studios and solo devs running Jenkins (self-hosted or containerized) who want
an AI assistant that reasons about builds and triggers correctly - including the
thing generic agents miss: **a CSRF crumb must be fetched in the same HTTP session
as the write it protects**, and a broken Perforce→Jenkins trigger is **silent** to
the developer who submitted the changelist (the trigger always exits 0), so
diagnosing "why didn't my build fire" means working from the Jenkins/webhook side,
not the `p4 submit` output.

## What's in the box

```
agents/jenkins.md                    the agent (identity/auth, crumb rules, error
                                      classification, request gating, never-/script)
skills/jenkins-observe/SKILL.md      read-only: job/build status (tree=), queue,
                                      progressiveText log tail, test reports, health trend
skills/jenkins-operate/SKILL.md      gated writes: buildWithParameters, abort, replay
                                      - crumb-in-session + confirmation, every time
skills/jenkins-p4-bridge/SKILL.md    diagnose the Perforce change-commit → Jenkins
                                      build loop: CI-tag grammar, job routing, the
                                      exit-0-always rule
commands/jenkins-status.md           /jenkins-status - job/build/queue snapshot
commands/jenkins-build.md            /jenkins-build  - guided, confirmed build trigger
commands/jenkins-logs.md             /jenkins-logs   - capped, structured console tail
hooks/ + scripts/                    guard-jenkins (hard-blocks the Script Console)
```

## Install

This repo is a self-contained Claude Code plugin marketplace. In Claude Code:

```
/plugin marketplace add ButterStack/gamedev-agents
/plugin install jenkins@gamedev-agents
```

The agent, skills, slash commands, and guard hook are auto-discovered on install.

## Setup

You need a reachable Jenkins controller URL and an **API token** - not your Jenkins
password.

**1. Generate an API token yourself.** Log into Jenkins, click your username →
**Configure** (`{JENKINS_URL}/me/configure`) → **API Token** → **Add new Token**.
Copy it into wherever your credentials already live (an env var, a secrets
manager) - the agent never asks you to paste a token into chat, and never types,
echoes, or logs one.

**2. Run as a least-privileged Jenkins user.** Create (or reuse) a service account
scoped to only the jobs/permissions this agent actually needs - read, plus
`Job/Build` on the jobs it should be allowed to trigger. **The real safety boundary
is the Jenkins account**, the same way the `perforce` plugin's real boundary is the
p4 account: Jenkins' own role-based authorization, not Claude Code permissions, is
what actually stops a destructive or dangerous action. Never run this agent as a
Jenkins admin/`ADMINISTER`-holding account.

**3. The guard hook is a backstop, not the primary control.** This plugin ships a
`guard-jenkins` hook that hard-blocks any command targeting the Script Console
(`/script`, `/scriptText`, CLI `groovy`/`groovysh`) regardless of how your Claude
Code permissions are configured - but a least-privileged Jenkins account that
simply *can't* reach the Script Console (no `ADMINISTER`/`RUN_SCRIPTS` permission)
is the guardrail that actually matters.

## Quickstart

Ask the `jenkins` agent, or use the slash commands:

- **"What's the state of Jenkins?"** → `/jenkins-status` (job/build status, queue
  depth, health trend)
- **"Trigger a build for changelist 4821."** → `/jenkins-build` (shows the job +
  parameters, confirms, then triggers via `buildWithParameters`)
- **"Why did the last build fail?"** → `/jenkins-logs` (capped console tail +
  test-report summary, not a raw log dump)
- **"My commit was tagged `#ci` but nothing built."** → the agent walks the
  `jenkins-p4-bridge` skill: is the trigger firing, is Jenkins receiving it, did the
  build pin to the right changelist

The agent shows exactly what it's about to trigger/abort and waits for confirmation
before any write - the same discipline the `perforce` agent applies to `p4 submit`.

## Safety posture

Opinionated about Jenkins' sharp edges: never calls the Script Console or evaluates
Groovy on the controller, under any framing; always fetches the CSRF crumb and
performs a write in the same HTTP session; always shows the job, build, and
parameters before triggering, aborting, or replaying anything; treats job/build
deletion, `config.xml` changes, enable/disable, `quiet-down`, aborting someone
else's build, and any job that looks like a production deploy/publish/release as
destructive operations requiring the target named explicitly. See
[`agents/jenkins.md`](./agents/jenkins.md) for the full list.

## Contributing

Issues, playbook corrections, and especially **real-controller testing reports**
are welcome - see [CONTRIBUTING.md](../CONTRIBUTING.md). Jenkins behavior varies by
version, plugin set (P4 plugin, Pipeline, Notification), and CSRF/security
configuration, so reports from your controller make this better for everyone.

## License

**Not yet licensed for reuse.** This repo has no LICENSE file yet, so all rights are
reserved by default. A license will be added before this repo is made public - see the
root [README](../README.md#license).

---

Part of the [ButterStack gamedev agents](../README.md) series.

*The open agents trail what ButterStack learns running gamedev tooling in production - get the managed version at [butterstack.com](https://butterstack.com?utm_source=github&utm_medium=repo&utm_campaign=gamedev-agents).*
