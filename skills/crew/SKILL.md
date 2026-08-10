---
name: crew
description: Runs a goal through intake, research, design, adversarial critique, build, review, PR and merge. Use when starting a ticket, feature, bug, or refactor, or when resuming an in-flight crew run.
disable-model-invocation: true
---

# crew

A goal in, merged code out. You are the architect. Subagents retrieve, build, and
criticise; they do not design.

```
/crew <goal|TICKET>          new run
/crew                        list active runs, resume one
```

## Phases

Run in order. Each phase is a skill. Load it and follow it.

| # | Skill | Produces | Skipped when |
|---|---|---|---|
| 1 | `crew-intake` | preconditions verified, `state.json` seeded | never |
| 2 | `crew-scout` | facts, with per-source status | `size: trivial` |
| 3 | `crew-design` | `plan.md` matching the schema below | never |
| 4 | `crew-critique` | verdict and findings | `size: trivial` or `standard` |
| — | **Gate 1** | your go-ahead on the plan | never |
| 5 | `crew-build` | the code, verified wave by wave | never |
| 6 | `crew-review` | three lanes coalesced, findings fixed | never |
| — | **Gate 2** | your go-ahead on the diff | never |
| 7 | `crew-pr` | a PR, ready for review | never |
| 8 | `crew-babysit` | CI green, threads handled, merged | never |
| 9 | `crew-retro` | learnings routed, cleanup reported | never |

Two gates, both human, neither skippable. Everything between them is autonomous.

## Run selection

Resolve to exactly one run before doing anything.

| Situation | Action |
|---|---|
| `/crew <goal>` | New run. Derive slug, seed state. |
| `/crew`, one run with `phase != done` | Resume it. Say which. |
| `/crew`, several active runs | List slug, goal, phase. Ask which. |
| `/crew`, no active runs | Say so. Ask for a goal. |
| `state.json` unreadable or malformed | Report the path and the error. Stop. |

Never guess which run is meant. Never silently skip a state file you failed to parse.

## State

`state.json`, `plan.md` and `briefs/<id>.md` live in `<repoRoot>/.crew/<slug>/`, where
`repoRoot` is the main checkout, the first `worktree` line of
`git worktree list --porcelain`. State outlives worktree teardown and eviction.

`briefs/<id>.md` holds one task section, copied verbatim at dispatch and read by one builder.
A builder never opens `plan.md`.

Never derive `repoRoot` from `git rev-parse --git-common-dir`. In a submodule that
resolves under `.git/modules/`, which writes state into Git internals.

```json
{
  "slug": "", "goal": "", "size": "trivial|standard|full",
  "phase": "intake|scout|design|critique|gate1|build|review|gate2|pr|babysit|retro|done",
  "gates": { "g1": false, "g2": false },
  "critique": { "verdict": null, "blocker": 0, "major": 0, "minor": 0, "round": 0 },
  "waveCursor": 0,
  "breaker": { "taskFails": {}, "runFails": 0 },
  "reviewVerify": { "status": "pending|running|pass|fail|environment_gap", "evidence": [] },
  "git": { "repoRoot": "", "worktreePath": "", "branch": "", "baseRef": "", "gitCommonDir": "" },
  "pr": { "url": null, "number": null, "headSha": null, "merged": false },
  "ticketRefs": [], "created": "", "updated": ""
}
```

Write `phase` on entering each phase, not on leaving it. A crash mid-phase must resume
into that phase, not past it.

`plan.md` frontmatter mirrors `slug`, `phase`, `size`, `gates`, `critique`, and `pr` so
the human sees state without opening JSON. `state.json` wins on conflict.

Read and write these with your own file tools. There is no helper script.

## plan.md schema

| Section | Contents |
|---|---|
| Goal | One paragraph. What done looks like. |
| Why | The problem. Evidence, with `file:line` or URL. |
| Architecture | Two or three sentences on the approach. |
| Tech Stack | What it is built on. One line. |
| Decisions | Table: decision, rationale, what was rejected. |
| Assumptions | Unknowns accepted without closing, each human-approved. Empty is valid. |
| Global Constraints | Project-wide requirements, one line each, exact values verbatim. Every task's requirements implicitly include this. |
| Approach | A diagram and a file map: what each file is responsible for. Never a description of what a task does. |
| Tasks | One `### tN` section per task. Format in `references/plan-format.md`. |
| Wave list | Derived from every task's `needs` by topological sort. |
| Verify | Whole-run proof. Each fenced `bash` block is one exact command, deduplicated and run once after review fixes from the worktree root as `bash -euo pipefail -c "$block"`. Prose after the blocks is manual checks, run once. The review phase runs these once before Gate 2. |
| Non-goals | Explicitly out of scope. |

Each task section opens with a fenced `yaml` header carrying `id`, `needs`, `files`,
`generates` and `verify`, then `**Interfaces**` and the steps. Ownership is `files ∪
generates`, and it drives everything: parallel dispatch, the post-wave changed-file guard, PR
staging, the review fix loop and every push babysit makes. One owner per path across the whole
plan, not per wave.

`Interfaces` is the contract between tasks, and it holds two invariants: every `Consumes`
string appears verbatim in the `Produces` of a task reachable through `needs`, and no symbol
is produced twice. Both are checkable, which is the point — a builder is dispatched with one
task and cannot see its neighbours, so a name written two ways in the plan becomes a name
written two ways in the code.

Behaviour is described once, in the task that implements it. Prose that restates a task is the
defect this format exists to remove: the two copies drift, and the builders follow the one
nobody proofread. Never write a requirement-to-task coverage map either.

## Sizing

Set at intake. Default `standard`.

Size gates only the research and critique phases. Everything from build onward always
runs — a run ends at merged code regardless of size.

| Size | Skips | Criteria |
|---|---|---|
| trivial | scout and critique | Syntactic only, all conditions below |
| standard | critique | Default |
| full | nothing | Any trigger below |

**Triggers**, any one: money, auth, PII, data migration, public API, concurrency,
idempotency, background jobs, cross-service boundaries, feature flags, irreversible
user-visible behavior, production observability.

**`trivial`** requires all of: an explicit single-file path is named; the change is docs,
comments, typo, formatting, or test-only; it touches no package manifest, lockfile,
config, schema, or migration; it changes no exported symbol; no trigger word appears in
the goal. Anything needing a judgment call about whether an interface changed is
`standard`, by definition.

State the size and its reason in one line. Do not ask. A wrong `full` costs time; a wrong
`trivial` ships unreviewed risk.

## Gate 1

Present, then stop:

- The plan, or its path
- The critique verdict and counts, if the size ran critique
- Findings you rejected, and why
- Anything in `Assumptions`

Set `gates.g1` only after the human says go. Never infer approval from silence, from a
question, or from a comment about something else.

On approval: set `phase` to `build`. Load and follow `crew-build`.

## Gate 2

After review, before the PR. Present, then stop:

- What changed, by file
- Coalesced findings: what was fixed, what was not, and why
- Whole-run verification from `reviewVerify.evidence` — see `crew-review` §4
- Anything the circuit breaker stopped
- Anything review raised that two fix rounds did not close

Set `gates.g2` only after the human says go. Same rule as Gate 1: silence is not approval.
Cannot approve while `reviewVerify.status` is `pending`, `running`, or `fail`; `environment_gap`
requires explicit acceptance.

Everything after Gate 2 is outward-facing — a push, a PR, a merge. That is what the gate
is for.

## Never

- Never write code before Gate 1.
- Never push, open a PR, or merge before Gate 2.
- Never merge a commit no approving review points at.
- Never resolve a review thread. Only the reviewer closes their own objection.
- Never create, move, or delete a worktree or branch. The human owns that lifecycle.
- Never design on a silent assumption. Close it, ask, or record it in `Assumptions`.
- Never claim a design is fact-grounded when a source it depends on returned anything but `ok`.
- Never let a subagent hold the design. You are the architect.
- Never advance a phase without writing `state.json`.
