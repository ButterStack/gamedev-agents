#!/usr/bin/env bash
#
# WorktreeCreate hook - set up an isolated Perforce client for a Claude Code worktree.
#
# Claude Code has native worktree isolation for git; for Perforce it delegates here.
# When Claude creates a worktree, this provisions a dedicated p4 client rooted at the
# worktree dir AND binds the worktree to it (via a .p4config) so `p4` run inside the
# worktree uses that client - not the user's main workspace.
#
# stdin : JSON { "worktree_name", "worktree_path", "git_ref", ... }
# stdout: the worktree path on a single line (REQUIRED).
# exit  : 0 = success (Claude uses the stdout path). Non-zero BLOCKS creation.
#
# Best-effort: if p4 is unavailable/unreachable or no real client is in context, the
# worktree still succeeds as a plain directory rather than blocking creation.

set -uo pipefail

input="$(cat)"

# Extract a top-level string field from the JSON (prefer jq; sed fallback - no hard
# jq dependency).
jval() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r --arg k "$key" '.[$k] // empty'
  else
    printf '%s' "$input" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
  fi
}

name="$(jval worktree_name)"
path="$(jval worktree_path)"

[ -n "$path" ] || { echo "worktree-create: no worktree_path in hook input" >&2; exit 1; }
mkdir -p "$path" || { echo "worktree-create: cannot create directory $path" >&2; exit 1; }

# Deterministic, collision-resistant client name. Client names are a SERVER-WIDE
# namespace, so scope by OS user + host + worktree (reproduced identically in
# worktree-remove.sh). Never derive from worktree name alone.
sanitize() { printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'; }
osuser="$(id -un 2>/dev/null || echo user)"
host="$(hostname -s 2>/dev/null || echo host)"
new="claude_wt_$(sanitize "$osuser")_$(sanitize "$host")_$(sanitize "$name")"

# Bounded p4 probe so a hung/unreachable server can't hang the hook past its timeout
# (which would BLOCK worktree creation - the opposite of degrade-gracefully).
p4probe() { if command -v timeout >/dev/null 2>&1; then timeout 8 "$@"; else "$@"; fi; }

# An existing client has an `Update` field; a nonexistent name yields a broad default
# TEMPLATE (Root=cwd, all-depots view) that must NEVER be saved as a real client.
client_exists() { p4 -ztag client -o "$1" 2>/dev/null | grep -q '^\.\.\. Update '; }

isolate() {
  command -v p4 >/dev/null 2>&1 || { echo "worktree-create: p4 not on PATH; plain dir" >&2; return; }
  p4probe p4 info >/dev/null 2>&1 || { echo "worktree-create: p4 server unreachable; plain dir" >&2; return; }

  if client_exists "$new"; then
    echo "worktree-create: reusing existing client $new" >&2
  else
    base="$(p4 -ztag -F %clientName% info 2>/dev/null || true)"
    if [ -z "$base" ] || ! client_exists "$base"; then
      echo "worktree-create: no existing client in context; skipping p4 isolation (plain dir)" >&2
      return
    fi
    # Derive from the current client so the View maps correctly. Blank Host (don't pin
    # to a machine), and strip AltRoots/ServerID (a copied AltRoot can resolve back to
    # the MAIN workspace and clobber it; a ServerID pins to an edge).
    if ! p4 client -o "$base" \
        | awk -v c="$new" -v r="$path" -v b="$base" '
            /^Client:/   { print "Client:\t" c; next }
            /^Root:/     { print "Root:\t" r; next }
            /^Host:/     { print "Host:"; next }
            /^AltRoots:/ { next }
            /^ServerID:/ { next }
            { gsub("//" b "/", "//" c "/"); print }' \
        | p4 client -i >&2; then
      echo "worktree-create: p4 client create failed; plain dir" >&2
      return
    fi
    echo "worktree-create: provisioned client $new (Root=$path)" >&2
  fi

  # Bind the worktree to the client so p4 run inside it uses THIS client.
  printf 'P4CLIENT=%s\n' "$new" > "$path/.p4config"
  if ! p4 set P4CONFIG 2>/dev/null | grep -q '='; then
    echo "worktree-create: NOTE isolation needs P4CONFIG set (e.g. 'p4 set P4CONFIG=.p4config'); wrote $path/.p4config" >&2
  fi
  echo "worktree-create: WARNING client $new has an EMPTY have-list; a bare 'p4 sync' will transfer the entire client view. Sync only the subtree you need." >&2
}

isolate

# Required: emit the worktree path for Claude Code.
echo "$path"
