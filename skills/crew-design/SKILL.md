---
name: crew-design
description: Designs the solution with the human. Closes unknowns, asks questions one at a time, then writes plan.md to the frozen schema. Use as phase 3 of a crew run.
---

# crew-design

Phase 3. You design. Not a subagent — you, in this conversation, with the human.

The predecessor relayed each design question through a fresh Opus dispatch. Five
questions cost five round trips and the answers arrived stripped of context. That is the
latency this phase exists to remove.

## 1. Close the unknowns

List every unknown the design depends on. For each, exactly one of:

| Resolution | When |
|---|---|
| Close it | You can find the answer. Go find it. |
| Ask the human | They know it and you cannot look it up. |
| Record it | Genuinely unknowable now. Goes in `Assumptions`, human-approved. |

Never design on a silent assumption. Cap at two rounds of closing; then surface what
remains and ask whether to proceed.

## 2. Ask

One question at a time. Wait for the answer before the next. Never batch.

Prefer multiple choice with your recommendation first. Ask about purpose, constraints,
and what success looks like — not about things you could determine by reading the code.

Stop asking when you can write the plan. More than five questions without a plan means
you are avoiding a decision. Make it, state it, let the critic attack it.

## 3. Propose

Two or three approaches with trade-offs, recommendation first, before settling. Say what
you rejected and why. A design with no rejected alternatives was not designed, it was
assumed.

Bias to the simplest thing that meets the goal. One coherent solution, not a
configurable framework. Prefer the boring pattern already in this codebase over the
better pattern that is not.

## 4. Write plan.md

To the schema in the `crew` skill, at `<repoRoot>/.crew/<slug>/plan.md`.

`Tasks` is one `### tN` section per task. Each opens with a fenced `yaml` header, then
`**Interfaces**`, then steps as checkboxes. The format is in
`skills/crew/references/plan-format.md`. Read it before writing your first task.

Write the steps so the builder types rather than decides. A step whose deliverable is code
shows the code. A step that runs something gives the command and what its output should say.
Test-first, so that the step before the change is the one that watches the check fail.

`Approach` is a diagram and a file map, and it never describes what a task does. Behaviour
belongs to the task that implements it, once. Two copies drift, and the builders follow the
copy nobody proofread.

`generates` lists files the task produces but does not author — lockfiles, generated code,
snapshots. Ownership is `files ∪ generates`, and five later readers key on that union, so a
task that will touch a lockfile must say so or the build stops on an unowned change.

One owner per path across the whole plan, not per wave. Derive `## Wave list` from `needs` by
topological sort; the build phase derives it again and stops if the two disagree. Every task
carries a real verify command — a task with nothing to run is a task nobody can check.

Scope that command to the task. It runs the tests covering the task's own `files`
(`pytest tests/x/test_y.py::test_z`), never the whole suite (`pytest`). The suite belongs in
the plan's `Verify`, which runs once.

On a large codebase this is the difference between a build measured in minutes and one
measured in hours, because a broad command is not run once. Every builder in the wave runs
its own task's `verify` while implementing, and that is not deduplicated — five tasks
declaring `pytest` is five full suites running at the same time, contending for the same
CPU, database and ports, so each is slower than it would be alone. Add up to two retries
each, the orchestrator's own re-run after the wave, and one more per fix in review. Narrow
commands make every one of those multiplications cheap.

## 5. Write the interfaces

Each builder gets one task and cannot see the others. Where tasks hand off, name the seam.

`Produces` is every signature a later task will call: exact name, parameter and return
types. `Consumes` is what this task calls from an earlier one, copied verbatim from that
task's `Produces` — copied, not paraphrased, because the whole value is that the two strings
are identical.

Signatures only, never bodies. The steps are where code goes; this is the boundary between
tasks, and nothing else belongs in it. A task at a leaf with no callers has an empty
`Produces`, and that is normal.

A `Consumes` entry whose producer is not in `needs` is a dependency bug, not an interface
one — the two tasks would land in the same wave and run in parallel. Fix `needs`.

## 6. Check the plan against itself

Run this before every gate, and again after any critique round that edits the plan. It is a
checklist you run yourself, not a subagent dispatch.

| Check | Failure it catches |
|---|---|
| Every task's `yaml` header parses | A quoting slip in `verify` should stop this phase, not the build. |
| The header count equals the `### tN` count under `## Tasks` | A `yaml` block shown as an example parses as a task nobody meant to schedule. |
| Every `Consumes` string appears verbatim in some `Produces` | `clearLayers()` in one task, `clearFullLayers()` in another. Both builders are right; the code does not compile. |
| No symbol appears in two tasks' `Produces` | Two builders define the same thing in parallel and the second overwrites the first. |
| Every `Consumes` has its producer in `needs` | The two tasks land in the same wave and race. |
| No path appears in two tasks' `files ∪ generates` | Two builders write one file at the same time. |
| `## Wave list` matches a topological sort of `needs` | A `needs` edge for setup order or shared state has no interface to check it. |
| No step contains anything from the never-write list in `references/plan-format.md` | The builder is handed "handle edge cases" and invents a design. |
| Every task's `verify` can actually fail | A check that passes on the unchanged tree verifies nothing. |
| No task's `verify` runs the whole suite | The suite runs once per task per wave instead of once, and the build takes hours. |

Fix what you find inline and move on. No re-review.

The last two are not hypothetical. On crew's own v2 plan the merge conditions were made safe
in the `Approach` prose while the task that implemented them still carried the unsafe
predicate, and only a second critique round caught it. That is why behaviour is now written
once: there is no second copy to fix, and no second copy to forget.

## Anti-bloat

The predecessor's architect was told to produce a complete artifact: every requirement
mapped in a coverage map, code samples for every interface and every non-trivial task.
That pressure is what made its designs long and generic. Do not reproduce it.

- Never write a requirement-to-task coverage map.
- Never let `Approach` describe what a task does. A diagram and a file map, nothing else.
- Never restate the goal in three sections.
- Never pad `Decisions` with choices nobody would question.
- Length is not thoroughness. A plan whose prose fits on a screen and whose tasks leave nothing to invent beats four pages that hedge.

Code in a step is not bloat, and its absence is a failure. A step whose deliverable is code
and which shows no code hands the decision to a builder that cannot ask you what you meant.
The English describing a change is usually longer than the change.

## Next

Set `phase` to `critique` when size is `full`, otherwise `gate1`.

Load `crew-critique` when size is `full`. Otherwise go straight to Gate 1 as defined in
the `crew` skill.
