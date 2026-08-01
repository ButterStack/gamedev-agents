#!/usr/bin/env bash
#
# WorktreeCreate hook: provision an isolated Lore instance for a Claude Code worktree.
#
# Claude Code has native worktree isolation for git; for Lore (Epic Games' VCS) it
# delegates here. When Claude creates a worktree, this clones the SAME remote repo the
# current directory is checked out from into the worktree path, using Lore's shared
# store (`--use-shared-store`) so fragment payloads dedup across worktrees on this
# machine instead of being fetched and stored once per worktree; each worktree still
# gets its own independent working tree, staged state, and branch.
#
# stdin : JSON { "worktree_name", "worktree_path", ... }
# stdout: the worktree path on a single line (REQUIRED).
# exit  : 0 = success (Claude uses the stdout path). Non-zero BLOCKS creation.
#
# Best-effort: if `lore` is unavailable/unreachable, or the current directory isn't a
# Lore repo, the worktree still succeeds as a plain directory rather than blocking
# creation.

set -uo pipefail

input="$(cat)"

# Extract a top-level string field from the JSON (prefer jq; sed fallback, no hard
# jq dependency).
jval() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r --arg k "$key" '.[$k] // empty'
  else
    printf '%s' "$input" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
  fi
}

path="$(jval worktree_path)"

[ -n "$path" ] || { echo "worktree-create: no worktree_path in hook input" >&2; exit 1; }
mkdir -p "$path" || { echo "worktree-create: cannot create directory $path" >&2; exit 1; }

# Bounded lore probe so a hung/unreachable server can't hang the hook past its timeout
# (which would BLOCK worktree creation, the opposite of degrade-gracefully).
loreprobe() { if command -v timeout >/dev/null 2>&1; then timeout 20 "$@"; else "$@"; fi; }

isolate() {
  command -v lore >/dev/null 2>&1 || { echo "worktree-create: lore not on PATH; plain dir" >&2; return; }

  # Resolve the CURRENT repo from ambient cwd, same spirit as p4's ambient client
  # context. Deliberately NOT `--repository "$PWD"`: that flag requires an EXACT repo
  # root and, unlike bare cwd resolution, does not walk up from a subdirectory.
  remote_url="$(lore repository config get remote_url 2>/dev/null)"
  if [ -z "$remote_url" ]; then
    echo "worktree-create: not inside a Lore repo (no remote_url); plain dir" >&2
    return
  fi

  # No config key exposes the repo name directly (only remote_url/identity/store keys
  # resolve); `lore repository info`'s first line is "<name> (<id>)" so parse that.
  # Bail to a plain dir rather than guess if it doesn't look right.
  info_line="$(loreprobe lore repository info 2>/dev/null | head -1)"
  repo_name="${info_line% (*}"
  if [ -z "$repo_name" ] || [ "$repo_name" = "$info_line" ]; then
    echo "worktree-create: could not determine repository name from 'lore repository info'; plain dir" >&2
    return
  fi

  clone_url="${remote_url%/}/${repo_name}"
  identity="$(lore repository config get identity 2>/dev/null)"

  # `--use-shared-store` (no explicit --shared-store-path) self-provisions Lore's
  # default per-remote shared store on first use and reuses it thereafter; no need
  # to pre-run `lore shared-store create` (which errors if the path already exists).
  set -- clone "$clone_url" "$path" --use-shared-store --non-interactive
  [ -n "$identity" ] && set -- "$@" --identity "$identity"

  if loreprobe lore "$@" >&2; then
    echo "worktree-create: cloned $clone_url into $path (shared store)" >&2
  else
    echo "worktree-create: lore clone failed; plain dir" >&2
  fi
}

isolate

# Required: emit the worktree path for Claude Code.
echo "$path"
