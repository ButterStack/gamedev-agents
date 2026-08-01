#!/usr/bin/env bash
#
# WorktreeRemove hook: tear down the isolated Lore instance for a worktree.
#
# Fires when Claude Code cleans up a worktree (session exit / subagent finish /
# manual cleanup). Cleans up after the dedicated Lore checkout worktree-create.sh
# provisioned: opportunistically prunes stale entries from the shared store's
# instance registry, then removes this worktree's own `.lore` metadata so a leftover
# directory is never mistaken for a live Lore checkout.
#
# stdin : JSON { "worktree_name", "worktree_path", ... }
# exit  : 0 (ignored by Claude Code, cleanup proceeds regardless).
#
# NOTE: `lore repository instance prune` only recognizes a worktree's registry entry
# as stale once its DIRECTORY is gone (removing just `.lore` is not enough, verified
# empirically), and a repository can't prune its own entry while it's still a valid
# `--repository` target. So THIS worktree's entry is swept opportunistically by a
# LATER prune (from any sibling worktree on the same shared store) after Claude Code
# removes the directory itself. Same best-effort, may-lag-a-crash story as
# perforce's claude_wt_* client leak. Admin janitor: run
# `lore repository instance prune --repository <any-live-clone-on-that-store>` to
# force a sweep.

set -uo pipefail

input="$(cat)"

jval() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r --arg k "$key" '.[$k] // empty'
  else
    printf '%s' "$input" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
  fi
}

path="$(jval worktree_path)"

command -v lore >/dev/null 2>&1 || exit 0
[ -n "$path" ] || exit 0
[ -d "$path/.lore" ] || { echo "worktree-remove: no .lore at $path; nothing to clean up" >&2; exit 0; }

loreprobe() { if command -v timeout >/dev/null 2>&1; then timeout 20 "$@"; else "$@"; fi; }

# Opportunistic janitor: sweep any ALREADY-stale sibling entries on this worktree's
# shared store while $path is still a valid --repository target. Must run BEFORE
# removing .lore below; once that's gone, $path is no longer a valid repository.
loreprobe lore repository instance prune --repository "$path" >&2 \
  || echo "worktree-remove: 'lore repository instance prune' failed (non-fatal)" >&2

# Metadata only, never touch the worktree's actual files, matching guard-p4's
# philosophy of leaving user content alone. Claude Code owns deleting the worktree
# directory itself; this just stops a leftover dir from looking like a live checkout.
rm -rf "$path/.lore"
echo "worktree-remove: removed .lore at $path" >&2

exit 0
