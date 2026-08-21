# Security Policy

## Reporting a vulnerability

If you find a security issue in one of these agents, skills, or guard hooks -
including a way to bypass a guard hook's "hard block," a prompt-injection
path, or anything else with a real security impact - please report it
privately rather than opening a public issue.

Email **hello@butterstack.com** with a description of the issue, the affected
plugin, and reproduction steps if you have them. We will acknowledge reports
within a few business days and keep you updated as we work through a fix.

Please do not open a public GitHub issue for a security report until we've
had a chance to address it.

## Scope

This repo ships Claude Code plugins: agent definitions, skills, slash
commands, and PreToolUse guard hooks (`*/scripts/guard-*.sh`) for Perforce,
Unreal Engine, Unity, Epic's Lore VCS, and Jenkins integrations. In scope:

- A guard hook that fails to block a command it documents as blocked.
- A prompt-injection or command-injection path in any agent, skill, or hook.
- Anything that could exfiltrate credentials or tokens from the environment
  the agent runs in.

Out of scope: vulnerabilities in Perforce, Unreal Engine, Unity, Lore, or
Jenkins themselves - report those to the respective vendor.

## A note on the guard hooks

The guard hooks in this repo are shell-string matchers, not sandboxes. They
are a backstop against common invocation forms of catastrophic operations,
not a guarantee against every possible way to construct an equivalent
command. Each plugin's README says plainly what the actual safety boundary
is (the underlying account's own permissions, source control, or both) - the
hooks reduce the blast radius of an obvious mistake, they do not replace
least-privileged credentials.
