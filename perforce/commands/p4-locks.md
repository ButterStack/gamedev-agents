---
description: Report Perforce exclusive-lock (+l) contention - who holds locks, on which assets, and what's blocked
argument-hint: "[depot-subtree]"
---

Report exclusive-lock (`+l`) contention for the user, scoped to `$ARGUMENTS` if
given (else the asset trees, e.g. `//<depot>/...`). Read-only - surface the
situation; do not release any lock here. Use the `p4-observe` skill (§3) for exact
command forms.

Do:

1. **Find everything open/locked across all users** - `p4 opened -a -m 200 <scope>`
   (on an **edge** server also `p4 opened -x <scope>`, since `opened -a` is edge-local).
2. **Get lock detail** - `p4 -ztag fstat <scope>/<asset>`; `otherOpen`/`otherLock`
   (naming the holding `user@client`) show by default (no `-O` flag needed). Confirm
   `headType` is `+l`/binary.
3. **Report contention** - for each locked asset, state plainly: *"`<asset>` is
   exclusively locked by `<user>@<client>`."* Highlight assets locked by others that
   block the current user, and any that look long-held.

Explain, when relevant, why this matters: binary/asset files are `+l` because they
can't be merged, so only one editor at a time - a stale lock blocks teammates. The
holder must `submit`, `revert`, or `unlock` to release it; the user should ask them.

If the user then wants to **release** a lock, hand off to `p4-workflows` §7. Be
precise: `p4 unlock -f` does **not** clear a `+l` exclusive open. An admin clears it by
reverting the holder's open (`p4 revert -C <their_client> <file>`), or `p4 unlock -x`
for a lock orphaned by a dead edge/client. Releasing never destroys their local file -
they lose the exclusive right to submit. Needs admin rights + explicit confirmation.

**Example:** *"Who's got Hero.uasset locked?"* → *"Hero.uasset is exclusively locked
by `alice@art_ws` (binary+l)."* Suggest asking alice to submit/revert; admin release
(`p4 revert -C alice_ws //.../Hero.uasset`) only as a last resort.
