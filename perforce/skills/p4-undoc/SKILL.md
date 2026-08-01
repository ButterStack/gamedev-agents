---
name: p4-undoc
description: >
  Advanced / undocumented p4 flags for cleaner scripting, parsing, and safe
  self-throttling - plus the list of undocumented commands to NEVER run. Internal
  power-user knowledge for the perforce agent; load it when you need custom output
  formatting, exact error codes, server-side revision slicing, or batching. Not
  user-facing - don't surface these in help text or docs unless asked.
---

# P4 undocumented / advanced flags

These come from `p4 help undoc` and are verified against P4D 2026.1. They are
supported but not in the normal docs - use them for your own scripting; don't
advertise them. All flags below are **read-only/formatting** unless noted.

## Custom output & error identity

- **`-F "<format>"` - override message formatting for clean scripting.** Two
  dictionaries: bare `-F` uses the message dict (values may carry prefixes, e.g.
  `%change%` → `Change 8708`); **`-Ztag -F`** uses the tagged dict with raw values
  and extra fields.
  ```sh
  p4 -F '%fileSize% %depotFile%' sizes //<depot>/....fbx | sort -n | tail -3   # bloat, no awk
  p4 -Ztag -F %change% changes -m1                                             # → 8708 (raw)
  p4 -Ztag -F '%time%|%change%|%user%' changes -s submitted -m 200 //<depot>/...
  ```
  Multi-line fields (`%desc%`) break line parsing - prefer `-ztag -Mj` when a field
  can be multi-line.
- **`-e <cmd>` - dump the message dictionary** (fmt strings, variable names, and the
  stable numeric `code`/`uniq`/`sev`). Use it to discover the variable names for `-F`,
  and to branch error handling on the exact error *code* instead of English text:
  ```sh
  p4 -e sizes //<depot>/x.fbx     # shows fmt0 %depotFile%%depotRev% %fileSize% bytes ...
  p4 -e files //nonexistent/...   # error → code0 ... sev 3 uniq 6244  (match the code, not the string)
  ```
- **`-ztag -Mj` - line-delimited JSON** (already the agent's default for structured
  reads). One object per line, `jq`-ready; the right choice when a field may be
  multi-line. (`-G`/`-R` give Python/Ruby marshal dicts.)
- **`-s`** prefixes every line `info:`/`error:`/`exit:` - lets you read the exit
  status in-stream.

## Server-side slicing (skip client-side filtering)

- **Relative revisions** `@<`, `@<=`, `@>`, `@>=`, `@=` (max 4 specs; quote for the
  shell): `p4 changes '//<depot>/...@>8690,@<=8700'` returns only that window.
- **Action revspecs** `#add #edit #delete #branch #integrate #import`:
  `p4 files '//<depot>/...#delete'` lists only deletions.

## Safe self-throttling & batching (great server etiquette)

- **`-zmaxScanRows=N` / `-zmaxResults=N` / `-zmaxLockTime=N`** - *lower* your own
  limits so a mistyped wildcard fails fast (`Request too large`) instead of
  table-scanning a production server. Prefix exploratory wide queries with these.
  (Never *raise* them as super to defeat admin caps.)
- **`-x <file> run`** - run many commands over ONE connection:
  `printf 'describe -s 8701\ndescribe -s 8702\n' | p4 -x - run`. Only put read-only
  commands in the file - it will run writes too.
- **`-E P4VAR=value`** - override any config var for one command (cleaner than
  mutating the environment): `p4 -E P4CLIENT=other info`.
- **`--explain`** - per-command flag self-documentation: `p4 changes --explain`.

## Diagnostics (read-only)

- `p4 -F` companions: `p4 fstat -Oc <file>` → `lbrFile` (physical archive path);
  `p4 fstat -Dx '//<depot>/*'` → files **and** subdirs in one call.
- `p4 configure show env` / `p4 configure show undoc` (super) - how the server was
  launched and its tunables. Read-only; **never `configure set`** an undoc tunable.
- `p4 filelog -1 <file>` - do NOT follow renames (anchor history to the literal path).

## NEVER run these (from `p4 help undoc`)

Server/DB/archive mutation - categorically out of scope; refer to the admin. The
bundled `guard-p4` hook also hard-blocks most of them:

- `p4 admin dump` / `p4 admin import` - read-locks / rewrites the live DB.
- `p4 storage -R|-r|-s`, `p4 dbpack` - rebuild/lock storage & index tables
  ("only after discussion with Perforce Support").
- `p4 obliterate -i/-I`, `p4 unsubmit`, `p4 duplicate`, `p4 retype`, `p4 snap` -
  history/archive rewriting.
- `p4 submit --forcenoretransfer` - commits archive content with **no digest**; can
  silently commit content differing from the client. Never.
- `p4 configure set <undoc tunable>`, `p4 index` - expert/support-only.
- Raising `-zmaxResults`/`-zmaxScanRows`/`-zmaxLockTime` to bypass admin limits.
