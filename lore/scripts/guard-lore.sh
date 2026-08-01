#!/usr/bin/env bash
#
# PreToolUse(Bash) guard - hard block for catastrophic, irreversible Lore VCS
# operations, regardless of global flags (`--repository`, `--identity`, `-f`, ...)
# or how permissions are configured. This is a backstop (same shape as
# guard-p4.sh) so that even a broad `Bash(lore:*)` allowlist cannot let the agent
# run server-side data-destroying commands:
#
#   lore file obliterate   - irreversibly removes fragment payload bytes for all users
#   lore repository delete  - deletes an entire repository
#
# Softer destructive ops (reset, sync --reset, branch reset, revision amend,
# layer remove --purge, push, --force) are gated by the agent's own confirmation
# rules, not here.
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

# Lore commands are `lore [GLOBAL FLAGS] <noun> <verb> ...`. For EVERY `lore`/`.../lore`
# token in the command, extract the first two non-flag tokens after it (the noun and
# verb), skipping global flags and the values of the value-taking ones. Emitting a pair
# per occurrence catches forms like `cd x && lore file obliterate`. Matching the
# noun/verb POSITION (not "anywhere in the string") avoids false positives such as a
# path arg literally named `obliterate`.
pairs="$(printf '%s' "$cmd" | awk '{
  for (p=1;p<=NF;p++) {
    if ($p !~ /(^|\/)lore$/) continue
    noun=""; verb=""
    for (i=p+1;i<=NF;i++) {
      t=$i
      if (t ~ /^-/) {
        # value-taking long flags in "--flag value" form: also skip the value token
        if (t ~ /^--(repository|log-level|identity|max-connections|file-count-limit|file-size-limit|compress-limit|search-limit)$/) i++
        continue
      }
      if (noun=="") { noun=t; continue }
      verb=t; break
    }
    if (noun!="") print noun" "verb
  }
}')"
[ -n "$pairs" ] || exit 0

while IFS= read -r pair; do
  case "$pair" in
    "file obliterate" | "repository delete" | "obliterate"* )
      echo "guard-lore: refusing '${pair% }' - irreversible/server-destructive Lore operations (obliterate, repository delete) are out of scope for this agent. Refer to whoever operates your Lore server." >&2
      exit 2
      ;;
  esac
done <<EOF
$pairs
EOF

exit 0
