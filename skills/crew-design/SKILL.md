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

`Tasks` is a fenced `json` block, not prose. It is what the build phase consumes.

```json
[
  { "id": "t1", "files": ["path/a"], "generates": [],
    "interfaces": { "produces": [], "consumes": [] },
    "instruction": "", "verify": "", "needs": [] }
]
```

`generates` lists files the task produces but does not author — lockfiles, generated code,
snapshots. Optional, defaults to empty. Ownership is `files ∪ generates`, and the build and
PR phases key on that union, so a task that will touch a lockfile must say so here or the
build stops on an unowned change.

One owner per union across the array. `needs` yields waves by topological sort. Every task
carries a real verify command — a task with nothing to run is a task nobody can check.

## 5. Write the interfaces

Each builder gets one task and cannot see the others. Where tasks hand off, name the seam.

`produces` is every signature a later task will call: exact name, parameter and return
types. `consumes` is what this task calls from an earlier one, copied verbatim from that
task's `produces` — copied, not paraphrased, because the whole value is that the two strings
are identical.

Signatures only, never bodies. This is not licence to write code samples; it is the boundary
between tasks, and nothing else belongs in it. A task at a leaf with no callers has an empty
`produces`, and that is normal.

A `consumes` entry whose producer is not in `needs` is a dependency bug, not an interface
one — the two tasks would land in the same wave and run in parallel. Fix `needs`.

## 6. Check the plan against itself

Run this before every gate, and again after any critique round that edits the plan. It is a
checklist you run yourself, not a subagent dispatch.

| Check | Failure it catches |
|---|---|
| Every `consumes` string appears verbatim in some `produces` | `clearLayers()` in one task, `clearFullLayers()` in another. Both builders are right; the code does not compile. |
| No symbol appears in two tasks' `produces` | Two builders define the same thing in parallel and the second overwrites the first. |
| Every `consumes` has its producer in `needs` | The two tasks land in the same wave and race. |
| Names in the prose match names in `Tasks` | The human approves one design and the builders execute another. |
| Every task's `verify` can actually fail | A check that passes on the unchanged tree verifies nothing. |

Fix what you find inline and move on. No re-review.

The last two are not hypothetical. On crew's own v2 plan the merge conditions were made safe
in the prose while `Tasks` still carried the unsafe predicate, and only a second critique
round caught it — the builders follow `Tasks`, so the prose fix had changed nothing. Revise
both in the same edit, always.

## Anti-bloat

The predecessor's architect was told to produce a complete artifact: every requirement
mapped in a coverage map, code samples for every interface and every non-trivial task.
That pressure is what made its designs long and generic. Do not reproduce it.

- Never write a requirement-to-task coverage map.
- Never write code samples for every interface. Pseudocode only where an interface is genuinely ambiguous.
- Never restate the goal in three sections.
- Never pad `Decisions` with choices nobody would question.
- Length is not thoroughness. A plan that fits on a screen and is right beats four pages that hedge.

## Next

Set `phase` to `critique` when size is `full`, otherwise `gate1`.

Load `crew-critique` when size is `full`. Otherwise go straight to Gate 1 as defined in
the `crew` skill.
