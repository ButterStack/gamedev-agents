# Perforce Agent - Integration Learnings (running log)

Dated log of what running Perforce integrations *for real* teaches us - webhook/trigger
ingestion, connection/auth, depot behavior - the stuff that isn't obvious from the docs.
Companion to [`NOTES.md`](./NOTES.md) (design rationale) and the real-depot testing-report
template in [`../CONTRIBUTING.md`](../CONTRIBUTING.md).

Two kinds of entry - tag each one:

- **`[skill]`** - where the agent's own diagnosis or a playbook was wrong or thin. These
  graduate into the skills (that's the feedback loop).
- **`[integration]`** - how a real Perforce integration (triggers, webhooks, CI, ingestion)
  actually behaves. Useful to anyone wiring `p4` into a pipeline even if it never touches a
  skill.

Conventions: newest first, dated. No secrets - reference token/credential *locations*, never
paste them. Prefer relative links so entries survive a repo rename. This is where the team logs
what each real integration teaches us; sibling plugins keep their own (e.g.
[`../unreal/LEARNINGS.md`](../unreal/LEARNINGS.md)).

---

## 2026-07-16 - p4 trigger/webhook ingestion: validate the changelist, the CL-0 probe, per-integration tokens `[integration]`

Learned wiring Perforce change-triggers into a webhook ingestion pipeline (and chasing a
red-herring failure for longer than we'd like to admit).

- **Validate the changelist number as a positive integer before doing any work.** A p4
  trigger (or a webhook layer in front of it) hands you the changelist as a *string*. Treat
  non-positive / non-numeric as a hard, clean `4xx` reject - never `5xx`, never silent-accept.
  The guard is just `change_number.to_i > 0`, but it's load-bearing: replayed triggers,
  misfires, and health probes all send junk here.

- **The CL-`0` reachability probe is a healthy 400, not a broken webhook.** A monitor or test
  harness will often ping the ingest endpoint by POSTing changelist `0` to confirm it's alive.
  With the guard above, that returns `400 invalid changelist` - which is *proof the endpoint is
  up and validating*. Treat "rejected an intentionally-invalid probe" (`400`) as **reachable**;
  only `5xx` / connection-refused means broken. We burned real time treating a benign `400`
  (that had printed on every test run for months) as the cause of an unrelated failure. If your
  probe logs a warning, make it say "reachable" on that specific 400 - not "webhook may be
  broken."

- **Inbound auth is a token-in-URL, not an HMAC signature.** Unlike GitHub / Jira / GitLab, a
  Perforce trigger is a shell script on the server - it doesn't natively HMAC-sign a JSON body.
  The pragmatic pattern is a **secret token embedded in the trigger's target URL** (or a header
  the trigger script sets), validated per integration. A webhook-hardening pass that assumes
  signature validation does *not* apply to the p4 path - don't "fix" it to reject unsigned p4
  triggers.

- **The token is per-integration, so never share one webhook-config fixture across projects.**
  Each integration has its own token; a global/shared trigger-config file (one path, rewritten
  per run) will cross-wire projects under any concurrency - last writer's token wins and events
  land on the wrong project. Give each integration/test its own token + config path (mirror your
  parallel-test isolation pattern). This bit us in a parallel test run and looked like a Perforce
  bug; it was a shared-fixture race.

- **Ingestion is async - ack fast, then poll.** The webhook should return `202` immediately and
  hand off to a background job; "did the changelist surface?" is a *poll*, and the poll window
  has to account for queue depth (a busy worker under parallel load needs more than a couple
  seconds before you call it a failure).

Verified live against a real p4 → webhook → changelist ingestion pipeline (a real changelist
synced end-to-end on the same build the failure was reported against).
