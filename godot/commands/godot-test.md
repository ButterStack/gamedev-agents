---
description: Run a Godot GUT suite and verify the result is trustworthy - checks for silently skipped scripts and unfailable CI gates
argument-hint: "[test-path-or-empty-for-full-suite]"
---

Run the project's GUT suite for the user, scoped by `$ARGUMENTS` if given, and
then **verify the result is real**. Use the `godot-test` skill.

1. Preflight: if the branch changed since the last import, run
   `--headless --import` first (`godot-observe` §3) or the results are
   phantom.
2. Prefer a **full-suite** invocation (`-gdir=`). A `-gtest=` run cannot
   exercise the suite-integrity check.
3. After the run, do not report "all tests passed" on the exit code alone:
   - scan for `Ignoring script ... because it does not extend GutTest` - each
     one may be a script that **failed to parse**, and the run still exits 0
   - compare the collected test count against what the suite should contain
   - if the run went through a pipe in CI, confirm `pipefail` is set, or the
     exit status is `tee`'s and means nothing
4. Recognise `Invalid call. Nonexistent function 'new' in base 'GDScript'` as
   "a script failed to compile" (often a native-method shadow escalated by
   GUT), not "the class is missing".

Report the collected-vs-expected count alongside pass/fail, and state the
engine version.
