---
name: crew-retro
description: Routes run learnings to repo rules or personal notes, reports cleanup, and closes the run. Use as phase 9 of a crew run.
---

# crew-retro

Phase 9. Last phase. Enter after the PR merges.

Harvest what transfers. Discard what does not. Report what the human should clean up.
Then close the run.

## 1. Enter

Set `phase` to `retro` in `state.json` and mirror it in `plan.md` frontmatter.

Confirm `pr.merged` is true. If babysit stopped short of merge, do not enter retro — resume
babysit.

## 2. Harvest learnings

Review the run: plan, build, review, PR, babysit. Ask one question per candidate:

> Would knowing this before the run have changed how it went, and will it recur?

Most run detail is **not** a learning. Discard it.

| Example | Learning? |
|---|---|
| The build failed once | No — noise |
| This repo's test suite needs a running database, and the plan should say so | Yes — recurring repo quirk |
| A reviewer asked for a variable rename | No — one-off |
| Two builders collided on a lockfile because `generates` was omitted | Yes — transferable process lesson |

When in doubt, discard. A note that never helps again is clutter.

## 3. Route by scope

For each learning that passes the harvest test:

| Scope | Destination |
|---|---|
| Specific to this repo | A rule in that repo's `.cursor/rules/` |
| Transfers to other work | A personal note under `~/.cursor/` |
| Neither | Do not write it |

**Repo rules** — `.mdc` format with frontmatter. Short. One idea per rule.

```markdown
---
description: What this rule enforces
globs: **/*.ts
alwaysApply: false
---

Rule body. Imperative. Under twenty lines.
```

Prefer amending an existing rule to adding a new one. A directory of near-duplicate rules
is worse than none.

**Personal notes** — a dated file under `~/.cursor/` (for example
`~/.cursor/crew-learnings.md`). Append; do not overwrite unrelated notes.

## 4. Report cleanup

Read from the `git` object in `state.json`:

| Field | Report |
|---|---|
| `worktreePath` | Path the human may remove |
| `branch` | Branch the human may delete |

Print both explicitly. crew reports; crew does not act. It created neither the worktree
nor the branch, and it does not delete either. The human owns worktree and branch
lifecycle in every phase — carried from v1.

## 5. Close

Set `phase` to `done` in `state.json` and `plan.md` frontmatter.

Print a one-line run summary:

```
<slug> — <pr.url> — <what shipped>
```

Pull `slug` from state, `pr.url` from state, and summarize the goal or the merged change
in one phrase.

## Never

- Never delete the worktree or branch. Report them and stop.
- Never write a non-learning. Most run detail is noise.
- Never add a repo rule when amending an existing one suffices.
- Never overwrite unrelated personal notes.
- Never enter retro before merge.
- Never skip setting `phase` to `done`.
