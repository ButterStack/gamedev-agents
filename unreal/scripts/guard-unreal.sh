#!/usr/bin/env bash
#
# PreToolUse(Bash) guard - hard block for catastrophic filesystem operations against
# an Unreal project or engine install, regardless of how permissions are configured.
# This is a backstop (same shape as guard-p4.sh / guard-jenkins.sh): even a broad
# Bash allowlist cannot let the agent
#   - rm/mv/overwrite a Content/ or Source/ tree or a *.uproject file
#     (assets and code belong to Perforce: `p4 delete` / `p4 move`, not `rm`),
#   - write into or delete from an engine install tree (.../UE_5.x/Engine/...,
#     .../UnrealEngine/Engine/... - a read-only reference),
#   - wipe a shared/network DerivedDataCache (other machines depend on it; wiping a
#     LOCAL DDC is allowed - it only costs a re-cook).
# Softer gates (build-cost confirmation, editor-must-be-closed, p4 checkout before
# modifying a binary asset, one-way engine-version upgrades) are the agent's own
# confirmation rules, not this hook. Only destructive filesystem verbs are inspected
# (rm, mv, find -delete / -exec rm, truncating redirects, cp/tee into the engine
# tree). Reads, p4 commands, RunUAT/UBT/UnrealEditor invocations, and
# `rm -rf Saved Intermediate` style build-output cleanup pass through untouched.
# Heredoc bodies are skipped so documentation/commit text that *mentions* rm/mv
# does not false-positive.
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
    if (p ~ /(UE_[0-9][0-9.]*|\$[{]?UE_ROOT[}]?|\$[{]?UE_INSTALL[A-Z_]*[}]?|UnrealEngine)[\/\\]+Engine([\/\\]|$)/)
      return "the engine install tree (read-only reference - never write into or delete from it)"
    if (p ~ /\.uproject$/)
      return "a .uproject file (project identity - deleting/overwriting it orphans the project)"
    if (p ~ /(^|[\/\\])Content([\/\\]|$)/)
      return "a Content/ tree (binary assets belong to Perforce - use p4 delete / p4 move)"
    if (p ~ /(^|[\/\\])Source([\/\\]|$)/)
      return "a Source/ tree (code belongs to Perforce - use p4 delete / p4 move)"
    if ((p ~ /DerivedDataCache/ || p ~ /(^|[\/\\])DDC([\/\\]|$)/) && (p ~ /^\\\\/ || p ~ /^\/\// || p ~ /[Ss]hared/))
      return "a shared/network DerivedDataCache (other machines depend on it; wipe only a LOCAL DDC)"
    return ""
  }
  # End of a statement scope: evaluate a pending cp destination (last arg), reset.
  function end_scope(   c) {
    if (verb == "cp" && cp_last != "") {
      c = classify(cp_last)
      if (index(c, "engine install") > 0 && reason == "") reason = "cp into " c ": " cp_last
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
  echo "guard-unreal: refusing - $reason. Protected: Content/ and Source/ trees, *.uproject files, the engine install (UE_*/Engine), and shared/network DDCs. Build-output cleanup (Saved/, Intermediate/, Binaries/, a LOCAL DerivedDataCache/) is allowed." >&2
  exit 2
fi

exit 0
