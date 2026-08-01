---
description: Preview changes in the Lore working tree, between revisions, or between branches (read-only)
argument-hint: "[paths | <revA> <revB>]"
---

Show a Lore diff for the user. Read-only - run no write command. Use the `lore-observe`
skill (§3) for exact command forms. Interpret `$ARGUMENTS`:

1. **No args** → `lore diff`: the working tree vs. the current revision (the "what have I
   changed locally, uncommitted" view - this is the default comparison).
2. **Path(s)** → `lore diff <paths>`: scope the working-tree diff to those paths.
3. **Two revisions** → `lore diff --source <revA> --target <revB> [paths]`, or
   `lore revision diff <revA> --target <revB>` for whole-revision diffs.
4. **A branch comparison** (if the user names branches) → `lore branch diff <target>
   --source <branch>` (compares via common ancestor).

Guidance:

- Add `-U <n>` for more/less context, and `--ignore-space-at-eol` /
  `--ignore-space-change` to cut whitespace noise on text files.
- **Binary assets** (`.uasset`/`.umap`/`.fbx`/`.psd`/`.png`/`.wav`, packaged builds)
  don't produce a meaningful textual diff - report *that a binary changed* and its size
  delta (`lore file info <asset>`), not a byte dump.
- For conflict-marker (3-way) output during a merge, use `--diff3`.

Summarize what changed at a useful altitude (files touched, nature of the change), then
show the relevant hunks - don't just paste the whole diff for a large changeset. To
stage/commit what you're previewing, hand off to the `lore-workflows` skill (§0).

**Example:** *"What have I changed?"* → `lore diff` → "3 files: `Config/Game.ini`
(+4/-1, tuning), `README.md` (typo fix), `Art/Hero.uasset` (binary, +1.2 MB)."
