# Perforce Agent - Integration Learnings (running log)

Dated log of what running Perforce integrations *for real* teaches us - the stuff
that isn't obvious from the docs. Companion to [`NOTES.md`](./NOTES.md) (design
rationale) and the real-depot testing-report template in
[`../CONTRIBUTING.md`](../CONTRIBUTING.md).

`[skill]` = the agent's own diagnosis was wrong or thin (graduates into the
skills). `[integration]` = how a real Perforce integration actually behaves.
Newest first, dated. No secrets - reference credential *locations*, never paste
them.

---

## 2026-07-16 - p4 trigger/webhook ingestion `[integration]`

Learned wiring Perforce change-triggers into a webhook ingestion pipeline:

- **Validate the changelist number as a positive integer before doing any work.**
  A p4 trigger hands you the changelist as a *string*; treat non-positive/
  non-numeric as a clean `4xx` reject, never `5xx`, never silent-accept. Replayed
  triggers, misfires, and health probes all send junk here.
- **A CL-`0` reachability probe returning `400` is healthy, not broken.** Monitors
  often ping the endpoint with changelist `0` to confirm it's alive; with the guard
  above that's a `400 invalid changelist` - proof the endpoint is up and
  validating. Only `5xx`/connection-refused means broken. We burned real time
  treating a benign, months-old `400` as the cause of an unrelated failure.
- **Inbound auth is a token-in-URL, not an HMAC signature.** A Perforce trigger is
  a shell script on the server - it doesn't natively HMAC-sign a body. The pattern
  is a secret token embedded in the trigger's target URL (or a header it sets),
  validated per integration - don't "fix" this path to expect a signature.
- **The token is per-integration - never share one webhook-config fixture across
  projects.** A shared trigger-config file cross-wires projects under
  concurrency (last writer's token wins). Give each integration its own token and
  config path.
- **Ingestion is async - ack fast, then poll.** Return `202` immediately and hand
  off to a background job; the "did it land?" poll window has to account for
  queue depth, not just a couple of seconds.

Verified live against a real p4 → webhook → changelist ingestion pipeline.
