---
name: crew-build
description: Executes the task sections of plan.md wave by wave via crew-builder subagents, with ownership guards and per-wave verification. Use as phase 5 of a crew run.
---

# crew-build

Phase 5. Gate 1 is approved. You orchestrate; builders execute.

Read every `### tN` under `## Tasks` in `<repoRoot>/.crew/<slug>/plan.md` and parse each
one's `yaml` header (first fence after the heading; rest in
`skills/crew/references/plan-format.md`). Set `phase` to `build` in `state.json`. Write state
on entry, not on exit — a crash mid-wave must resume into build, not skip it.

Initialise `waveCursor` to `0` **only when it is absent**. A resumed run continues from the
saved cursor. Resetting it on entry re-runs completed waves.

## 1. Compute waves

Waves come from `needs` by topological sort. Never hand-number waves in the plan or here.

```
needs: []           → wave 0
needs: ["t1"]       → after t1 completes
needs: ["t1","t2"]  → after both complete
```

Each wave is every task whose `needs` are satisfied by earlier waves, ordered and indexed
from `0`. A wave is done only when every task in it passed verify — no per-task built flag.

Compare what you derived against the plan's `## Wave list`. On any disagreement, stop and show
both before a builder runs.

**Consume `waveCursor`.** Skip every wave with an index below it, and write the new value
after each wave passes its guard and verify.

## 2. Ownership

Ownership is `files ∪ generates` for every task. Optional `generates` defaults to empty.
This union drives dispatch, the post-wave guard, and PR staging.

| Rule | Why |
|---|---|
| Parallel dispatch only when `files ∪ generates` unions are disjoint and every §2 serialization rule allows it | Overlapping unions collide; disjoint unions alone do not prevent verify contention |
| Serialize tasks sharing any path in `generates` | Generated output has one writer |
| Serialize tasks whose `verify` touches shared state | Databases, fixture dirs, build caches, ports |
| Serialize tasks whose `verify` spawns workers or saturates the CPU pool | Two xdist-style suites contend for the same cores |

When serializing, run tasks in stable `id` order. When resource use is unclear, serialize
conservatively.

## 3. Dispatch

Write the task's whole section verbatim to `<repoRoot>/.crew/<slug>/briefs/<id>.md` first.

For each task in the current wave, dispatch `crew-builder` by `subagent_type` alone. Its
model is pinned in `agents/crew-builder.md`; never pass a model parameter.

Pass: the brief path, the plan's `## Global Constraints` block, and the worktree path from
`state.json.git.worktreePath`. Nothing else, and never the plan path.

Never paste the section into the prompt — it stays in your context for the rest of the run.

The brief is the whole spec, `**Interfaces**` included. Parallel only when every §2 rule
allows it. One builder per task. Never batch unlike tasks into one dispatch.

```
Status:  DONE | DONE_WITH_CONCERNS | BLOCKED
Files:   every path changed, including generated
Verify:  command, exit code, relevant output
Concerns: omit if none
Blocked: omit if none
```

A builder verify report is a claim. §5 validates each report and decides whether a rerun is required.

## 4. Post-wave guard

Before dispatching a wave:

```bash
git status --porcelain=v1 -z
```

Never the plain form: it writes a rename as `old -> new` in one entry and quotes any path
outside ASCII. Split on NUL, drop the two status columns and the space, and for a rename take
both paths. Full rules in `skills/crew/references/plan-format.md`.

Save the snapshot. After every builder in the wave finishes, snapshot again.

Diff the two snapshots to paths changed *in this wave only*. Do not compare the whole
dirty tree — earlier waves' work would read as unowned and stop the line falsely.

| Check | Action |
|---|---|
| Path is in some task's `files ∪ generates` for this wave | OK |
| Path is outside every union in this wave | Stop. Escalate. Never absorb silently |
| Builder's `Files` list omits a changed path | Stop. Omission reads as unowned |

## 5. Verify

Every builder runs its narrow header `verify` during implementation. That report is the
builder's proof of its isolated change.

After the guard passes, validate each builder report contains:

1. the exact header `verify` command,
2. exit code zero,
3. relevant output showing the command completed.

A **complete verify report** satisfies a **single-task wave** containing exactly one task.
Rerun that task's command when proof is missing, non-zero, inconsistent, or the builder
reports `DONE_WITH_CONCERNS`. For a **multi-task wave**, deduplicate header `verify` strings
and run them after the guard — builder reports prove isolated changes; orchestrator runs prove
the integrated wave and retain circuit breaker attribution.

**Deduplicate first.** Collect the wave's `verify` strings into a set. Five tasks
declaring `npm test` is one run, not five.

**Run the distinct commands in parallel**, except any belonging to a task §2 requires
serializing — shared state, worker-spawning, or CPU pool saturation; those run serially, in
`id` order. Never run two xdist-style suites concurrently.

| Builder verify | Orchestrator verify |
|---|---|
| Runs during implementation | Runs after the wave guard |
| Sees only that builder's changes | Sees the whole wave integrated |
| A complete report proves a single-task wave | Skipped for a complete single-task report |

## 6. Circuit breaker

Track failures per task and per run.

| Condition | Action |
|---|---|
| Same task fails twice | Stop the line. Surface to human. |
| Three failures across the run (any tasks) | Stop the line. Surface to human. |

A failure is: builder `BLOCKED`, a builder-reported verify exit non-zero, post-wave guard
stop, verify exit non-zero after you ran it, or a single-task fallback rerun failing. Count a
builder-reported non-zero even when a later fallback rerun passes. A complete zero-exit report
for a single-task wave is not a failure. `DONE_WITH_CONCERNS` on a single-task wave triggers
the fallback rerun; on a multi-task wave it counts as success unless integrated verify fails.

One task attempt contributes at most one circuit-breaker failure event — overlapping symptoms
from the same attempt do not double-count.

Never retry a third time on the same task. Record breaker state in `state.json`.

## 7. Advance

Increment `waveCursor` after each wave passes guard and verify. Write `state.json`.

When all tasks are built, set `phase` to `review`. Load `crew-review`.

## Never

- Never dispatch parallel builders whose `files ∪ generates` overlap.
- Never parallelize tasks that share a `generates` path.
- Never parallelize tasks whose `verify` commands touch shared state.
- Never parallelize tasks whose `verify` commands spawn workers or saturate the CPU pool.
- Never run two xdist-style suites concurrently.
- Never trust an incomplete builder verify report as the wave's verification.
- Never compare the full dirty tree in the post-wave guard — only this wave's delta.
- Never absorb a changed file outside the wave's unions.
- Never hand-number waves instead of deriving them from `needs`.
- Never proceed when your derived waves disagree with the plan's `## Wave list`.
- Never paste a task section into a dispatch prompt. Write the brief and pass its path.
- Never read the tree with plain `git status --porcelain`.
- Never retry a task a third time after two failures.
- Never commit, push, or stage in this phase.
- Never advance past build without writing `state.json`.
