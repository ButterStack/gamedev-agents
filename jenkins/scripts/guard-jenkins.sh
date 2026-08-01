#!/usr/bin/env bash
#
# PreToolUse(Bash) guard - hard block for the Jenkins Script Console (Groovy RCE),
# regardless of how permissions are configured. This is a backstop so that even a
# broad `Bash(curl:*)` / `Bash(jenkins-cli:*)` allowlist cannot let the agent
# execute arbitrary Groovy on a Jenkins controller. Softer destructive ops (job
# delete, config.xml PUT, aborting another user's build, ...) are gated by the
# agent's own confirmation rules, not here.
#
# Blocks:
#   1. Any URL/path whose FINAL path segment is exactly `script` or `scriptText`
#      (case-insensitive) - the Script Console and its text variant, whether at
#      the Jenkins root (`/script`), under the newer `/manage/` prefix
#      (`/manage/script`), or per-node (`/computer/<name>/script`). Deliberately
#      excludes a path where that segment is immediately preceded by `/job/<name>/`
#      - a job can legitimately be named "script" (`/job/script/api/json`,
#      `/job/script/build`, `/job/script/config.xml`, even `/job/script` itself),
#      and none of those are the Script Console. Only tokens containing `/script`
#      as a substring are examined at all, so an unrelated bare word/filename like
#      `script.sh` or a job named `scripts` (no exact `/script` segment) never
#      reaches this check.
#   2. A `jenkins-cli`/`jenkins-cli.jar` invocation whose VERB (the first
#      non-flag argument, after skipping global options like `-s`/`-auth`/`-i`)
#      is `groovy` or `groovysh`. Verb-position matching means a job merely named
#      "groovy" (e.g. `jenkins-cli.jar get-job groovy`) is not blocked - only the
#      actual Groovy-eval subcommands are.
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

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Disable pathname expansion for the unquoted word-splitting loops below - command
# text routinely contains `?`/`*` (query strings, wildcards) that must be treated
# as literal characters, not filesystem globs.
set -f

# --- Check 1: Script Console / scriptText endpoint, by final path segment ---
for tok in $cmd; do
  # Cheap pre-filter: only a token containing "/script" (slash immediately before
  # "script") can possibly be the console - this also matches "/scriptText" since
  # it starts with "script". Excludes bare words/filenames with no leading slash
  # (e.g. `script.sh`, a job named `scripts` with no trailing "/script" segment).
  case "$(lower "$tok")" in
    */script*) ;;
    *) continue ;;
  esac

  # Strip one layer of wrapping quotes, then query string / fragment, then a
  # trailing slash, so "$JENKINS_URL/script?foo=1"'  ->  $JENKINS_URL/script.
  clean="${tok%\"}"; clean="${clean#\"}"
  clean="${clean%\'}"; clean="${clean#\'}"
  clean="${clean%%\?*}"
  clean="${clean%%#*}"
  clean="${clean%/}"

  last="$(lower "${clean##*/}")"
  case "$last" in
    script | scripttext) ;;
    *) continue ;;
  esac

  rest="${clean%/*}"
  prev="$(lower "${rest##*/}")"

  if [ "$prev" != "job" ]; then
    echo "guard-jenkins: refusing - '$tok' targets the Jenkins Script Console (/script or /scriptText). Evaluating Groovy on the controller is arbitrary remote code execution and is out of scope for this agent - use a REST/CLI read equivalent instead (api/json, console, who-am-i, ...)." >&2
    exit 2
  fi
done

# --- Check 2: jenkins-cli groovy / groovysh verb (verb-position match) ---
cli_seen=0
skip_next=0
for tok in $cmd; do
  if [ "$skip_next" = "1" ]; then
    skip_next=0
    continue
  fi

  base="$(lower "${tok##*/}")"
  if [ "$base" = "jenkins-cli.jar" ] || [ "$base" = "jenkins-cli" ]; then
    cli_seen=1
    continue
  fi

  if [ "$cli_seen" = "1" ]; then
    case "$tok" in
      -s | -auth | -i | -logger)
        # Known value-taking global options - skip the flag and its value, verb
        # hasn't appeared yet.
        skip_next=1
        continue
        ;;
      -*)
        # Other global flags (-webSocket, -http, -noCertificateCheck, ...) are
        # boolean - skip just the flag, verb still hasn't appeared.
        continue
        ;;
    esac

    case "$tok" in
      groovy | groovysh)
        echo "guard-jenkins: refusing - jenkins-cli '$tok' evaluates arbitrary Groovy on the controller (RCE). Out of scope for this agent; use a read-only jenkins-cli verb (who-am-i, console, get-job, ...) or REST instead." >&2
        exit 2
        ;;
    esac

    # First non-flag token after jenkins-cli that isn't groovy/groovysh IS the
    # verb (e.g. build, get-job, console, who-am-i) - done classifying this
    # invocation, stop treating subsequent tokens as CLI-relative.
    cli_seen=0
  fi
done

set +f
exit 0
