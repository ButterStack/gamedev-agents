# Jenkins Agent - Integration Learnings (running log)

Dated log of what running Jenkins integrations *for real* teaches us - the stuff
that isn't obvious from the docs. Companion to [`NOTES.md`](./NOTES.md) (design
rationale) and the real-controller testing-report template in
[`../CONTRIBUTING.md`](../CONTRIBUTING.md).

`[skill]` = the agent's own diagnosis was wrong or thin. `[integration]` = how a
real Jenkins integration actually behaves. Newest first, dated. No secrets -
reference credential *locations*, never paste them.

---

## 2026-07-17 - crumb-present + Perforce bridge, against a CSRF-enabled controller `[integration]`

Validated the write path and the Perforce→Jenkins trigger bridge against a
purpose-built, CSRF-enabled Jenkins + p4d stack - closer to a real, locked-down
controller than a permissive dev instance.

- **API-token auth is EXEMPT from the CSRF crumb; username+password is not.** The
  crumb-in-session dance is unnecessary with an API token (kept as a password
  fallback, where it still applies). The bare `?token=` remote-trigger parameter
  is **not** crumb-exempt (`403` under CSRF) - a shell trigger calling
  `buildWithParameters` must use API-token Basic auth, or the controller must run
  CSRF-off.
- **`303`/`302` = queued (accepted), not failure**, correcting an earlier wrong
  error-code table; a missing required parameter returns `201` (not `500`), and a
  `replay` call with a bare script parameter returns `400`.
- **A Perforce-side shell trigger that only pattern-matches a literal `#ci` tag**
  has no job-routing logic of its own - any richer CI-tag grammar has to live on
  the side that parses the changelist description. The trigger always pins the
  changelist number and always `exit 0`s - it must never block a submit.
- A newer p4d can enforce a stricter security floor than an older Jenkins trigger
  script expects - pin the server version you validate against.

## 2026-07-16 - read/write path validation against real controllers `[integration]`

Validated the read and write skills against real Jenkins controllers, including a
job with a plain-string webhook token that became the most useful single finding
of the pass.

- **`GET config.xml` needs `Job/ExtendedRead`, not just `Job/Read`.** Anonymous
  read on two different real controllers returned `403` - reading a job's raw
  config needs a permission level above the one `api/json` uses.
- **A plain-string build parameter is not a secret, even if it holds one.** A
  real job passed a webhook token as a plain `StringParameter`, so its value was
  readable via `api/json` by any read (including anonymous) user - a general
  Jenkins footgun, not specific to any one pipeline. This is now a standing rule:
  the agent proactively scans build parameters and config for values that look
  like secrets, reports them redacted, and recommends a masked credential instead
  of a plain string parameter.
- **`replay/api/json` does not exist** (404), and `replay/run` needs a proper form
  field, not a bare script parameter (which gets a generic-looking `400`).
  Corrected and verified live: replay via the correct form returns `302` and a
  new build runs the edited script.
- **The crumb-`404` → no-crumb-header branch is real**: on a CSRF-off controller
  the crumb-issuer endpoint 404s, and a write should skip the crumb header
  entirely rather than send a stale or empty one.
- Confirmed live: identity and CSRF-off detection, scoped job listing, status and
  health trend, log-tailing on running and finished builds, and (against a
  disposable throwaway job) the full trigger → queue → build-number → abort
  cycle.
