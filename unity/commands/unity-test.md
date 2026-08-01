---
description: Run a gated Unity test pass - EditMode/PlayMode via unity test, --timeout always set in CI, results read from the NUnit XML (never exit code alone)
argument-hint: "[EditMode|PlayMode] [filter]"
---

Guide the user through a safe, gated `unity test` run per `$ARGUMENTS` (mode,
optional test-name filter - default to EditMode, the cheaper probe, unless
the question needs runtime behavior). Use the `unity-build` skill (§3) for
the exact command forms.

Steps:

1. **Preflight** (`unity-build` §0): doctor core (`unity-observe` §1-§7) -
   Editor version resolved and installed, license active
   (`unity license status`, not `auth status`), no `Temp/UnityLockfile` held
   by another process.
2. **Choose the cheapest sufficient mode** - `--mode EditMode` proves compile
   + logic fast; `--mode PlayMode` actually enters play mode (closer to
   runtime, slower). Narrow with `--filter <pattern>` when the user asks
   about specific tests.
3. **Always set `--timeout <seconds>`** when running unattended/CI - it is
   **disabled by default** and a hung PlayMode test hangs forever. Pick a
   bound from the suite's known runtime, generously padded.
4. **Show, then confirm** - print the exact command line, e.g.
   `unity test . --mode EditMode --output ./results/edit.xml --timeout 900`,
   plus the cost estimate (`unity-build` §7), and **wait for confirmation**
   before running.
5. **Run and read the NUnit XML** - `--output <path>` (default
   `test-results.xml`). Parse the XML for total/passed/failed counts; a
   compile error (`error CS####` in the log) means the tests never ran at
   all - report that as the finding, not "tests failed".
6. **Report observed results**: pass/fail counts from the report file, the
   first failing test's name + message if any, duration - never the exit
   code alone (the batchmode exit-0 trap applies to test runs too).

If tests fail, quote the first failure with its message, explain what it
means, and propose the targeted fix. If the run hung and was killed by the
timeout, say so explicitly - a timeout kill is an environment/dialog problem
to diagnose (`unity-observe` §8), not a test failure.

**Example:** *"Do the tests pass before I package?"* -> doctor, then propose
`unity test . --mode EditMode --output ./results/edit.xml --timeout 900`,
confirm, run, and report "42/42 passed in 3m 10s" from the XML - not from
`$?`.
