#!/usr/bin/env bash
#
# PreToolUse(Bash) guard - hard block for catastrophic filesystem operations against
# a Unity project or Editor install, regardless of how permissions are configured.
# This is a backstop (same shape as guard-unreal.sh / guard-jenkins.sh / guard-p4.sh):
# even a broad Bash allowlist cannot let the agent
#   - rm/mv/overwrite an Assets/, ProjectSettings/, or Packages/ tree (the project
#     itself - belongs to source control, not `rm`/`mv`),
#   - delete any *.meta file (it carries the asset's GUID - a deleted .meta orphans
#     every reference to that asset, anywhere in the tree),
#   - write into or delete from a Unity Editor install tree (Unity Hub's
#     .../Hub/Editor/<version>/..., a macOS Unity.app bundle - a read-only reference).
# Softer gates (build-cost confirmation, --allow-install / --allow-dirty-build,
# license activate/return, editors upgrade, pipeline install, deleting Library/)
# are the agent's own confirmation rules, not this hook. Only destructive
# filesystem verbs are inspected (rm, mv, find -delete / -exec rm, truncating
# redirects, cp/tee into the Editor install tree). Reads, `unity ...` CLI
# invocations, and `rm -rf Library Temp Logs obj Builds` style regenerable
# build-state cleanup pass through untouched. Heredoc bodies are skipped so
# documentation/commit text that *mentions* rm/mv does not false-positive.
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

# Normalize so the token scan sees statement separators and redirects as standalone
# tokens: `&&` `||` `|` `;` `&` -> " ; ", `>`/`>>` -> " > ".
norm="$(printf '%s' "$cmd" | sed -e 's/&&/ ; /g' -e 's/||/ ; /g' -e 's/>>*/ > /g' -e 's/[|;&]/ ; /g')"

reason="$(printf '%s' "$norm" | awk '
  # Classify a (quote-stripped) token as a protected target, or return "".
  function classify(p) {
    if (p ~ /(Unity[\/\\]+Hub[\/\\]+Editor|Unity\.app[\/\\]+Contents)([\/\\]|$)/)
      return "the Unity Editor install tree (read-only reference - never write into or delete from it)"
    if (p ~ /\.meta$/)
      return "a .meta file (it carries the asset GUID - deleting it orphans every reference to the asset)"
    if (p ~ /(^|[\/\\])Assets([\/\\]|$)/)
      return "an Assets/ tree (the project itself - use source control, not rm/mv)"
    if (p ~ /(^|[\/\\])ProjectSettings([\/\\]|$)/)
      return "a ProjectSettings/ tree (project identity/config - use source control, not rm/mv)"
    if (p ~ /(^|[\/\\])Packages([\/\\]|$)/)
      return "a Packages/ tree (manifest.json + packages-lock.json - use source control, not rm/mv)"
    return ""
  }
  # End of a statement scope: evaluate a pending cp destination (last arg), reset.
  function end_scope(   c) {
    if (verb == "cp" && cp_last != "") {
      c = classify(cp_last)
      if (index(c, "Editor install") > 0 && reason == "") reason = "cp into " c ": " cp_last
    }
    verb = ""; redirect = 0; find_prot = ""; find_exec = 0; cp_last = ""
  }
  {
    line = $0
    gsub(/<<</, " __HERESTRING__ ", line)   # do not mistake here-strings for heredocs
    # Skip heredoc bodies until the terminator line.
    if (hd != "") { s = line; gsub(/^[ \t]+|[ \t]+$/, "", s); if (s == hd) hd = ""; next }
    if (match(line, /<<-?[ \t]*['\''"]?[A-Za-z_][A-Za-z0-9_]*/)) {
      m = substr(line, RSTART, RLENGTH)
      sub(/^<<-?[ \t]*['\''"]?/, "", m)
      hd = m
    }
    n = split(line, t, /[ \t]+/)
    end_scope()
    for (i = 1; i <= n; i++) {
      tok = t[i]
      gsub(/^['\''"]+/, "", tok); gsub(/['\''"]+$/, "", tok)
      if (tok == "") continue
      if (tok == ";") { end_scope(); continue }
      if (tok == ">") { redirect = 1; continue }
      if (redirect) {
        redirect = 0
        c = classify(tok)
        if (c != "" && reason == "") reason = "truncating redirect onto " c ": > " tok
        continue
      }
      if (verb == "") {
        if (tok ~ /^[A-Za-z_][A-Za-z0-9_]*=/) continue                 # VAR=val prefix
        if (tok ~ /^(sudo|env|command|nohup|nice|time|xargs|exec)$/) continue
        if (tok ~ /(^|\/)rm$/)   { verb = "rm";   continue }
        if (tok ~ /(^|\/)mv$/)   { verb = "mv";   continue }
        if (tok ~ /(^|\/)find$/) { verb = "find"; continue }
        if (tok ~ /(^|\/)cp$/)   { verb = "cp";   continue }
        if (tok ~ /(^|\/)tee$/)  { verb = "tee";  continue }
        verb = "other"; continue                                       # benign command: skip its args
      }
      if (verb == "other") continue
      if (verb == "rm" || verb == "mv" || verb == "tee") {
        if (tok ~ /^-/) continue
        c = classify(tok)
        if (c != "" && reason == "") reason = verb " targeting " c ": " tok
        continue
      }
      if (verb == "cp") { if (tok !~ /^-/) cp_last = tok; continue }
      if (verb == "find") {
        if (tok == "-delete") { if (find_prot != "" && reason == "") reason = "find -delete on " find_prot; continue }
        if (tok == "-exec" || tok == "-execdir" || tok == "-ok" || tok == "-okdir") { find_exec = 1; continue }
        if (find_exec) {
          if (tok ~ /(^|\/)(rm|unlink|shred)$/ && find_prot != "" && reason == "") reason = "find -exec " tok " on " find_prot
          find_exec = 0
          continue
        }
        if (tok ~ /^-/) continue
        c = classify(tok)
        if (c != "" && find_prot == "") find_prot = c
        continue
      }
    }
    end_scope()
  }
  END { if (reason != "") print reason }
')"

if [ -n "$reason" ]; then
  echo "guard-unity: refusing - $reason. Protected: Assets/, ProjectSettings/, and Packages/ trees, *.meta files, and the Unity Editor install (.../Hub/Editor/<version>, Unity.app). Regenerable build-state cleanup (Library/, Temp/, Logs/, obj/, Builds/) is allowed." >&2
  exit 2
fi

exit 0
