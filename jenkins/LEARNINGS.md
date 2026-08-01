# Jenkins Agent - Integration Learnings (running log)

Dated log of what running Jenkins integrations *for real* teaches us - CSRF/crumb
behavior, trigger/queue semantics, the Perforce change-commit → build loop - the
stuff that isn't obvious from the docs. Companion to [`NOTES.md`](./NOTES.md) (design
rationale) and the real-controller testing-report template in
[`../CONTRIBUTING.md`](../CONTRIBUTING.md).

Two kinds of entry - tag each one:

- **`[skill]`** - where the agent's own diagnosis or a playbook was wrong or thin. These
  graduate into the skills (that's the feedback loop).
- **`[integration]`** - how a real Jenkins integration (triggers, webhooks, CI,
  the Perforce bridge) actually behaves. Useful to anyone wiring Jenkins into a
  pipeline even if it never touches a skill.

Conventions: newest first, dated. No secrets - reference token/credential *locations*,
never paste them. This is where the team logs what each real integration teaches us;
sibling plugins keep their own (e.g. [`../perforce/LEARNINGS.md`](../perforce/LEARNINGS.md)
and [`../unreal/LEARNINGS.md`](../unreal/LEARNINGS.md)).

---

## 2026-07-17 - crumb-present + Perforce bridge, validated against a CSRF-enabled controller `[integration]`

Learned standing up a purpose-built, disposable, CSRF-enabled **Jenkins 2.504.2** +
**p4d 2025.2** stack (isolated, torn down afterward) to validate the write path and
the Perforce→Jenkins trigger bridge under conditions closer to a real, locked-down
controller than the earlier CSRF-off dev pass below.

- **API-token auth is EXEMPT from the CSRF crumb; username+password is not.** The
  crumb-in-session dance is unnecessary when the agent authenticates with an API
  token (kept as a password fallback, where the crumb dance still applies). The bare
  `?token=` remote-trigger parameter is **not** crumb-exempt (`403` under CSRF) - a
  shell trigger calling `buildWithParameters` must use API-token Basic auth, or the
  controller must run CSRF-off.
- **`303`/`302` = queued (accepted), not failure.** An earlier internal error-code
  table had this wrong. A missing required parameter returns `201` (not `500`,
  another wrong table entry); a `replay` call with a bare `mainScript` parameter
  returns `400`.
- **The Perforce-side shell trigger only pattern-matches a literal `#ci` tag** (and
  false-positives on `#ci...` substrings) with no job-routing logic of its own - any
  richer CI-tag grammar (`#build`, `[ci]`, `ci:`, `--ci`, `#jenkins:JobName` routing)
  has to live on the side that parses the changelist description, not in the trigger
  script itself. The trigger always pins the changelist number and always `exit 0`s
  (confirmed) - it must never block a `p4 submit`.
- **Setup gotcha:** `p4d 2026.1` enforces a `security=4` floor that an older Jenkins
  trigger script may not expect - pin the p4d image version you validate against, or
  budget time to update the trigger for the stricter security level.

Verified live against a real CSRF-enabled Jenkins + p4d stack, disposable and torn
down after the session.

## 2026-07-16 - read/write path validation against real controllers `[integration]`

Learned validating the `jenkins-observe` (read) and `jenkins-operate` (write) skills
against real Jenkins controllers, including a job with a plain-string webhook token
that turned into the most useful single finding of the pass.

- **`GET config.xml` needs `Job/ExtendedRead`, not just `Job/Read`.** An earlier
  internal note claimed `config.xml` returns `200` under normal read auth. Live
  (anonymous read on two different real controllers) it returns **`403`** - reading a
  job's raw config needs the `Job/ExtendedRead` permission, a level above the
  `Job/Read` that `api/json` uses. Don't assume config-file access follows from
  ordinary read access.
- **A plain-string build parameter is not a secret, even if it holds one.** A real job
  passed a webhook token as a plain `StringParameter`, so its value was readable via
  `api/json` by any read (including anonymous) user - a general Jenkins footgun, not
  specific to any one pipeline. This prompted a standing rule: the agent now
  proactively scans build parameters and config for values that look like
  secrets (name matches token/secret/key/password/webhook, or high entropy), reports
  them redacted, and recommends a masked `withCredentials` credential instead of a
  plain string parameter.
- **`replay/api/json` does not exist** (404), and **`replay/run` needs a Stapler
  `json` form field**, not a bare `mainScript` parameter (a bare parameter gets
  `400 "This page expects a form submission"`). An earlier internal note had this
  wrong; corrected and verified live: replay via the correct form field returns `302`
  and a new build runs the edited script.
- **The crumb-`404` → no-crumb-header branch is real and worth handling
  explicitly**: on a CSRF-off controller, `/crumbIssuer/api/json` 404s, and a write
  should skip the crumb header entirely rather than sending a stale or empty one.
- Confirmed live on the read side: identity (`whoAmI` → anonymous/authenticated),
  CSRF-off detection (`crumbIssuer` → 404), `tree=` job listing (with `-g`), per-job
  status + `healthReport`, weather/build-history trend (`builds[...]{0,N}`),
  empty-queue shape, folder nested-job access, build `actions[parameters[...]]`,
  `progressiveText` tailing (`X-Text-Size` present, `X-More-Data` absent on a
  finished build), and `testReport` 404 = no publisher. Confirmed live on the write
  side (against a disposable throwaway pipeline job, created and deleted): trigger
  `buildWithParameters` → `201` + `Location` queue URL → queue-poll to a build number
  (parameter carried through), abort `/stop` → `302` → `result: ABORTED`.
