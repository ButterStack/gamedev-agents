---
description: Tail or fetch a Jenkins build's console log, capped and structured - plus a test-report summary if present
argument-hint: "<job-name> [build-number]"
---

Fetch and summarize console output for the build named in `$ARGUMENTS` (job name
required; build number optional - default to `lastBuild`). Read-only. Use the
`jenkins-observe` skill (§5) for exact request forms.

Steps:

1. Resolve the job/build (`jenkins-observe` §2-3) - confirm it exists and note
   `building` (still running?) vs a finished `result`.
2. **If the build is still running**, use `logText/progressiveText?start=0` and
   report `X-More-Data`/`X-Text-Size` - offer to keep tailing (repeated calls with
   `start=<last X-Text-Size>`) rather than a one-shot dump, since the log is still
   growing.
3. **If the build is finished**, a single `logText/progressiveText?start=0` (or
   `consoleText` for a short log) is sufficient - no need to poll.
4. **Don't paste the raw log wholesale.** Summarize: build stage reached, the
   first/last error-looking lines (grep for `ERROR`, `FAILED`, `Exception`,
   `error:`/`fatal:` for compile errors), and duration. Offer the full log only if
   asked.
5. **If the build failed or is unstable**, also check `testReport/api/json`
   (`jenkins-observe` §6) - a `404` there just means no test report is published
   (not an error); if present, summarize `failCount`/`passCount` and name the
   failing cases.
6. For a build that never fired at all (nothing to fetch logs for), hand off to the
   `jenkins-p4-bridge` skill rather than reporting "no logs found" as the answer.

**Example:** *"Why did the last MyGame-Cook fail?"* → pull `lastBuild`'s
result (`FAILURE`), tail its console via `progressiveText`, surface the first real
error line (e.g. an Unreal `BuildCookRun` cook failure or a `MAX_PATH` Windows
packaging error), and check `testReport` for any failing test cases - a tight
summary, not the raw 16KB log.
