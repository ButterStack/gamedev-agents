---
name: jenkins-p4-bridge
description: >
  Diagnose the Perforce change-commit → Jenkins build loop - why a submitted
  changelist did or didn't produce a build. Covers the CI-tag grammar studios use in
  changelist descriptions, `#jenkins:JobName` routing, the native P4-plugin trigger
  path, and the exit-0-always rule that makes a broken bridge silent at submit time.
  Use when a build "should have" fired from a Perforce submit and didn't, fired for
  the wrong job, or didn't pin to the changelist you expected. Read-only diagnosis -
  hand off to `jenkins-operate` (to manually trigger) or the `perforce` agent's
  `p4-observe`/`p4-workflows` skills (to fix trigger config) once you've localized
  the fault.
---

# Jenkins ↔ Perforce Bridge Diagnosis

A Perforce submit reaching a Jenkins build is a **chain of independent hops**, and
by design **every hop on the Perforce side is silent on failure** (see §4). When a
user says "I tagged my commit `#ci` and nothing happened," your job is to walk the
chain and find which hop dropped it - not to guess or just re-trigger manually.

There are two distinct mechanisms studios wire up; know which one(s) are in play
before diagnosing:

- **A. Native P4-plugin polling trigger** - a `change-commit` trigger script on the
  Perforce server calls Jenkins' own `POST {JENKINS_URL}/p4/change` endpoint
  (provided by the Jenkins **P4 Plugin**), which tells Jenkins "a change landed,"
  and Jenkins' own SCM-polling config decides which job(s) to build. No CI tags
  involved - every commit matching the job's configured depot path can trigger.
- **B. Tag-gated routing** (a common studio pattern) - something watching Perforce
  (a webhook receiver, a
  poller) inspects the **changelist description** for a CI tag, decides *whether*
  to build at all and *which job*, then calls `buildWithParameters` directly (see
  `jenkins-operate` §1). This is where the CI-tag grammar in §2 applies.

A studio may run either, both, or neither - check which trigger mechanism is
actually configured (`p4 triggers -o`, and/or the webhook receiver's config) before
assuming tags matter.

---

## 1. Path A - the native P4-plugin trigger

The Perforce-side script (see the `perforce` agent's `p4-observe` §5 for reading the
trigger table) typically looks like:

```sh
#!/bin/bash
CHANGELIST=$1
curl -s -X POST -d "change=${CHANGELIST}" "${JENKINS_URL}/p4/change"
exit 0
```

wired into `p4 triggers -o` as:

```
jenkins-build change-commit //depot/... "/path/to/jenkins-trigger.sh %changelist%"
```

Diagnose in order:

1. **Is the trigger firing?** `p4 triggers -o` (needs `super`) shows the table
   exists and the path matches the submitted changelist's depot. No visibility from
   a non-admin account - degrade to checking Perforce server logs
   (`$P4ROOT/logs/log`) for the trigger's invocation if you have access, or ask an
   admin.
2. **Is Jenkins receiving it?** From the Jenkins side, there's no REST GET for "did
   `/p4/change` get hit" - check the P4 plugin's own log (Jenkins → Manage Jenkins →
   System Log, or the controller's `jenkins.log`) for `/p4/change` POSTs. A
   reachability sanity check (read-only, safe): confirm the endpoint responds at
   all:
   ```sh
   curl -sS -m5 -o /dev/null -w "%{http_code}\n" "$JENKINS_URL/p4/change"
   ```
   A connection failure/timeout here from the *Perforce server's* network position
   (not your workstation's) is the most common real-world break - firewalls between
   the P4 server and Jenkins are a frequent gap.
3. **Did the right job build?** The P4 plugin's own SCM-polling configuration (per
   job, "Source Code Management → Perforce") decides which job(s) respond to a given
   depot path - there's no tag involved in Path A. If the wrong job (or no job)
   built, check that job's SCM config (`jenkins-observe` §8, `config.xml`) for the
   depot path it's watching.

## 2. Path B - CI-tag grammar (changelist description)

A watcher scanning changelist descriptions recognizes these patterns
(case-insensitive; substring match, not whole-word - so a false-positive on
unrelated text containing e.g. `ci:` is possible):

```
#ci   #build   #jenkins
[ci]  [build]  [jenkins]
ci:   build:   jenkins:
--ci  --build  --jenkins
```

Any one of these anywhere in the description is enough to mark the changelist as
CI-triggering - the presence check and the job-routing check are **separate**
(§2 continued below always fires *some* job once the presence check passes, using
the fallback order if no explicit job is named).

> **⚠ Validated 2026-07-17 - a shell `change-commit` trigger and an app-side webhook
> receiver often implement *different* tag grammars, so don't assume §2's full grammar
> applies to whichever one is installed.** A common split, confirmed on a real setup:
> - A **shell `change-commit` trigger** that does a plain substring grep for a single
>   tag (e.g. `grep -qi "#ci"`) matches **only that one literal tag** - it does **not**
>   honor `#build`, `#jenkins`, `[ci]`, `ci:`, or `--ci`, has **no `#jenkins:JobName`
>   routing** (it always POSTs to one configured job), and **false-positives on any
>   `#ci...` substring** (`#cirrus`, `#cicd`, `#circle` all fire a build - substring, not
>   whole-word).
> - The **full grammar** and **`#jenkins:JobName` routing** typically live in the
>   separate **app-side webhook receiver** (the service implementing the should-trigger
>   + job-routing logic behind a `POST .../webhooks/...` endpoint) - a different code path
>   from the shell trigger.
>
> Before trusting §2's grammar, confirm **which** mechanism is installed (`p4 triggers
> -o` + the webhook receiver's config): a bare substring-grep shell trigger understands
> only its one tag and can't route; the app path understands the rest. See §5 for the
> full validated behavior.

**Job routing** - `#jenkins:JobName` / `[jenkins:JobName]` (and the `ci`/`build`
synonyms: `#ci:JobName`, `[build:JobName]`) name an explicit job:

1. If a specific job is named, it's only honored if it's in the integration's
   **`selected_jobs`** allow-list (or that list is empty, meaning "any job is
   allowed"). A named job **not** in `selected_jobs` is rejected with a warning -
   the build does **not** silently fall through to a different job.
2. If no job is named (or the named one was rejected), fall back in order:
   `selected_jobs.first` → the integration's configured default `job_name` → **no
   job at all**. A missing job configuration is a deliberate dead-end, not a guess -
   the bridge will not invent a job name to try.

**Diagnose a "tagged but nothing built" report** by checking, in order:

1. **Does the description actually contain a recognized pattern?** Re-read it
   literally - `p4 describe -s <n>` (full description, not truncated `-ztag`; see
   `p4-observe`). A near-miss like `CI Ready` or `#cireview` won't match; only the
   exact substrings above do.
2. **Is a job resolvable?** Walk the routing logic above by hand against the
   description text and the integration's configured `selected_jobs`/`job_name`. A
   named-but-not-allowed job is a common silent-looking failure - it logs a warning
   server-side but produces no submitter-visible error (see §4).
3. **Did the changelist predate the integration?** Some bridges deliberately skip
   changelists submitted before the CI integration was configured (to avoid a flood
   of historical builds on first setup) - check the integration's creation time
   against the changelist's submit time if builds are only missing for old CLs.
4. **Gotcha - the trigger-presence check and the inbound-webhook check can use
   different pattern lists.** If a studio has both a submit-time watcher and a
   separate inbound-webhook receiver for the same event, verify **both** recognize
   the tag your commit used; a tag that's valid in one code path's grammar isn't
   guaranteed valid in the other's if they were written independently. When in
   doubt, use the most conservative common tag (`#ci` or `#build` match everywhere)
   rather than a less common synonym.

## 3. "Did the build pin to the right changelist?"

Once a build *did* fire, confirm it ran against the changelist you expect -
mismatches happen when a job builds off `//depot/...` HEAD rather than the specific
triggering changelist:

```sh
curl -g -u "$JENKINS_USER:$JENKINS_TOKEN" \
  "$JENKINS_URL/job/$JOB/$BUILD_NUMBER/api/json?tree=actions[parameters[name,value]],changeSet[items[changeNumber,msg]]"
```

- `actions[parameters]` shows the `P4_CHANGELIST` (or equivalently named) parameter
  the build was **triggered with** - compare it to the changelist number you expect.
- `changeSet[items[changeNumber]]` (populated when the job's P4-plugin SCM step
  actually synced) shows what it **actually built against** - these two can
  legitimately differ (e.g. a job configured to sync `@now`/head rather than the
  passed-in changelist parameter). If they differ and the job was meant to pin
  exactly, that's a job-configuration issue (`config.xml`'s Perforce populate
  options), not a trigger-bridge issue - hand off with that distinction made
  explicit.
- No `changeSet` at all commonly means the job isn't actually using the P4 plugin's
  SCM step for its checkout (e.g. a shell step doing its own `p4 sync`) - expected
  for hand-rolled pipelines, not a bug.

## 4. The exit-0 rule - why the bridge fails silently

**A healthy Perforce `change-commit` trigger always exits 0, even when the
downstream call fails** - this is by design: a trigger that could block a submit on
a webhook/Jenkins outage would take down the whole team's ability to check in code
over a CI hiccup. The practical consequence: **a submitter is never told the bridge
is broken.** `p4 submit` succeeds normally regardless of whether Jenkins ever heard
about it.

This means:

- Don't treat "the submit went through fine" as any evidence the trigger worked -
  it's evidence of nothing on the CI side.
- The correct place to look for a silent break is always downstream: Jenkins-side
  logs/build history (Path A) or the webhook receiver's logs (Path B), never the
  Perforce submit output.
- If `p4-observe` §2's CI-tag analysis shows tags being used consistently but the
  corresponding build volume (Jenkins job's `builds[]` count over the same window)
  doesn't track, that gap **is** the signal of an outage - cross-reference the two
  data sources rather than trusting either alone.

## 5. Validated behavior - CSRF auth on the trigger, and the p4d version floor

Validated live 2026-07-17 against **Jenkins 2.504.2** (CSRF enabled) + **p4d 2025.2**,
driving a real shell `change-commit` trigger:

- **A shell trigger's default call 403s under CSRF.** A trigger that fires
  `buildWithParameters?P4_CHANGELIST=<CL>&token=<remote-trigger token>` with no Basic
  auth, against a CSRF-enabled controller, returns **403 "No valid crumb was included
  in the request"** - the job `?token=` param is **not** crumb-exempt (only API-token
  Basic auth is; see `jenkins-operate` §0). Fix: set `JENKINS_USER` + `JENKINS_PASSWORD`
  (an **API token**) so the trigger uses crumb-exempt Basic auth (→ 201), or disable
  CSRF (what many dev images do, precisely to let bare-`?token=` triggers through). A
  403 in the trigger's log is this - not a p4 fault.
- **Diagnostics, with the codes you actually see:**
  1. **Firing?** A p4d `change-commit` trigger's stdout is discarded on `exit 0` -
     redirect it (`your-trigger.sh %change% >> /tmp/trigger.log`) to see whether it ran
     and found/skipped the tag. An **empty** log usually means the trigger table didn't
     install: the trigger spec form needs a **literal TAB** before each line - verify
     with `p4 triggers -o` (spaces silently produce no trigger).
  2. **Receiving?** The script logs the Jenkins HTTP code: **403** = CSRF/auth (token
     param instead of Basic auth), **000** = network/DNS (couldn't reach the
     controller), **201/200** = accepted.
  3. **Pinned?** `/job/JOB/N/api/json?tree=actions[parameters[name,value]]` →
     `P4_CHANGELIST` equals the submitted change (verified: builds pinned to their CL).
- **`exit 0` confirmed** - every `p4 submit` succeeded even with the webhook
  unreachable (000) *and* Jenkins returning 403; the trigger never blocks a submit.
- **p4d version floor (setup gotcha).** If you build a p4d image from the **unpinned
  `helix-p4d` apt package**, the Perforce repo now serves **p4d 2026.1**, which
  **enforces a `security=4` floor** (it clamps `security` back to 4 on every startup),
  breaking a `security=0` dev bootstrap and trigger install. Pin `helix-p4d` +
  `p4-server` + `p4-server-base` to `2025.2-2907753~noble` (pinning only `helix-p4d` is
  insufficient - the server binary comes from `p4-server-base-NN.N`).

## Cross-reference

- Perforce-side trigger table health and CI-tag description analysis:
  `perforce` plugin's `p4-observe` skill, §5 ("Trigger / CI configuration health").
- Manually triggering a build once you've confirmed the bridge itself is broken (as
  a stopgap while the bridge is fixed): `jenkins-operate` §1 - still show + confirm,
  same as any other trigger.
- Reading job/build status and console to see what a fired build actually did:
  `jenkins-observe`.
