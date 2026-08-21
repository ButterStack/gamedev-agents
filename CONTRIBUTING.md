# Contributing to gamedev-agents

Thanks for your interest in contributing! `gamedev-agents` is ButterStack's series of
domain-specific gamedev agents for Claude Code, and each one stays useful precisely by
staying narrow.

## Philosophy

These are **not** general-purpose clients or do-everything assistants. Each plugin is
a tightly scoped Claude Code agent, a handful of skills, and a few slash commands
whose job is to **observe, analyze, and safely operate** one specific tool for game
teams.

A few things we hold to be non-negotiable:

- **Read-first.** The default posture is inspect and summarize, not mutate.
  Observation and analysis should run freely; anything that writes to a depot, repo,
  build server, or project is a deliberate, gated action.
- **Destructive operations stay dangerous on purpose.** `p4 revert`, `p4 obliterate`,
  `lore file obliterate`, force sync, Jenkins job/build deletes - these have explicit
  confirmation gates, dry-run-first requirements, and "never on someone else's work"
  rules baked into each plugin's `agents/*.md`. Any PR that touches these paths must
  preserve - not loosen - those guardrails. If you think a rule is wrong, open an
  issue and make the case; don't quietly relax it in a playbook.
- **Large binaries are expensive.** Reverts, force syncs, full engine rebuilds, and
  lock releases on multi-GB game assets aren't free actions - treat them with the
  same caution the agents do.

If a change makes an agent more convenient at the cost of any of the above, it's not
a fit for this repo.

## How to contribute

1. **Fork** the repo and create a feature branch off `main` (e.g.
   `fix/reconcile-ignore-globs`, `docs/streams-playbook`).
2. Make your change. See "Style conventions" below for playbook conventions.
3. Open a **pull request** against `main` with a clear description of what changed
   and why. Reference any related issue.
4. Keep PRs focused - one concern per PR is easier to review and easier to test
   against a real server/engine.

### Keep the agent prompt tight; push detail into skills

Each plugin's `agents/<name>.md` is that agent's system prompt, and it should stay
tight: identity, safety rules, and *when* to reach for a playbook - not the playbooks
themselves. Detailed, step-by-step command sequences belong in that plugin's
`skills/*/SKILL.md` files, which load on demand.

This isn't just tidiness - it's a token-efficiency choice. A skill only enters
context when it's actually needed for the task at hand; bloating the agent's own
system prompt means paying that cost on *every* invocation, observe-only requests
included. If you're adding a new operational sequence, it almost always belongs in a
skill with a pointer from the agent prompt, not inline in the agent file.

## Especially valued: real-server / real-engine testing reports

Most of what's in this repo is written from domain knowledge and validated against
one test setup per tool. Real-world behavior varies meaningfully by server/engine
version, topology, security level, and configuration - so **testing reports from
contributors running against a real setup are one of the most valuable contributions
you can make**, even without changing a line of the playbooks.

If you run a command sequence from a skill or slash command against a live
server/engine, please open an issue or PR note using this template:

```
**Tool/version**: <e.g. p4d 2024.1, Jenkins 2.504.2, Unreal 5.7, Unity 6000.x, lore 0.9.x>
**Topology/config**: <whatever's relevant - classic vs streams, CSRF on/off, editor version, etc.>
**Tested**: <which playbook / command sequence, e.g. "p4-workflows §6 revert safely">
**Result**: worked as documented | needed correction (describe) | failed (paste the exact error)
**Notes**: anything version-specific worth calling out
```

Corrections based on real output are welcome as PRs directly against the skill
files - please keep the corrected command sequence and note the version it was
verified against in the PR description.

Durable, dated integration learnings - webhook/trigger behavior, connection/auth
quirks, gotchas that a testing report turns into a general lesson - are logged in
each plugin's `LEARNINGS.md` (e.g. [`perforce/LEARNINGS.md`](./perforce/LEARNINGS.md),
[`unreal/LEARNINGS.md`](./unreal/LEARNINGS.md), [`lore/LEARNINGS.md`](./lore/LEARNINGS.md)).
If your report generalizes beyond one server/engine, add an entry there too.

## Style conventions

- **Playbooks are copy-pasteable.** Use `<ANGLE_BRACKET>` placeholders (`<CL>`,
  `<depot_path>`, `<USER>`) so a command can be pasted and edited in place, not
  `[bracketed]` or free prose describing the command.
- **Every destructive playbook starts with a dry-run.** If a sequence includes a
  revert, force sync, reconcile, unlock, resolve-with-overwrite, or similar, the
  first step must be the preview/dry-run form, with the real command following only
  after review.
- Match the existing tone in the skills: terse, command-first, with a short "why
  this matters" note rather than long prose explanations.

## Linting and validation

Every plugin must pass the lint before it merges - CI runs it on each PR
(`.github/workflows/lint.yml`), and you can run it locally:

```sh
./scripts/lint-plugins.sh
```

Two layers, no API key or `claude` login required:

- **Official** - [`claude plugin validate <path> --strict`](https://code.claude.com/docs/en/plugins-reference)
  on the marketplace and each plugin: `plugin.json`/`marketplace.json` schema,
  `hooks/hooks.json` structure, and agent/skill/command frontmatter syntax. Install
  the CLI with `npm i -g @anthropic-ai/claude-code`; the lint skips this layer with a
  warning if `claude` isn't present.
- **Portable** (jq only) - the gaps the validator doesn't cover: required frontmatter
  *fields* (`name`+`description` on agents/skills, `description` on commands),
  `plugin.json` `name` matching both its directory and its marketplace entry, and
  every hook `command` script existing **and being executable** (`chmod +x` your
  guard/worktree scripts - a non-executable hook silently no-ops). Shell scripts are
  run through `shellcheck -S warning` when it's installed.

Behavior testing (optional, not in CI): `claude plugin eval` / the `skill-creator`
plugin can score an agent or skill against prompt cases, but it spawns subagents and
so needs API access - run it locally when tuning an agent's prompt, not in CI.

## Scope and non-goals

- These are **gamedev-focused** agents, not general administration tools for their
  underlying systems. Server administration, license management, and
  broker/proxy/infrastructure configuration are out of scope unless they directly
  affect a gamedev workflow (e.g. trigger health for CI).
- **No hard dependency on a third-party MCP server.** Each plugin is deliberately
  CLI/REST-driven so it works anywhere the underlying tool is installed. Structured
  backends (e.g. an MCP server for the tool) may be explored later as an optional,
  preferred-when-available path - but PRs should not make an agent or its skills
  *require* one.
- Engine-specific presets (typemap, `P4IGNORE`, etc.) are welcome for Unreal, Unity,
  and other common engines, but keep additions data (presets, tables) rather than
  engine-specific control flow baked into an agent prompt.

## Issues and questions

Bug reports, playbook corrections, and "this doesn't match what I saw on my
server/engine" reports are all welcome as GitHub issues - you don't need a PR in
hand to flag something. If you're unsure whether an idea fits the scope above, open
an issue first and we'll figure it out together.

## Code of Conduct

Be respectful, assume good faith, and keep discussion focused on the work. We want
this to be a welcoming place for contributors testing against very different
setups.

## License

This repo is MIT licensed (see [LICENSE](./LICENSE)). By submitting a
contribution, you agree it is provided under the same MIT license as the rest
of the project.
