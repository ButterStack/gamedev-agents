#!/usr/bin/env bash
#
# Lint every plugin in this marketplace so the agents don't drift out of spec.
#
# Two layers:
#   1. OFFICIAL - `claude plugin validate --strict` on the marketplace manifest and
#      each plugin (JSON schema, hooks.json structure, frontmatter syntax,
#      unrecognized fields). Skipped with a warning if the `claude` CLI is absent.
#   2. PORTABLE - checks the official validator does NOT cover, implemented with jq
#      so they run anywhere: required frontmatter FIELDS, plugin.json `name` == its
#      directory, marketplace <-> plugin.json name agreement, hook `command` scripts
#      exist and are executable, and shellcheck / shebang on shell scripts.
#
# No network, API key, or `claude` login is required. Exit 0 = clean, 1 = failures.
#
# Usage: scripts/lint-plugins.sh

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2   # repo root
ROOT="$PWD"
MKT=".claude-plugin/marketplace.json"

if [ -t 1 ]; then RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; DIM=$'\033[2m'; NC=$'\033[0m'
else RED=; GRN=; YEL=; DIM=; NC=; fi

FAILS=0; WARNS=0
pass()    { printf '  %sok%s   %s\n'   "$GRN" "$NC" "$1"; }
fail()    { printf '  %sFAIL%s %s\n'   "$RED" "$NC" "$1"; FAILS=$((FAILS+1)); }
warn()    { printf '  %swarn%s %s\n'   "$YEL" "$NC" "$1"; WARNS=$((WARNS+1)); }
section() { printf '\n%s== %s ==%s\n' "$DIM" "$1" "$NC"; }

command -v jq >/dev/null 2>&1 || { echo "lint: jq is required" >&2; exit 2; }
[ -f "$MKT" ] || { echo "lint: $MKT not found (run from repo root)" >&2; exit 2; }
jq empty "$MKT" 2>/dev/null || { echo "lint: $MKT is not valid JSON" >&2; exit 2; }

# Plugin directories, from the marketplace's local sources.
# (read-loop, not `mapfile`, so this runs on macOS's stock bash 3.2 too)
PLUGINS=()
while IFS= read -r line; do [ -n "$line" ] && PLUGINS+=("$line"); done \
  < <(jq -r '.plugins[].source | select(type=="string")' "$MKT" | sed 's#^\./##')
[ "${#PLUGINS[@]}" -gt 0 ] || { echo "lint: no local plugins found in $MKT" >&2; exit 2; }

# has_fm_key <file> <key> : 0 found, 1 frontmatter present but key missing, 2 no frontmatter
has_fm_key() {
  awk -v key="$2" '
    NR==1 && $0!="---" { exit 2 }
    NR==1 { next }
    $0=="---" { exit 1 }
    $0 ~ "^"key"[[:space:]]*:" { exit 0 }
  ' "$1"
}

# require_fm <file> <key...> : fail unless every key is present in the frontmatter
require_fm() {
  local f="$1"; shift
  local rel="${f#"$ROOT"/}"
  for key in "$@"; do
    has_fm_key "$f" "$key"; local rc=$?
    if   [ "$rc" = 2 ]; then fail "$rel: no YAML frontmatter block"; return
    elif [ "$rc" = 1 ]; then fail "$rel: frontmatter missing required '$key:'"
    fi
  done
}

###############################################################################
section "Layer 1 - official: claude plugin validate --strict"
###############################################################################
if command -v claude >/dev/null 2>&1; then
  if claude plugin validate . --strict >/tmp/lint-validate.out 2>&1; then
    pass "marketplace manifest"
  else
    fail "marketplace manifest (claude plugin validate . --strict)"
    sed 's/^/      /' /tmp/lint-validate.out
  fi
  for p in "${PLUGINS[@]}"; do
    if claude plugin validate "$p" --strict >/tmp/lint-validate.out 2>&1; then
      pass "$p"
    else
      fail "$p (claude plugin validate $p --strict)"
      sed 's/^/      /' /tmp/lint-validate.out
    fi
  done
else
  warn "claude CLI not installed - skipping official validation (portable checks below still run)"
  warn "install with: npm i -g @anthropic-ai/claude-code"
fi

###############################################################################
section "Layer 2 - marketplace manifest"
###############################################################################
for key in name owner plugins; do
  [ "$(jq -r "has(\"$key\")" "$MKT")" = true ] && pass "marketplace has .$key" \
    || fail "marketplace missing required .$key"
done
# each plugin entry: required fields, local source exists, no path traversal
n=$(jq '.plugins | length' "$MKT")
for i in $(seq 0 $((n-1))); do
  name=$(jq -r ".plugins[$i].name // empty" "$MKT")
  src=$(jq -r ".plugins[$i].source // empty" "$MKT")
  [ -n "$name" ] || fail "plugins[$i] missing .name"
  [ -n "$src" ]  || { fail "plugins[$i] ($name) missing .source"; continue; }
  case "$src" in *..*) fail "plugins[$i] ($name) source contains '..': $src";; esac
  dir="${src#./}"
  [ -d "$dir" ] || fail "plugins[$i] ($name) source dir missing: $dir"
done
# duplicate plugin names
dupes=$(jq -r '.plugins[].name' "$MKT" | sort | uniq -d)
[ -z "$dupes" ] && pass "no duplicate plugin names" || fail "duplicate plugin names: $dupes"

###############################################################################
section "Layer 2 - per plugin (portable checks)"
###############################################################################
for p in "${PLUGINS[@]}"; do
  printf '\n%s%s%s\n' "$DIM" "$p" "$NC"
  pj="$p/.claude-plugin/plugin.json"

  # plugin.json: exists, valid JSON, name present, name == dir, name == marketplace entry
  if [ ! -f "$pj" ]; then fail "$pj missing"; continue; fi
  if ! jq empty "$pj" 2>/dev/null; then fail "$pj invalid JSON"; continue; fi
  pjname=$(jq -r '.name // empty' "$pj")
  [ -n "$pjname" ] && pass "plugin.json has name" || fail "plugin.json missing .name"
  [ "$pjname" = "$(basename "$p")" ] && pass "plugin.json name matches dir" \
    || fail "plugin.json name '$pjname' != dir '$(basename "$p")'"
  mktname=$(jq -r --arg s "./$p" '.plugins[] | select((.source|sub("^\\./";""))==($s|sub("^\\./";""))) | .name' "$MKT")
  [ "$pjname" = "$mktname" ] && pass "plugin.json name matches marketplace entry" \
    || fail "plugin.json name '$pjname' != marketplace entry '$mktname'"

  # agents/skills/commands: required frontmatter fields
  while IFS= read -r f; do require_fm "$f" name description; done \
    < <(find "$p/agents" -name '*.md' 2>/dev/null)
  while IFS= read -r f; do require_fm "$f" name description; done \
    < <(find "$p/skills" -name 'SKILL.md' 2>/dev/null)
  while IFS= read -r f; do require_fm "$f" description; done \
    < <(find "$p/commands" -name '*.md' 2>/dev/null)
  pass "frontmatter fields checked (agents/skills/commands)"

  # hooks.json: valid JSON, and every command-hook .sh reference exists + is executable
  hj="$p/hooks/hooks.json"
  if [ -f "$hj" ]; then
    if ! jq empty "$hj" 2>/dev/null; then fail "$hj invalid JSON"; else
      while IFS= read -r cmd; do
        [ -n "$cmd" ] || continue
        resolved=$(printf '%s' "$cmd" | sed "s#\${CLAUDE_PLUGIN_ROOT}#$p#g" | tr -d '"')
        sh=$(printf '%s' "$resolved" | grep -oE '[^[:space:]]+\.sh' | head -1)
        [ -n "$sh" ] || continue
        if [ ! -f "$sh" ]; then fail "hook script missing: $sh"
        elif [ ! -x "$sh" ]; then fail "hook script not executable (chmod +x): $sh"
        else pass "hook script ok: ${sh#"$p"/}"; fi
      done < <(jq -r '.. | .command? // empty' "$hj")
    fi
  fi

  # scripts/*.sh: shebang + shellcheck (if available)
  while IFS= read -r s; do
    head -1 "$s" | grep -q '^#!' && pass "shebang: ${s#"$p"/}" || fail "missing shebang: $s"
    if command -v shellcheck >/dev/null 2>&1; then
      if shellcheck -S warning "$s" >/tmp/lint-sc.out 2>&1; then pass "shellcheck: ${s#"$p"/}"
      else fail "shellcheck: $s"; sed 's/^/      /' /tmp/lint-sc.out; fi
    fi
  done < <(find "$p/scripts" -name '*.sh' 2>/dev/null)
  command -v shellcheck >/dev/null 2>&1 || warn "shellcheck not installed - skipped shell static analysis for $p"
done

###############################################################################
printf '\n%s========================================%s\n' "$DIM" "$NC"
if [ "$FAILS" -eq 0 ]; then
  printf '%s✔ lint passed%s  (%d warning(s))\n' "$GRN" "$NC" "$WARNS"
  exit 0
else
  printf '%s✘ lint failed: %d error(s), %d warning(s)%s\n' "$RED" "$FAILS" "$WARNS" "$NC"
  exit 1
fi
