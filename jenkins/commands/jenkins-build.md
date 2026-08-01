---
description: Gated, confirmed Jenkins build trigger - show job + parameters, confirm, then trigger via buildWithParameters
argument-hint: "<job-name> [param=value ...]"
---

Guide the user through safely triggering a Jenkins build for the job named in
`$ARGUMENTS` (with any `param=value` pairs also parsed from `$ARGUMENTS`). Use the
`jenkins-operate` skill for exact request forms and the crumb-in-session rule.

Steps:

1. **Resolve identity and the job's real state first** (`jenkins-observe` §1-2):
   confirm the job exists (exact, case-sensitive name), is `buildable`, and isn't
   already mid-build in a way that makes a second trigger redundant.
2. **Show, don't assume, the parameters.** Pull the job's expected parameter list
   (from `config.xml` or the job page) and compare against what the user gave you in
   `$ARGUMENTS`. Flag any required parameter that's missing rather than sending a
   build with blanks.
3. **Flag production/deploy risk.** If the job name suggests a deploy/release/
   publish/prod target, stop and require the user to name that exact job before
   proceeding - do not accept a generic "yes."
4. **Confirmation gate - show the exact action**: job name, every parameter and its
   value, and what will happen (a real build will start, consuming an executor and
   possibly artifacts/side effects like a Steam upload). Wait for explicit
   confirmation.
5. **Trigger**: crumb-in-session `POST .../buildWithParameters` (`jenkins-operate`
   §0-1). Expect `201` + a `Location` queue-item URL - not yet a build number.
6. **Follow it**: poll the queue item until it resolves to a build number
   (`jenkins-observe` §4), then report the build number and offer to tail its
   console (`jenkins-observe` §5).

Never trigger without the confirmation step in #4, even if the user's original
request already sounds like a command ("kick off the build") - restate exactly what
will run first.

**Example:** *"Trigger MyGame-Build for changelist 4821."* → confirm the job is
buildable and not already running, show `P4_CHANGELIST=4821` (plus any other
required params) and confirm, then trigger - report the resulting queue item and,
once it resolves, the build number to watch.
