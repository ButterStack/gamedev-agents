#!/usr/bin/env bash
#
# PreToolUse(Bash) guard - hard block for catastrophic Perforce admin operations,
# regardless of global flags (`-ztag`, `-p`, `-u`, ...) or how permissions are
# configured. This is a backstop so that even a broad `Bash(p4:*)` allowlist cannot
# let the agent run server-lifecycle / archive / obliterate commands. Softer
# destructive ops (revert, unlock -f, client -d, submit) are gated by the agent's
# own confirmation rules, not here.
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

# Extract the p4 SUBCOMMAND (verb): the first non-flag token after a `p4`/`.../p4`
# token, skipping global flags and the values of value-taking flags. Matching the
# verb position (not "anywhere in the string") avoids false positives like a depot
# path //depot/archive/... being read as the `archive` verb.
verb="$(printf '%s' "$cmd" | awk '{
  s=0
  for (i=1;i<=NF;i++) { if ($i ~ /(^|\/)p4$/) { s=i; break } }
  if (!s) exit
  for (i=s+1;i<=NF;i++) {
    t=$i
    if (t ~ /^-/) { if (t ~ /^-(p|u|c|C|d|H|P|Q|r|v|x|z|F|L|G|I)$/) i++; continue }
    print t; exit
  }
}')"

case "$verb" in
  obliterate|admin|dbverify|dbpack|journalcopy|journaldbchecksums|archive|restore|unload|ldapsync|storage|unsubmit|duplicate|retype)
    echo "guard-p4: refusing '$verb' - server-lifecycle / archive / history-rewriting operations are out of scope for this agent. Refer to the Perforce administrator." >&2
    exit 2
    ;;
esac

exit 0
