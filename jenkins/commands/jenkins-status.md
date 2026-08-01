---
description: Summarize Jenkins job/build status, queue depth, and health trend
argument-hint: "[job-name]"
---

Summarize the current Jenkins state for the user. Read-only - run no write/trigger
command in this workflow. Use the `jenkins-observe` skill for exact request forms.
Scope to `$ARGUMENTS` if a job name is given, else give a controller-wide overview.

Gather and report, in order:

1. **Identity** - `GET {JENKINS_URL}/whoAmI/api/json`. Note if running anonymously
   or under a service account; don't assume write access either way.
2. **Job listing (no argument) or job detail (argument given)** - `GET
   /api/json?tree=jobs[name,url,buildable,color]` for the overview, or `GET
   /job/$ARGUMENTS/api/json?tree=...` (see `jenkins-observe` §2) for one job's
   `color`, `healthReport`, `lastBuild`/`lastSuccessfulBuild`/`lastFailedBuild`.
   **Always scope with `tree=`** - never a bare `depth=` on the root.
3. **Queue** - `GET /queue/api/json?tree=items[id,task[name],why,buildable,stuck]`.
   Empty is good; report anything `stuck` or waiting a long time.
4. **Health trend (job given)** - recent builds' `result` sequence
   (`jenkins-observe` §7) to spot a flaky/regressing job, not just its current
   state.
5. **If a build is currently running**, offer to tail its console via
   `logText/progressiveText` (see `jenkins-observe` §5) rather than dumping the
   full log unprompted.

Present a concise summary - what's green/red, what's queued, anything trending
worse - not raw JSON dumps. For a deeper CI-trigger diagnosis (a build that should
have fired but didn't), point to `/jenkins-logs` or the `jenkins-p4-bridge` skill.

**Example:** *"What's the state of Jenkins?"* → 5 jobs, 4 green (`blue`) one red;
queue empty; `MyGame-Cook` failed its last run - offer to pull its
console. *"What's the state of MyGame-Build?"* → `blue`, health 100, last build
#127 SUCCESS, not currently building, nothing queued behind it.
