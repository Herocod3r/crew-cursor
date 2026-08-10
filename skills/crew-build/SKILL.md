---
name: crew-build
description: Executes the task sections of plan.md wave by wave via crew-builder subagents, with ownership guards and per-wave verification. Use as phase 5 of a crew run.
---

# crew-build

Phase 5. Gate 1 is approved. You orchestrate; builders execute.

Read every `### tN` section under `## Tasks` in `<repoRoot>/.crew/<slug>/plan.md` and parse
each one's `yaml` header. Structure is only what sits outside a fenced block, and a task's
header is the first `yaml` fence after its heading; the rest of the rules are in
`skills/crew/references/plan-format.md`. Set `phase` to `build` in `state.json`. Write state
on entry, not on exit — a crash mid-wave must resume into build, not skip it.

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

Compare what you derived against the plan's `## Wave list`. On any disagreement, stop and show
both. A plan with no such section, or one that does not parse, stops the phase too — an absent
list is not an agreement. That list was derived from the same `needs` at design time, so two derivations differing
means one of you misread the plan, and the human should see which before a builder runs.

**Consume `waveCursor`.** Skip every wave with an index below it, and write the new value
after each wave passes its guard and verify. Not resetting the cursor on entry is only
half of resume — a loop that never reads it re-runs completed waves anyway.

## 2. Ownership

Ownership is `files ∪ generates` for every task. Both keys are always written; a task with
nothing generated carries `generates: []`, and a header missing either key is invalid.
This union drives dispatch, the post-wave guard, and PR staging — one contract everywhere.

| Rule | Why |
|---|---|
| Parallel dispatch only when unions are disjoint | Two builders on the same union collide |
| Serialize tasks sharing any path in `generates` | Generated output has one writer |
| Serialize tasks whose `verify` touches shared state | Databases, fixture dirs, build caches, ports |

When serializing, run tasks in stable `id` order within the wave slot.

## 3. Dispatch

Create `<repoRoot>/.crew/<slug>/briefs/` if it is not there, then write the task's whole
section verbatim to `briefs/<id>.md` inside it.

For each task in the current wave, dispatch `crew-builder` by `subagent_type` alone. Its
model is pinned in `agents/crew-builder.md`; never pass a model parameter.

Pass: the brief path, the plan's `## Global Constraints` block, and the worktree path from
`state.json.git.worktreePath`. Nothing else, and never the plan path.

Never paste the section into the prompt. A task section carries real code, and everything in
a dispatch prompt stays in your context for the rest of the run and is re-read every turn.
Ten builders' worth of task text is ten copies you pay for on every later turn.

The brief is the whole spec, `**Interfaces**` included. That block is the only place a builder
learns the names its neighbours use, and it cannot see their tasks.

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

Snapshot before dispatching the wave, and again after every builder in it finishes.
`crew_snapshot` is defined in `skills/crew/references/plan-format.md`: a tree object of the
working tree, built through a throwaway index so the real one is untouched.

```bash
BEFORE=$(crew_snapshot)
#   … dispatch the wave …
AFTER=$(crew_snapshot)
git diff-tree -r --name-only -z "$BEFORE" "$AFTER"
```

That is the set of paths changed *in this wave only*. Never judge the whole dirty tree, because
earlier waves' work would read as unowned and stop the line falsely.

Never substitute `git status` for the snapshot. Status reports the state a path is in, not
whether it changed, so a file an earlier wave left at `M` stays at `M` when this wave's builder
edits it too and the guard sees nothing.

For each path changed this wave:

| Check | Action |
|---|---|
| Path is in some task's `files ∪ generates` for this wave | OK |
| Path is outside every union in this wave | Stop. Escalate. Never absorb silently |
| Builder's `Files` list omits a changed path | Stop. Omission reads as unowned |

## 5. Verify

After the guard passes, run the wave's `verify` commands yourself, in the worktree.

**Deduplicate first.** Collect the wave's `verify` strings into a set. Five tasks
declaring `npm test` is one run, not five — and every task sharing that command passes or
fails together on its single result.

**Run the distinct commands in parallel**, except any belonging to a task flagged in §2 as
touching shared state; those run serially, in `id` order. Everything else is independent
by the same ownership rule that let the builders run concurrently.

Read exit codes and output. A task passes only when its command was run by you and exited
zero.

| Builder verify | Orchestrator verify |
|---|---|
| Runs during implementation | Runs after the wave guard |
| Sees only that builder's changes | Sees the whole wave integrated |
| Informs the builder's fix loop | Is the wave's pass/fail |
| Reported in builder output | Never trusted as proof |

The re-run is not only distrust. A builder verified against a tree containing its changes
alone; by the end of the wave its siblings have landed too, and that is a different
question. It is also why verification is per wave rather than deferred to the end — a
failure has to be attributable to a wave for the circuit breaker to mean anything.

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
- Never proceed when your derived waves disagree with the plan's `## Wave list`.
- Never paste a task section into a dispatch prompt. Write the brief and pass its path.
- Never use `git status` as an ownership snapshot. Take a `crew_snapshot` and diff two trees.
- Never retry a task a third time after two failures.
- Never commit, push, or stage in this phase.
- Never advance past build without writing `state.json`.
