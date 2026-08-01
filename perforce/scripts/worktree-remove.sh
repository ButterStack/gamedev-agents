#!/usr/bin/env bash
#
# WorktreeRemove hook - tear down the isolated Perforce client for a worktree.
#
# Fires when Claude Code cleans up a worktree (session exit / subagent finish /
# manual cleanup). Deletes the dedicated p4 client from worktree-create.sh WITHOUT
# losing work: `p4 client -d` refuses a client that has opened files or shelves, so
# we revert opens (metadata only - the worktree files are being removed anyway) and
# delete empty pending changelists, but LEAVE the client intact if it holds shelved
# work rather than destroy it.
#
# stdin : JSON { "worktree_name", "worktree_path", ... }
# exit  : 0 (ignored by Claude Code - cleanup proceeds regardless).
#
# NOTE: on a crash / kill -9 / lid-close this hook may never fire, leaking a
# claude_wt_* client. Admin janitor: `p4 clients -e 'claude_wt_*'` then review
# `Access:` dates and `p4 client -d` the stale ones.

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

name="$(jval worktree_name)"
command -v p4 >/dev/null 2>&1 || exit 0
[ -n "$name" ] || exit 0

# Same deterministic derivation as worktree-create.sh.
sanitize() { printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'; }
osuser="$(id -un 2>/dev/null || echo user)"
host="$(hostname -s 2>/dev/null || echo host)"
new="claude_wt_$(sanitize "$osuser")_$(sanitize "$host")_$(sanitize "$name")"

p4probe() { if command -v timeout >/dev/null 2>&1; then timeout 8 "$@"; else "$@"; fi; }

# Only touch our own client, and only if it actually exists.
p4 -ztag client -o "$new" 2>/dev/null | grep -q '^\.\.\. Update ' \
  || { echo "worktree-remove: no client $new to remove" >&2; exit 0; }

# Never auto-destroy shelved work: leave the client and tell the user how to recover.
if [ -n "$(p4probe p4 changes -s shelved -c "$new" -m 1 2>/dev/null)" ]; then
  echo "worktree-remove: client $new has SHELVED changes - leaving it intact to avoid data loss. Recover them, then: p4 client -d $new" >&2
  exit 0
fi

# Revert any opens (metadata only; worktree files are being removed anyway).
if [ -n "$(p4 -c "$new" opened -m 1 2>/dev/null)" ]; then
  p4 -c "$new" revert -k //... >/dev/null 2>&1 || true
fi

# Delete now-empty pending changelists owned by this client.
p4 changes -s pending -c "$new" 2>/dev/null | awk '{print $2}' | while read -r cl; do
  [ -n "$cl" ] && p4 change -d "$cl" >/dev/null 2>&1 || true
done

if p4 client -d "$new" >/dev/null 2>&1; then
  echo "worktree-remove: deleted client $new" >&2
else
  echo "worktree-remove: could NOT delete client $new - left intact (check 'p4 opened -a -C $new')" >&2
fi

exit 0
