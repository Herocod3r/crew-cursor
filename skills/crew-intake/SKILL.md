---
name: crew-intake
description: Opens a crew run. Verifies git preconditions, restates the problem, grounds it in actionable work, sets the size, and seeds state.json. Use as phase 1 of a crew run.
---

# crew-intake

Phase 1. Nothing else runs until this passes.

## 1. Preconditions

crew never creates, moves, or deletes a worktree or branch. The human owns that
lifecycle. crew verifies the context and records it — not owning it is no excuse for not
knowing it, because the build slice needs a branch to diff and push.

```bash
git rev-parse --is-inside-work-tree
git rev-parse --is-bare-repository
git rev-parse --abbrev-ref HEAD
git rev-parse --show-toplevel
git worktree list --porcelain
```

| Condition | Action |
|---|---|
| `git` exits non-zero | Stop. Not a repository. |
| Bare repository | Stop. No working tree to plan against. |
| `HEAD` is detached | Stop. Nothing to push later. |
| Main checkout, not a linked worktree | Say so. Ask: continue here, or stop so you can make one. Never create it. |
| Linked worktree on a branch | Proceed. |

`repoRoot` is the first `worktree` line of `git worktree list --porcelain` — the main
checkout. Never `git rev-parse --git-common-dir`; in a submodule that resolves under
`.git/modules/` and would write state into Git internals.

## 1b. Check the agents are registered

Plugin-bundled agents silently ignore `model` and `readonly`, and `~/.cursor/agents/` does
not load in the CLI at all. Only the repo's own `.cursor/agents/` honours both, which is
what makes the critic a different model family, the builders cheap, and the read-only
reviewers read-only structurally rather than by request.

The `cursor` wrapper links them before the session starts. **Do not link them here.**
Subagents are registered once at startup, so a symlink created during a run stays invisible
for that entire run — verified: the linking step reports success and the very next dispatch
in the same session still says the type is unavailable.

Check registration, not the filesystem. Dispatch `crew-retriever` with a trivial prompt, or
read your own available subagent types.

| Result | Do this |
|---|---|
| All four registered | Continue. |
| Missing, links absent | Run `~/.cursor/plugins/local/crew/install.sh ensure`, then stop and tell the human to rerun `/crew` in a new session. |
| Missing, links present | The wrapper ran but startup did not pick them up. Report it and stop. |

Stop rather than continue degraded. A missing `crew-critic` turns the critique same-family
and a missing `crew-builder` runs the whole build on the expensive parent model, and neither
announces itself.

Symlinks, never copies — a copy keeps working while drifting from the plugin, so the pinned
model quietly stops matching. Ignored through `.git/info/exclude`, never the repo's tracked
`.gitignore`: these are absolute paths into one machine's plugin directory and must never
reach another clone, and editing a tracked file is not intake's job.

## 2. Restate

State the problem back in one paragraph, in your own words. Not a summary of their
sentence — your understanding of what is actually wrong and what changing it buys.

Then ground it. A goal is actionable when you can name:

- The observable thing that is wrong or missing
- Where it lives, at least approximately
- What "done" looks like, concretely enough to verify

Missing any of those, ask for it. One question. Do not proceed on a goal you cannot test
against later.

Detect ticket references matching `[A-Z]+-\d+`. Record them in `ticketRefs`. Do not fetch
them here — that is the scout phase.

## 3. Size

Default `standard`. Escalate on any trigger. Drop to `trivial` only on the syntactic test.

**Triggers**, any one: money, auth, PII, data migration, public API, concurrency,
idempotency, background jobs, cross-service boundaries, feature flags, irreversible
user-visible behavior, production observability.

**`trivial`** requires all of: an explicit single-file path is named; the change is docs,
comments, typo, formatting, or test-only; it touches no package manifest, lockfile,
config, schema, or migration; it changes no exported symbol; no trigger word appears in
the goal.

Anything needing a judgment call about whether an interface changed is `standard`.

State the size and its reason in one line. Do not ask.

## 4. Slug

Kebab-case, from the ticket key or the topic. Must match `^[a-z0-9][a-z0-9-]*$`. No
slashes, dots, or `..`. State your choice in one line; do not make it a question.

Check `<repoRoot>/.crew/` first. Reuse an existing slug when the work belongs to that
run. If a fresh slug collides with unrelated work, make it more specific.

## 5. Seed state

Create `<repoRoot>/.crew/<slug>/state.json` per the schema in the `crew` skill. Set
`phase` to `scout`, or to `design` when size is `trivial`. Fill the whole `git` block.

Then load the next phase skill.

## Never

- Never create a worktree or branch.
- Never proceed past a failed precondition.
- Never accept a goal you cannot verify completion against.
- Never ask the human to pick the slug or the size.
