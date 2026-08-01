---
description: Analyze Perforce depot activity - changelist velocity, contributors, CI-trigger health, hot paths, and large-binary bloat
argument-hint: "[depot-subtree]"
---

Produce a read-only analysis of the Perforce (Helix Core) system for the user,
scoped to `$ARGUMENTS` if given (else a sensible default depot/subtree). Run only
read-only commands. Use the `p4-observe` skill for exact command forms - especially
`p4 -ztag -Mj <cmd>` for parseable JSON (never `-Mj` alone; never `-ztag describe`
for full descriptions).

Analyze and report:

1. **Changelist velocity** - pull recent submitted changes
   (`p4 -ztag -Mj changes -s submitted -m <N> <scope>`), parse `time` (Unix), and
   summarize submissions per day/week and active vs quiet periods.
2. **Contributors & hot paths** - group by `user`/`client` and by top-level depot
   directory (`path`) to show who's active and where change concentrates
   (art vs code vs audio).
3. **CI-trigger health** - count description tags the studio uses (`#ci`, `#build`,
   `#jenkins`, `#approval`, `[ci]`, `#jenkins:<Job>`). Correlate with the
   `change-commit` triggers from `p4 triggers -o` (**super-only** - if you lack access,
   do the tag analysis alone and say the trigger table was unavailable). Call out a drop
   in CI tags on trigger-covered paths - since triggers exit 0 even when the downstream
   endpoint fails, a silent CI outage shows up here before anywhere else.
4. **Large-binary / bloat** - `p4 sizes -s <scope>` for totals, then biggest files
   and a breakdown by asset type (`.png`/`.fbx`/`.wav`/`.uasset`). Flag anything that
   looks like build output/cache that shouldn't be versioned (cross-ref P4IGNORE
   presets in `p4-workflows`).

Cap history scans with `-m <N>` and scope to a subtree - full history on a busy
depot is huge. Present findings as a tight briefing with concrete numbers and named
files/users, not raw dumps. If the analysis surfaces action (bloat to remove, a
typemap to add, a broken CI bridge), name it and hand off to `p4-workflows` - do not
mutate anything here.

**Example:** *"How active is the depot this month?"* → submits/day and trend, top
contributors, CI-tag health vs the `change-commit` triggers, total size + biggest
asset types, and any suspected build-output leakage - with concrete numbers.
