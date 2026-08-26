#!/usr/bin/env bash
#
# PreToolUse(Bash) guard - hard block for catastrophic filesystem operations against
# a Godot project, regardless of how permissions are configured. Backstop in the same
# shape as guard-unity.sh / guard-unreal.sh: even a broad Bash allowlist cannot let
# the agent
#   - rm/mv project.godot or export_presets.cfg (the project's identity and its
#     packing contract - source-controlled, not `rm` material),
#   - delete a *.import sidecar (Godot's analog of Unity's .meta: it carries the
#     asset's import settings and UID mapping, and a `git rm -f '*.wav'` glob does
#     NOT match the matching '*.wav.import', which is exactly how orphaned sidecars
#     get committed),
#   - run `git clean -f` unscoped, which deletes tracked content alongside the
#     regenerable .uid/.import sidecars it is usually aimed at,
#   - write into or delete from a Godot engine install tree (a read-only reference).
# `rm -rf .godot` is explicitly ALLOWED: that cache is regenerable by
# `godot --headless --import` and clearing it is a legitimate fix for a stale
# class cache. Reads and `godot ...` invocations pass through untouched. Heredoc
# bodies are skipped so documentation that merely mentions rm/mv does not
# false-positive.
#
# stdin : PreToolUse JSON { "tool_name": "Bash", "tool_input": { "command": "..." } }
# exit  : 0 = allow; 2 = BLOCK (stderr is shown to the model).

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
else
  cmd="$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)"[[:space:]]*}.*/\1/p')"
fi

[ -n "$cmd" ] || exit 0

# Strip heredoc bodies: prose that mentions rm/mv must not trip the guard.
scan="$(printf '%s\n' "$cmd" | awk '
  /<<-?[[:space:]]*'"'"'?[A-Za-z_][A-Za-z0-9_]*'"'"'?/ { inhd=1; print; next }
  inhd { if ($0 ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*$/) inhd=0; next }
  { print }
')"

block() {
  printf 'BLOCKED by guard-godot: %s\n' "$1" >&2
  printf 'This is a hard backstop, not a permissions prompt. If you genuinely need it, ask the user to run it themselves.\n' >&2
  exit 2
}

# Only destructive verbs are inspected at all.
printf '%s' "$scan" | grep -qE '(^|[;&|[:space:]])(rm|mv|shred|truncate)([[:space:]]|$)|(^|[;&|[:space:]])git[[:space:]]+(clean|rm)([[:space:]]|$)|(^|[;&|[:space:]])find[[:space:]].*(-delete|-exec[[:space:]]+rm)' || exit 0

# 1. The project's identity and packing contract.
printf '%s' "$scan" | grep -qE '(rm|mv|shred)([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^;&|]*\b(project\.godot|export_presets\.cfg)\b' \
  && block "refusing to remove or move project.godot / export_presets.cfg - these are source-controlled project identity, not disposable files."

# 2. .import sidecars - Godot's .meta analog.
printf '%s' "$scan" | grep -qE '(rm|shred)([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^;&|]*\.import\b' \
  && block "refusing to delete a .import sidecar - it carries the asset's import settings and UID. Deleting it orphans references. If you are removing an asset, remove BOTH the asset and its .import together (a '*.wav' glob does not match '*.wav.import')."
printf '%s' "$scan" | grep -qE 'git[[:space:]]+rm([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^;&|]*\.import\b' \
  && block "refusing 'git rm' on a .import sidecar on its own - remove the asset and its sidecar together, or you will commit an orphan."

# 3. Unscoped `git clean -f` - deletes tracked content, not just regenerable sidecars.
if printf '%s' "$scan" | grep -qE 'git[[:space:]]+clean[[:space:]]+(-[a-zA-Z]*f[a-zA-Z]*)' \
   && ! printf '%s' "$scan" | grep -qE 'git[[:space:]]+clean[^;&|]*--[[:space:]]+'; then
  block "refusing an unscoped 'git clean -f'. Scope it to the regenerable sidecars and verify none are tracked first: git ls-files -- '*.uid' '*.import' && git clean -f -- '*.uid' '*.import'"
fi

# 4. The engine install tree is a read-only reference.
printf '%s' "$scan" | grep -qE '(rm|mv|shred|truncate)([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^;&|]*(/Godot\.app/|/godot[-_][0-9]|/usr/local/bin/godot\b)' \
  && block "refusing to modify or delete a Godot engine install. Treat the engine as a read-only reference."

exit 0
