---
description: Summarize the current Perforce workspace & server state (connection, ticket, opened files, pending/shelved changelists, locks, reconcile drift)
argument-hint: "[depot-subtree]"
---

Summarize the current Perforce (Helix Core) state for the user. Read-only - run no
write/destructive command in this workflow. Use the `p4-observe` skill for the exact
command forms. Scope to `$ARGUMENTS` if a subtree is given, else the full client view.

Gather and report, in order:

1. **Connection & identity** - `p4 -ztag info` (server, `serverVersion`,
   `serverUptime`, `userName`, `clientName`, `clientRoot`, `clientCase`). Resolve
   user/client from `p4 info`, never `$USER`. If `clientName` is `*unknown*`, say so -
   no workspace is set; treat this as an **audit-only** run and use the
   client-independent forms noted below (a read-only audit needs no workspace).
2. **Auth** - `p4 login -s` (ticket expiry, or expired/not-logged-in). Note that a
   passing `p4 info` does not imply a valid ticket.
3. **Opened files** - `p4 opened` (this client) grouped by changelist, noting action
   (edit/add/delete) and `+l` locks. **With no workspace** (`clientName` `*unknown*`),
   `p4 opened` errors `Client ... unknown` - use `p4 opened -a <scope>` for the depot-wide
   picture instead.
4. **Pending changelists** - `p4 changes -s pending -u <user> -l` with descriptions;
   flag stale/long-open ones.
5. **Shelved work** - `p4 changes -s shelved -u <user>`, if any.
6. **Reconcile drift** - only when `$ARGUMENTS` scopes a subtree: `p4 reconcile -n -m
   <scope>` (or `p4 status <scope>`). Skip a full-workspace drift scan by default - it
   digests every writable file (hundreds of GB on a game workspace); `-m` compares
   modtime instead. Surface out-of-band adds/edits/deletes not yet staged.
7. **Locks by others** - `p4 opened -a <scope>` for files locked/opened by other
   users that could block a submit.

Present a concise summary - what's checked out, what's uncommitted/unreconciled,
what's ready to submit, and anything risky (large binaries open for edit, files
locked by others, stale changelists) - not raw command dumps. For deeper history or
lock analysis, point to `/p4-analyze` and `/p4-locks`.

**Example:** *"What's my workspace state?"* → a snapshot: you're `<user>@<client>` on
P4D `<version>` with a valid ticket; 2 files open in CL `<n>`; no reconcile drift;
nothing locked by others; one shelf from last week. Prose, not raw output.
