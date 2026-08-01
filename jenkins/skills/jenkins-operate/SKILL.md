---
name: jenkins-operate
description: >
  Gated Jenkins write operations - triggering a parameterized build, aborting a
  build, and replaying a pipeline. Every operation here fetches its CSRF crumb and
  performs the write in ONE HTTP session, and every operation requires showing the
  user exactly what will happen and getting explicit confirmation first. Use only
  after the `jenkins-observe` skill has established what's actually happening - this
  skill mutates the controller.
---

# Jenkins Operate

Every playbook here **writes** to the Jenkins controller. Follow the same discipline
the `perforce` agent uses for `p4 submit`: **show the target and the exact action,
then wait for explicit confirmation before running it.** Never chain a trigger/abort
straight off an observation without that pause.

Resolve identity and crumb rules from the `jenkins` agent before using this skill.
All examples use `curl -g` (see `jenkins-observe` for why `-g`/`--globoff` matters
whenever a URL has `tree=field[...]` brackets - not relevant to most calls here,
but harmless to always include).

---

## 0. The crumb rule - API-token writes are exempt; password writes need a same-session crumb

**Validated live (Jenkins 2.504.2, CSRF on): a write authenticated with an API token
is exempt from CSRF - it succeeds with no crumb.** So with an API token (`-u
user:apitoken`) you may POST writes directly. The crumb-in-session dance below is only
needed for **username+password** auth (or the job's `?token=` remote-trigger param),
which 403s (`No valid crumb was included in the request`) unless it carries a valid
crumb **plus the session cookie from the same connection that fetched it**. The
pattern below is harmless under token auth (an extra crumb is ignored) and correct
under password auth - fetch the crumb and perform the write **in the same cookie
session** (two separate `curl` invocations without a shared cookie jar produce an
invalid crumb):

```sh
# One session: crumb fetch + write share a cookie jar.
COOKIES=$(mktemp)
CRUMB_JSON=$(curl -g -sS -c "$COOKIES" -b "$COOKIES" \
  -u "$JENKINS_USER:$JENKINS_TOKEN" \
  "$JENKINS_URL/crumbIssuer/api/json")

if [ -n "$CRUMB_JSON" ]; then
  CRUMB_FIELD=$(echo "$CRUMB_JSON" | jq -r '.crumbRequestField')
  CRUMB_VALUE=$(echo "$CRUMB_JSON" | jq -r '.crumb')
  CRUMB_HEADER=(-H "$CRUMB_FIELD: $CRUMB_VALUE")
else
  CRUMB_HEADER=()   # 404 on crumbIssuer ⇒ CSRF off; send no crumb header
fi

curl -g -sS -c "$COOKIES" -b "$COOKIES" -u "$JENKINS_USER:$JENKINS_TOKEN" \
  "${CRUMB_HEADER[@]}" -X POST "$JENKINS_URL/job/$JOB/build" -w '\nHTTP:%{http_code}\n'

rm -f "$COOKIES"
```

If `crumbIssuer` 404s, skip the header entirely rather than sending a stale/empty
one - some configurations reject a present-but-wrong crumb header more aggressively
than a missing one.

## 1. Trigger a build (`buildWithParameters`) - show, then confirm

**Before triggering anything**, show the user:

1. The exact job name and its current state (buildable? currently building already?
   - pull from `jenkins-observe` §2).
2. The parameters you're about to send and their values.
3. Whether this looks like a production/deploy/release job (see the agent's
   destructive-ops list) - if so, require the user to name the job explicitly.

Only after confirmation, trigger:

```sh
curl -g -sS -c "$COOKIES" -b "$COOKIES" -u "$JENKINS_USER:$JENKINS_TOKEN" \
  "${CRUMB_HEADER[@]}" -X POST \
  --data-urlencode "P4_CHANGELIST=$CHANGELIST" \
  --data-urlencode "PARAM2=$VALUE2" \
  "$JENKINS_URL/job/$JOB/buildWithParameters" \
  -D - -o /dev/null
```

- **Expect `201 Created`** with a `Location` header pointing at a **queue item**
  URL (`$JENKINS_URL/queue/item/<id>/`), not a build number yet - the build hasn't
  necessarily started, only been queued. Poll `$JENKINS_URL/queue/item/<id>/api/json`
  (see `jenkins-observe` §4) until it resolves to an `executable` with a real build
  `number`.
- A job with **no** parameters uses plain `build` (no `WithParameters`) - same crumb
  rule applies.
- **`201` and `303` both mean "queued" - neither is a failure** (validated: Jenkins
  2.504.2). `201 Created` = a fresh queue item; `303 See Other` (redirect to the same
  `/queue/item/N/`) = an identical parameter set re-submitted within the ~5s quiet
  period, deduped into the already-queued item. Only **`403`** (missing/invalid crumb
  under password or `?token=` auth) or **`400`** (malformed request) means the write
  was rejected - re-check auth then.

### A Perforce-triggered build contract (worked example)

A concrete worked example of the pattern above - the shape a Perforce trigger uses to
fire a parameterized build:

```
POST {JENKINS_URL}/job/{JOB}/buildWithParameters
    ?P4_CHANGELIST=...&WEBHOOK_TOKEN=...&token={trigger-token}
Authorization: Basic base64(user:api_token)
```

Expect `201` + `Location`; the crumb is fetched in the same HTTP session as this
POST. The `token=` query param (distinct from the CSRF crumb) is Jenkins' own
**remote trigger authentication token** (`authenticationToken(...)` in a Job DSL /
Jenkinsfile, or "Trigger builds remotely" + auth token in the classic UI) - a
per-job secret that lets an external system (a Perforce trigger script) fire a
build without a full user session. **Validated live (Jenkins 2.504.2, CSRF on): the
bare `?token=` remote-trigger param is NOT crumb-exempt** - a `buildWithParameters
?token=...` call with no Basic auth (or with a cross-session crumb) returns **403 "No
valid crumb"**. Only **API-token Basic auth** is crumb-exempt. So against a
CSRF-enabled controller, trigger with API-token Basic auth (`-u user:apitoken`); the
`?token=` param alone is not enough. (This is exactly why some dev images disable CSRF
- to let bare-`?token=` Perforce triggers through; see `jenkins-p4-bridge`.)

## 2. Abort a build

**Only your own build, or the user has explicitly named someone else's** (aborting
another user's running build is on the agent's destructive-ops list - confirm by
name and explain the impact: their in-progress work is killed, not paused).

```sh
curl -g -sS -c "$COOKIES" -b "$COOKIES" -u "$JENKINS_USER:$JENKINS_TOKEN" \
  "${CRUMB_HEADER[@]}" -X POST "$JENKINS_URL/job/$JOB/$BUILD_NUMBER/stop"
```

- `/stop` requests a graceful interrupt; a build already mid-shutdown or unresponsive
  may need `/kill` (harder stop) or `/term` - treat both as a stronger version of the
  same destructive action, same confirmation bar.
- Verify afterward: re-fetch `.../api/json?tree=result,building` and confirm
  `result: "ABORTED"`, `building: false`.

## 3. Replay a pipeline

Replay re-runs a **Pipeline** job's exact script (optionally edited) against the
same or new parameters, without touching the job's saved configuration.

1. Review the script before replaying. There is **no** `replay/api/json` endpoint -
   `.../$BUILD_NUMBER/replay/api/json` returns `404` (verified); the script is not
   exposed as JSON. Read it from the job's pipeline definition instead - the
   `<script>` inside the `CpsFlowDefinition` in `.../job/$JOB/config.xml` (config.xml
   needs `Job/ExtendedRead`, see `jenkins-observe` §8) - or open
   `.../$BUILD_NUMBER/replay/` in a browser (its textarea is pre-filled with the exact
   script that will run). **Show the script (or a diff, if the user wants to change
   it) to the user before submitting**, exactly like showing a changelist description
   before `p4 submit`.
2. Submit the replay - same crumb-in-session write as §1. `replay/run` is a Stapler
   **form submission**: the script and any shared-library overrides go inside a single
   `json` form field, **not** a bare `mainScript` param - a plain `mainScript` POST
   fails with `400 "This page expects a form submission"` (verified). Write the JSON to
   a file to sidestep shell-quoting, then post it:
   ```sh
   cat > replay.json <<'JSON'
   {"mainScript":"node { echo 'hello' }","libs":[]}
   JSON
   curl -g -sS -c "$COOKIES" -b "$COOKIES" -u "$JENKINS_USER:$JENKINS_TOKEN" \
     "${CRUMB_HEADER[@]}" -X POST --data-urlencode "json@replay.json" \
     "$JENKINS_URL/job/$JOB/$BUILD_NUMBER/replay/run" -D - -o /dev/null
   ```
   Add shared-library overrides inside the same JSON:
   `"libs":[{"name":"<lib>","version":"<ref>"}]` (some Jenkins versions name the empty
   field `"additionalScripts":[]` instead of `"libs":[]` - both accept an empty array).
   **Expect `302`** redirecting back to the job (not `201`). Same CSRF rule as §0
   (validated Jenkins 2.504.2): API-token Basic auth needs no crumb (→ `302` + new
   build); password without a crumb → `403`; a bare `mainScript` param without the
   `json` wrapper → `400`.
3. Replay creates a **new build number** - report which one, confirm its early console
   lines ran the intended script, and point the user to `jenkins-observe` to follow it
   (queue → console tail).

Replay is powerful (it accepts an edited script) - treat a **changed** script with
extra scrutiny: read the diff back to the user and confirm they intended the change,
not just that they intended "replay."

## 4. Verify every write actually did what you think

Jenkins doesn't always fail loudly. After any operation in this skill:

- Trigger → confirm the queue item resolved to a real build and that build's
  parameters (`actions[parameters[...]]`) match what you sent.
- Abort → confirm `result: "ABORTED"`, not still `building: true`.
- Replay → confirm the new build number exists and pulled the script you expected
  (spot-check console output's early lines if unsure).

## Notes

- Every operation in this file is a write. If you're not sure whether a request is
  observation or operation, it's observation - use `jenkins-observe` and ask before
  switching to this skill.
- Never trigger a job whose name signals production/deploy/release without the user
  naming that exact job - see the `jenkins` agent's destructive-ops list.
- If a trigger appears to have fired but the corresponding Perforce-side change never
  shows up correlated to it (or vice versa - a changelist has a CI tag but no build
  ever appears), that's a `jenkins-p4-bridge` investigation, not a retry-harder loop
  here.
