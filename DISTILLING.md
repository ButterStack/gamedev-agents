# Distilling private learnings into this repo

`gamedev-agents` is the public-facing side of a private working repo where
ButterStack actually runs these agents against real depots, engines, and CI
servers. When something real lands in the private repo's `NOTES.md` or
`LEARNINGS.md` - a validated gotcha, a corrected assumption, a real-server finding
- it should get distilled into this repo on a standing basis, not as a one-off.

This document is the process. It's written to be handed to an agent verbatim as a
task prompt (see "Prompt to hand an agent" at the bottom) - a human should still
spot-check the result before it's pushed, but the mechanical pass is repeatable.

## Why this exists

The first build of this repo (see the initial commits) was a one-time distillation
of the whole private repo at once. That was a big, careful, one-shot pass. This
document exists so the *next* one - and the one after that - doesn't need the same
from-scratch judgment call every time. Read it, follow it, and the distillation
should come out consistent with what's already here.

## (a) Sanitization checklist

Work through every file that's new or changed since the last distillation. For
each one:

**Strip entirely - these should never appear in this repo:**
- Internal Rails/app file paths and method names (`app/services/...`,
  `client.rb#some_method`, specific class/service names from the private repo's
  codebase).
- Internal hostnames and URLs (`demo.butterstack.com`, `staging.butterstack.com`,
  any `*.butterstack.com` subdomain that isn't the public marketing site,
  internal admin panels).
- Docker container/service names tied to the private repo's compose setup
  (`butter_stack-jenkins-1` and similar).
- Personal names (Kevin, Ryan, or any other individual) - reword to "the team",
  "we", or drop the attribution entirely. First-person plural ("we found",
  "we recommend") reads fine and is honest without naming anyone.
- Internal tracking references: GitHub issue numbers, branch names
  (`claude/issue-36-...`), PR numbers, internal doc filenames.
- Private repo URLs, including private forks (e.g. an org-internal fork of a
  third-party engine/tool repo).
- Secret or credential **values** - obviously. If you find one, do not copy it
  anywhere, including into a commit message. Note its location so it can get
  rotated if needed, and tell the human doing the review.
- Any literal tool-call or agent-transcript artifacts that leaked into a file by
  accident (stray XML-ish tags, "Fable: CORRECT"-style self-grading notes, or
  anything else that only makes sense as output of an agent session rather than
  as a description of the tool being documented).

**Keep and foreground - this is the actual value of the repo:**
- Tool truths: how the real tool actually behaves, especially where it
  contradicts its own docs or contradicts Git-shaped intuition.
- Validation narratives: "we ran this against a real server/engine and here's
  what we found" - these are what make the repo credible. A concrete detail
  (server version, corpus size, a real error string) is a feature, not a leak,
  as long as it isn't itself internal (see below).
- Exact error strings, exit codes, flag names, and command forms - these are
  what make a playbook copy-pasteable and are never sensitive.

**Genericize - keep the substance, drop the specific internal-ish identifier:**
- Personal or team machine/rig names (`beast`, `wanda`, `beast-wsl`) → "the
  primary test machine," "a second machine on hand."
- An internal environment name used as a stand-in for "a real server" (e.g. "the
  demo Perforce server") → "our own internal Perforce server" or similar - the
  fact that it's real and internal is worth keeping; which specific named
  environment it was is not.
- A private test-project codename that leaks nothing on its own (it's not a
  customer, not a business detail) can usually stay if it's already baked into
  a real fixture filename or captured log - don't rename fixtures to hide a
  codename that's already public inside the file's own content. Use judgment:
  if the name alone would tell an outsider something ButterStack hasn't chosen
  to disclose, genericize it; if it's just a label for "our second test game,"
  it's fine.

Run a final grep sweep before considering a file done:
```
grep -rniE 'Kevin|Ryan|butter_stack-|app/(services|clients|controllers)|demo\.butterstack|staging\.butterstack|issue #[0-9]|branch `claude/' <changed files>
```
Zero hits, or every hit explained, is the bar.

## (b) The 30-50% compression rule

Every `LEARNINGS.md` file, and the learnings-heavy sections of every `NOTES.md`
(anything titled "Validation status," "Live validation," "Verified vs
not-yet-verified," or similar), should read as a *distillation*, not a transcript.
Target cutting the section's line count by 30-50% versus the private-repo source,
while making it stronger, not just shorter.

**What qualifies as a keep:**
- The strongest 2-4 validation-against-reality stories per plugin - the ones with
  a concrete, surprising, load-bearing finding (a format flag that silently isn't
  what it claims to be, an error code that means something different than
  documented, a trap where the obvious fix is wrong). If a plugin doesn't have a
  clear "strongest story," that's a sign the learning itself may not be worth
  distilling yet - wait for a better one rather than padding.
- Anything that would change what a reader actually does differently.
- A finding that generalizes beyond the one server/engine/session it was found
  on. Note explicitly when something *hasn't* been shown to generalize yet.

**What qualifies as a cut:**
- Repetitive dated minutiae - five session-log entries that all restate the same
  underlying fact with different dates and slightly different framing collapse
  into one entry.
- Session-by-session chronology (an "Open items / TODO" checklist that just
  re-lists what the dated entries above it already said, with checkmarks) -
  drop it; it's process tracking, not a finding.
- Anything that only makes sense with context the private repo has and this one
  doesn't (a reference to "the earlier internal note," an internal review pass
  name, an internal debugging session's blow-by-blow).
- Restating the same finding in both `NOTES.md` and `LEARNINGS.md` at full
  length - pick one home for the detail (usually `LEARNINGS.md`, since it's the
  dated log) and have the other point to it in a sentence.
- Narrow, single-instance edge cases that don't teach a durable lesson (a very
  specific build configuration that failed once for reasons unlikely to recur)
  unless they're genuinely instructive as a *category* of failure.

**How to compress without losing substance:** merge adjacent bullets that are
really one story told twice, tighten prose (cut "we spent a long time chasing
this" scene-setting once the lesson itself is clear), and prefer one well-written
paragraph over three short ones that repeat each other's setup. Never compress by
deleting the technical specifics (the exact error string, the exact flag, the
exact version number) - compress the narration around them.

## (c) Truthfulness rule

Every claim in this repo must be **literally true**. This is non-negotiable and
applies to every word, not just the obviously factual ones.

- Do not assert an installed customer base, invent studio names, or invent usage
  counts. ButterStack is not yet publicly launched as of this writing - don't let
  distilled copy get ahead of that.
- Prefer grounded phrasing that's true without overclaiming: "the production
  depots and builds we analyze," "our own live Helix Core history," "real
  projects running the full stack (Perforce, Jenkins, Jira, UE5)." These are true
  regardless of how many external customers exist, because they describe
  ButterStack's own internal usage, not a customer's.
- A validation story should describe exactly what was tested (real server, real
  engine, disposable/torn-down or long-lived, one session or several) without
  implying broader coverage than what actually happened. "Still not verified"
  callouts are a feature - keep them.
- If a rewritten sentence would be false, inaccurate, or misleading if someone
  fact-checked it against reality, rewrite it again. Vague-but-true beats
  precise-but-false every time.
- No license claims beyond what's actually true of this repo at the time of the
  distillation pass (check the root README's License section for current status
  before writing anything that touches licensing).

## (d) Trigger and cadence

- **Trigger:** whenever a dated entry lands in a plugin's `LEARNINGS.md` in the
  private working repo, or a `NOTES.md` validation section gets a real update
  (not just a wording tweak).
- **Cadence:** distill within about a week of the private-repo entry landing.
  Don't let it pile up into a large, hard-to-review backlog - small, frequent
  distillation passes are easier to sanitize correctly and easier to review than
  one big one.
- **Scope per pass:** one plugin's new entries at a time is fine; a pass doesn't
  need to touch every plugin. Batch multiple plugins together only if they
  updated close together in time.
- **Trivial changes don't need a pass:** a typo fix or a link update in the
  private repo doesn't need to flow through this process - only actual new
  learnings (a new dated entry, a corrected claim, a new validation finding).

## (e) Prompt to hand an agent

The block below is meant to be copied as-is into a task for an agent (with the
bracketed parts filled in) when it's time to run a distillation pass. It assumes
the agent has read access to the private working repo and write access to a
clone of this one.

```
Distill recent learnings from the private working repo into ButterStack/gamedev-agents.

Source: [private repo name/path], specifically [plugin name(s)]'s LEARNINGS.md
and/or NOTES.md, changes since [date or commit SHA].

Target: the matching plugin director(y/ies) in a clone of ButterStack/gamedev-agents.

Read DISTILLING.md at the target repo's root first - it is the full spec for
this task: the sanitization checklist (section a), the 30-50% compression rule
and what counts as keep vs cut (section b), the truthfulness rule (section c),
and the cadence this is meant to run on (section d). Follow it exactly.

Do:
1. Diff the private repo's relevant LEARNINGS.md/NOTES.md against what's already
   distilled into the target repo, to find what's actually new.
2. Apply the sanitization checklist to the new material.
3. Integrate it into the target repo's LEARNINGS.md (new dated entries) and/or
   NOTES.md (if it changes a validation summary), keeping the whole file within
   the compression target - trim older content further if needed to make room,
   don't just let files grow unboundedly.
4. Run the final grep sweep from section (a) with zero unexplained hits.
5. Apply the truthfulness rule to every sentence you write or touch.
6. Do NOT touch unreal/fixtures/ - those are handled separately.
7. Do NOT modify the private working repo. Read-only there, always.
8. Commit with a clear message (temp file + `git commit -F`, ending with
   "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>", no em dashes) and
   push to this repo's main.

Report: which entries were distilled, before/after line counts for any file you
changed, anything you excluded and why, and any secret/credential values you
found in the source material (do not copy them anywhere - report their location
only).
```
