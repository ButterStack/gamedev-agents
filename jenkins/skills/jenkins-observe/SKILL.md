---
name: jenkins-observe
description: >
  Read-only Jenkins observability playbooks - job/build status via scoped `tree=`
  queries, queue inspection, console-log tailing via progressiveText, test reports,
  and health/weather trend. Use for inspecting and reasoning about a Jenkins
  controller WITHOUT changing it. For operations that trigger/abort/replay builds use
  the `jenkins-operate` skill instead.
---

# Jenkins Observe

Read-only playbooks for understanding a Jenkins controller. **Nothing here mutates
anything** - every request below is a `GET`. Resolve identity first
(`{JENKINS_URL}/whoAmI/api/json`) - see the `jenkins` agent for auth/crumb rules
(crumb is only needed for writes, not for anything in this skill).

All examples use `curl -u "$JENKINS_USER:$JENKINS_TOKEN"`. **Always pass `-g`
(`--globoff`) with curl when the URL contains `tree=field[subfield]` brackets** -
without it curl parses `[` `]` as its own range-globbing syntax and fails with `bad
range in URL` before the request is even sent (expected: `curl
"...?tree=jobs[name]"` errors on the brackets; `curl -g "...?tree=jobs[name]"` works).

---

## 1. Controller & job listing - always scope with `tree=`

**Never** hit `{JENKINS_URL}/api/json` with a bare `depth=` (or no scoping at all)
on the root - it recursively serializes every job, build, and nested field on the
controller and can return megabytes or hang a busy instance. Always name the fields
you want:

```sh
curl -g -u "$JENKINS_USER:$JENKINS_TOKEN" \
  "$JENKINS_URL/api/json?tree=jobs[name,url,buildable,color]"
```

`color` is Jenkins' compact status encoding: `blue`=last build succeeded,
`red`=failed, `yellow`=unstable, `notbuilt`=never run, `grey`/`disabled`=disabled,
and an `_anime` suffix (e.g. `blue_anime`) means it's currently building.

## 2. A specific job's status

Scope to exactly what you need - don't pull the full job object (build history,
SCM config, etc.) for a status check:

```sh
curl -g -u "$JENKINS_USER:$JENKINS_TOKEN" \
  "$JENKINS_URL/job/$JOB/api/json?tree=name,buildable,color,healthReport[description,score],lastBuild[number,result,timestamp,building],lastSuccessfulBuild[number],lastFailedBuild[number]"
```

- `healthReport[].score` is the rolling "weather" (0-100, lower = more recent
  failures) - a fast way to spot a job that's been flaky over its last several runs
  without walking build history yourself.
- Symbolic build references work anywhere a build number does: `lastBuild`,
  `lastSuccessfulBuild`, `lastFailedBuild`, `lastCompletedBuild` - e.g.
  `$JENKINS_URL/job/$JOB/lastBuild/api/json`.
- **Job names are case-sensitive** and unknown/mistyped names 404 rather than
  returning an empty result - verify the exact name from the listing in §1 before
  assuming a job doesn't exist.

## 3. A specific build's status

```sh
curl -g -u "$JENKINS_USER:$JENKINS_TOKEN" \
  "$JENKINS_URL/job/$JOB/$BUILD_NUMBER/api/json?tree=number,result,building,timestamp,duration,url,actions[parameters[name,value]]"
```

- `result` ∈ `SUCCESS` / `FAILURE` / `UNSTABLE` / `ABORTED` / `null` (still running -
  check `building:true` instead of relying on `result`).
- `actions[parameters[...]]` surfaces the parameters the build was triggered with
  (e.g. `P4_CHANGELIST`) - the fastest way to answer "which changelist did this
  build run against?" without parsing console output.
- **⚠ Parameters can carry secrets in cleartext** (a webhook/API token passed as a
  plain `StringParameterValue`). Don't read past them - run the **§9 secret-exposure
  check**: report any secret-looking value as redacted, never echo it.

## 4. Queue - is a build waiting, and why

```sh
curl -g -u "$JENKINS_USER:$JENKINS_TOKEN" \
  "$JENKINS_URL/queue/api/json?tree=items[id,task[name],why,buildable,stuck]"
```

- Empty `items: []` means nothing queued (a quiet controller returns
  `{"_class":"hudson.model.Queue","items":[]}`).
- `why` is a human-readable reason it's waiting (e.g. "Waiting for next available
  executor", or a quiet-period countdown). `stuck:true` means it's been blocked
  longer than expected - flag it.
- A specific queued item's detail (useful right after triggering a build, before it
  gets a build number): `$JENKINS_URL/queue/item/$QUEUE_ID/api/json`. Poll this,
  not the job's `lastBuild`, until it resolves to `executable` (which then has the
  real build `number`). A just-triggered build sits in the queue through the job's
  **quiet period (~5s default)** before it starts and gets a number - so `nextBuildNumber`
  won't advance and `lastBuild` won't be your build for those first seconds; poll the
  queue item (validated: Jenkins 2.504.2).

## 5. Console log - tail with progressiveText, don't re-pull consoleText

For anything beyond a short finished build's log, use the **progressive** text
endpoint instead of repeatedly fetching the full `consoleText`:

```sh
curl -g -u "$JENKINS_USER:$JENKINS_TOKEN" -D - \
  "$JENKINS_URL/job/$JOB/$BUILD_NUMBER/logText/progressiveText?start=0" \
  -o console_chunk.txt
```

- Response headers carry `X-Text-Size: <bytes>` (the current total) and, **only
  while the build is still running**, `X-More-Data: true`. Use `X-Text-Size` as the
  next request's `start=` value to fetch only the new tail:

  ```sh
  next_start=$(curl -g -sI -u "$JENKINS_USER:$JENKINS_TOKEN" \
    "$JENKINS_URL/job/$JOB/$BUILD_NUMBER/logText/progressiveText?start=$prev_start" \
    | grep -i '^X-Text-Size:' | tr -d '\r' | awk '{print $2}')
  ```

- Once the build finishes, `X-More-Data` stops appearing - that's your signal to
  stop polling. (On a completed build, `X-Text-Size` is present and `X-More-Data`
  absent - the expected shape for a build that's no longer running.)
- Plain `consoleText` (no `logText/progressiveText`) still works and is fine for a
  **short, already-finished** build's full log - but re-fetching it repeatedly to
  simulate "tailing" a running build re-downloads the entire log every poll, which
  gets expensive on long Unreal/Unity build logs. Always prefer progressiveText once
  you're polling more than once.

## 6. Test reports

```sh
curl -g -u "$JENKINS_USER:$JENKINS_TOKEN" \
  "$JENKINS_URL/job/$JOB/$BUILD_NUMBER/testReport/api/json?tree=failCount,skipCount,passCount,suites[name,cases[name,status]]"
```

- **A `404` here just means the job doesn't publish a test report** (no test-results
  publisher configured, or this build predates one being added) - not an error to
  chase. On a job with no test-results step, `testReport/api/json` returns `404`.
- When present, drill into `suites[].cases[]` only for failures - `status` values
  like `FAILED`/`REGRESSION` - rather than dumping every passing case.

## 7. Health / weather trend over recent builds

Jenkins' built-in `healthReport` (§2) is a single rolled-up number. For an actual
trend, pull recent build results and look at the sequence:

```sh
curl -g -u "$JENKINS_USER:$JENKINS_TOKEN" \
  "$JENKINS_URL/job/$JOB/api/json?tree=builds[number,result,timestamp,duration]{0,20}"
```

- The `{0,20}` range-selector on `builds` caps to the most recent 20 - always cap;
  a job with thousands of builds will otherwise return the entire history.
- Read `result` across the sequence for streaks (e.g. "last 3 failed, 12 before that
  passed") and `duration` for creeping build-time regressions (common on Unreal
  incremental-cook builds as `DerivedDataCache` grows stale).

## 8. Read-only job config inspection

`config.xml` is a **GET-safe read** (only `POST` to it writes) - but it is
**permission-gated above plain read**: it requires `Job/ExtendedRead` (the
permission bundled with `Job/Configure`), not the `Job/Read` that `api/json`
uses.

```sh
curl -g -u "$JENKINS_USER:$JENKINS_TOKEN" "$JENKINS_URL/job/$JOB/config.xml"
```

Useful to confirm a job's SCM config, parameters, or `authenticationToken` (remote
trigger token) without touching the Jenkins UI - **when you have ExtendedRead**.
On a controller where anonymous or a read-only user only holds `Overall/Read` +
`Job/Read` (the common `allowAnonymousRead` dev posture), `GET .../config.xml`
returns **`403`**, not `200` - verified live against a JCasC controller with
`allowAnonymousRead: true`, where every `api/json` endpoint above returns `200`
but `config.xml` is `403`. For those same facts under plain read auth, use
`api/json` instead (`tree=...,actions[parameters[name,value]]`, `scm[...]`,
`triggers[...]`); only expect `config.xml` to work when authenticated with an
ExtendedRead-capable token.

---

## 9. Secret-exposure check - run whenever you read parameters or config

Jenkins returns build **parameters** and `config.xml` in cleartext to anyone with
read access. On an `allowAnonymousRead` controller (a common dev/internal posture)
that means *anonymous* - so a secret passed as a plain build parameter is
effectively readable by anyone who can reach the controller. This is a **proactive
check**: whenever you pull `actions[parameters[...]]` (§3) or read job config, scan
for exposed secrets rather than only looking when asked.

- **Flag a parameter as a likely secret** when its *name* matches (case-insensitive)
  `token`, `secret`, `password`/`passwd`, `api[_-]?key`, `access[_-]?key`,
  `private[_-]?key`, `credential`, or `webhook`; **or** its *value* is a long,
  high-entropy string (≈20+ chars of hex/base64) even when the name looks benign.
- **Never echo the value.** Report it set-and-redacted - e.g.
  `WEBHOOK_TOKEN = <redacted - secret exposed as a plain build parameter>`
  - the same no-echo rule the agent applies to its own tokens.
- **Recommend the fix.** A secret belongs in a **masked Jenkins credential** (Secret
  text) bound via `withCredentials`, so it's injected as an env var and scrubbed from
  logs and the parameters API - not a `StringParameterValue`, and not passed in a
  build-trigger **URL query string** (which also lands in request/proxy/access logs).
  At minimum: a masked password parameter, delivered via header or POST body rather
  than a URL query.
- **This is an observation to surface, not an action to take.** You don't have (and
  must not use) write access to rewrite someone's job from here - report the exposure
  and remediation and let the user fix it. If the exposed secret is part of the
  Perforce→Jenkins trigger loop (a webhook or trigger token), cross-ref
  `jenkins-p4-bridge`.

---

## Example - a filled status briefing

From `job/MyGame-Build/api/json?tree=...` + `queue/api/json`:

> **MyGame-Build** - `blue` (last build succeeded), health 100 (no recent
> failures). Last build #127, SUCCESS, not currently building. Last successful =
> #127, last failed = #2 (long ago). Queue is empty - nothing waiting.
>
> **MyGame-Cook** - `red` (last build failed). Worth pulling console via
> `logText/progressiveText` on the failing build number before assuming why.

(Illustrative shape - not yet captured from a live validation run.)

## Caveats

- **Anonymous read access is common** on internal/dev controllers
  (`allowAnonymousRead: true`) - a 200 on these
  endpoints without credentials doesn't mean write access works too; confirm via the
  `jenkins` agent's auth rules before proposing any write.
- **`tree=` silently drops unknown field names instead of erroring** (expected:
  `tree=jobs[bogusfield]` returns `200` with empty job objects, not a 400) -
  if a query comes back suspiciously empty, double check field spelling rather than
  assuming the data doesn't exist.
- Large controllers: always cap build-history pulls (`{0,N}` range selector) and
  scope `tree=` tightly - the failure mode here is a slow/huge response, not a
  permission error.

## Notes

- Keep everything here read-only. If observation surfaces something to act on
  (trigger a rebuild, abort a stuck build), hand off to `jenkins-operate` and
  re-confirm with the user before writing. If it looks like a Perforce-trigger
  problem (builds not firing at all), hand off to `jenkins-p4-bridge`.
