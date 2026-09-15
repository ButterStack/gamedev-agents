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

## 2026-09-14 - the typemap is one server-wide table, and a p4d container image is a second writer `[integration]`

Learned running a Git->Perforce mirror against a p4d that ships as a Docker image and
re-applies its own engine typemap preset on every container start, not just first
provision.

- **`p4 typemap` is a single server-wide table, so "add my depot's rows" is a
  read-modify-write against state someone else also owns.** The documented pattern
  (`p4 typemap -o | <insert rows> | p4 typemap -i`) has no compare-and-swap - any other
  writer that reads, edits, and writes the whole table drops rows it doesn't know about.
- **The other writer here was the p4d image itself.** Its startup script re-applies an
  engine preset on every boot, and a restart taken just to pick up an unrelated image
  upgrade silently removed six depot-scoped rows a different provisioning script had
  appended - nothing failed at the time, the rows were simply gone.
- **The exposure window measured ~8 minutes, not seconds**, timestamped on one real
  restart. Because typemap only applies to newly-added files, a submit landing inside the
  window leaves mis-typed files behind after the window closes, needing `p4 edit -t
  <type>` to fix.
- **So verify the rows before the first `add` and fail the run - don't warn and
  continue.** A sync job that warns will add a whole tree with the wrong types during a
  restart window; a hard fail costs one retried run instead.
- **Without a spec depot, there's no history or author for typemap/protections edits** -
  `p4 typemap -o` shows current state only, and forensics stop dead. `p4 depots` tells
  you in one command whether you have one.

## 2026-09-14 - "Wrong number of words", and what p4's exit codes do under `set -e` `[skill]`

Three diagnostic details that cost real time chasing the entry above.

- **"Wrong number of words for field 'X'" doesn't always mean what `p4-observe`'s
  trigger-table advice says.** That advice is right for the *trigger* table (an
  unquoted command containing spaces). For the **typemap** spec, the identical string
  *is* whitespace: rows must be TAB-indented. Read the error against the spec you're
  actually editing.
- **`p4` exits 1 with empty stdout on both "cannot connect" and "no ticket,"** verified
  against a live server. That matters under `set -euo pipefail`: an assignment like
  `current="$(p4 typemap -o)"` **aborts** on those failures rather than yielding an
  empty string - so a script that reaches its "rows are missing" branch really did read
  successfully; it's not a swallowed connection error.
- **Idempotency keyed on a description trailer must accept every width its writers
  actually produce.** A mirror recording `Original-Commit: <sha>` and matching it back
  with a 40-char-only pattern missed a code path that wrote an abbreviated sha, read
  that as "nothing synced," and replayed the branch from its root commit - which then
  failed inside git-p4's apply step with "No valid patches in input." Matching a
  variable-width sha and resolving it to the full value locally fixed it; treat an
  unresolvable trailer as a hard error, not as "nothing synced."

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
