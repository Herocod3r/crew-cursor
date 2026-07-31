---
name: crew
description: Runs a goal through intake, research, design, and adversarial critique to an approved implementation plan. Use when starting a ticket, feature, bug, or refactor, or when resuming an in-flight crew run.
disable-model-invocation: true
---

# crew

A goal in, an approved implementation plan out. You are the architect. Subagents retrieve
and criticise; they do not design.

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
| 4 | `crew-critique` | verdict, findings, Gate 1 | `size: trivial` or `standard` |

Then **Gate 1**: present the plan and the verdict. Stop. Wait.

Build, review, PR, babysit, merge, and retro are not implemented. After Gate 1, hand
`plan.md` to whatever builds it.

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

`state.json` and `plan.md` live in `<repoRoot>/.crew/<slug>/`, where `repoRoot` is the
main checkout — the first `worktree` line of `git worktree list --porcelain`. State
outlives worktree teardown and eviction.

Never derive `repoRoot` from `git rev-parse --git-common-dir`. In a submodule that
resolves under `.git/modules/`, which writes state into Git internals.

```json
{
  "slug": "", "goal": "", "size": "trivial|standard|full",
  "phase": "intake|scout|design|critique|gate1|done",
  "gates": { "g1": false, "g2": false },
  "critique": { "verdict": null, "blocker": 0, "major": 0, "minor": 0, "round": 0 },
  "git": { "repoRoot": "", "worktreePath": "", "branch": "", "baseRef": "", "gitCommonDir": "" },
  "pr": null,
  "ticketRefs": [], "created": "", "updated": ""
}
```

Write `phase` on entering each phase, not on leaving it. A crash mid-phase must resume
into that phase, not past it.

`plan.md` frontmatter mirrors `slug`, `phase`, `size`, `gates`, `critique` so the human
sees state without opening JSON. `state.json` wins on conflict.

Read and write these with your own file tools. There is no helper script.

## plan.md schema

| Section | Contents |
|---|---|
| Goal | One paragraph. What done looks like. |
| Why | The problem. Evidence, with `file:line` or URL. |
| Decisions | Table: decision, rationale, what was rejected. |
| Assumptions | Unknowns accepted without closing, each human-approved. Empty is valid. |
| Approach | Prose plus a diagram. Pseudocode only where an interface is genuinely ambiguous. |
| Tasks | Fenced `json` block. The machine contract. |
| Verify | Commands proving the whole thing works. |
| Non-goals | Explicitly out of scope. |

```json
[
  { "id": "t1", "files": ["path/a"], "instruction": "", "verify": "", "needs": [] }
]
```

One owner per file across the whole array. `needs` yields waves by topological sort.

Never write a requirement-to-task coverage map. Never write code samples for every
interface. That combination is what made the predecessor's designs bloated and generic.

## Sizing

Set at intake. Default `standard`.

| Size | Runs | Criteria |
|---|---|---|
| trivial | 1, 3 | Syntactic only, all conditions below |
| standard | 1, 2, 3 | Default |
| full | 1, 2, 3, 4 | Any trigger below |

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

## Never

- Never write code before Gate 1. This skill produces a plan.
- Never create, move, or delete a worktree or branch. The human owns that lifecycle.
- Never design on a silent assumption. Close it, ask, or record it in `Assumptions`.
- Never claim a design is fact-grounded when a source it depends on returned anything but `ok`.
- Never let a subagent hold the design. You are the architect.
- Never advance a phase without writing `state.json`.
