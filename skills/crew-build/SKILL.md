---
name: crew-build
description: Executes the Tasks JSON from plan.md wave by wave via crew-builder subagents, with ownership guards and per-wave verification. Use as phase 5 of a crew run.
---

# crew-build

Phase 5. Gate 1 is approved. You orchestrate; builders execute.

Read the Tasks JSON block from `<repoRoot>/.crew/<slug>/plan.md`. Set `phase` to `build`
in `state.json`. Write state on entry, not on exit — a crash mid-wave must resume into
build, not skip it.

Initialise `waveCursor` to `0` **only when it is absent**. A resumed run continues from the
saved cursor. Resetting it on entry re-runs waves that already completed, which is the
opposite of what crash-resume is for.

## 1. Compute waves

Waves come from `needs` by topological sort. Never hand-number waves in the plan or here.

```
needs: []           → wave 0
needs: ["t1"]       → after t1 completes
needs: ["t1","t2"]  → after both complete
```

Each wave is every task whose `needs` are satisfied by earlier waves. Waves are ordered
and indexed from `0`. Completion is tracked per wave, not per task — there is no built
flag on individual tasks, and a wave is done only when every task in it passed verify.

**Consume `waveCursor`.** Skip every wave with an index below it, and write the new value
after each wave passes its guard and verify. Not resetting the cursor on entry is only
half of resume — a loop that never reads it re-runs completed waves anyway.

## 2. Ownership

Ownership is `files ∪ generates` for every task. Optional `generates` defaults to empty.
This union drives dispatch, the post-wave guard, and PR staging — one contract everywhere.

| Rule | Why |
|---|---|
| Parallel dispatch only when unions are disjoint | Two builders on the same union collide |
| Serialize tasks sharing any path in `generates` | Generated output has one writer |
| Serialize tasks whose `verify` touches shared state | Databases, fixture dirs, build caches, ports |

When serializing, run tasks in stable `id` order within the wave slot.

## 3. Dispatch

For each task in the current wave, dispatch `crew-builder` (`composer-2.5-fast`).

Pass: task `id`, full task spec (`files`, `generates`, `instruction`, `verify`), plan path,
worktree path from `state.json.git.worktreePath`.

Parallel when unions are disjoint. One builder per task. Never batch unlike tasks into one
dispatch.

The builder's output contract:

```
Status:  DONE | DONE_WITH_CONCERNS | BLOCKED
Files:   every path changed, including generated
Verify:  command, exit code, relevant output
Concerns: omit if none
Blocked: omit if none
```

A builder reporting PASS is a claim. You run verification yourself in step 5.

## 4. Post-wave guard

Before dispatching a wave:

```bash
git status --porcelain
```

Save the snapshot. After every builder in the wave finishes, snapshot again.

Diff the two snapshots to paths changed *in this wave only*. Do not compare the whole
dirty tree — earlier waves' work would read as unowned and stop the line falsely.

For each path changed this wave:

| Check | Action |
|---|---|
| Path is in some task's `files ∪ generates` for this wave | OK |
| Path is outside every union in this wave | Stop. Escalate. Never absorb silently |
| Builder's `Files` list omits a changed path | Stop. Omission reads as unowned |

## 5. Verify

After the guard passes, run each task's `verify` command yourself — in the worktree, in
stable `id` order. Use the shell. Read exit codes and output.

| Builder verify | Orchestrator verify |
|---|---|
| Runs during implementation | Runs after the wave guard |
| Informs the builder's fix loop | Is the wave's pass/fail |
| Reported in builder output | Never trusted as proof |

A task passes only when you ran `verify` and it exited zero.

## 6. Circuit breaker

Track failures per task and per run.

| Condition | Action |
|---|---|
| Same task fails twice | Stop the line. Surface to human. |
| Three failures across the run (any tasks) | Stop the line. Surface to human. |

A failure is: builder `BLOCKED`, post-wave guard stop, or verify exit non-zero after you
ran it. `DONE_WITH_CONCERNS` counts as success unless verify fails.

Never retry a third time on the same task. Two failures on one task is usually a wrong
plan, not a wrong builder.

Record breaker state in `state.json` so a resumed run does not reset counts silently.

## 7. Advance

Increment `waveCursor` after each wave passes guard and verify. Write `state.json`.

When all tasks are built, set `phase` to `review`. Load `crew-review`.

## Never

- Never dispatch parallel builders whose `files ∪ generates` overlap.
- Never parallelize tasks that share a `generates` path.
- Never parallelize tasks whose `verify` commands touch shared state.
- Never trust a builder's verify report as the wave's verification.
- Never compare the full dirty tree in the post-wave guard — only this wave's delta.
- Never absorb a changed file outside the wave's unions.
- Never hand-number waves instead of deriving them from `needs`.
- Never retry a task a third time after two failures.
- Never commit, push, or stage in this phase.
- Never advance past build without writing `state.json`.
