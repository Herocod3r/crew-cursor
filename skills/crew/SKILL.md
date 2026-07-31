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

`state.json` and `plan.md` live in `<repoRoot>/.crew/<slug>/`, where `repoRoot` is the
main checkout — the first `worktree` line of `git worktree list --porcelain`. State
outlives worktree teardown and eviction.

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
| Decisions | Table: decision, rationale, what was rejected. |
| Assumptions | Unknowns accepted without closing, each human-approved. Empty is valid. |
| Approach | Prose plus a diagram. Pseudocode only where an interface is genuinely ambiguous. |
| Tasks | Fenced `json` block. The machine contract. |
| Verify | Commands proving the whole thing works. |
| Non-goals | Explicitly out of scope. |

```json
[
  { "id": "t1", "files": ["path/a"], "generates": [], "instruction": "", "verify": "", "needs": [] }
]
```

| Field | Meaning |
|---|---|
| `files` | Files the task authors. |
| `generates` | Files it produces but does not author — lockfiles, generated code, snapshots. Optional, defaults to empty. |

Ownership is `files ∪ generates`, and it drives everything: parallel dispatch, the
post-wave changed-file guard, and PR staging. One owner per union across the whole array.
`needs` yields waves by topological sort.

Never write a requirement-to-task coverage map. Never write code samples for every
interface. That combination is what made the predecessor's designs bloated and generic.

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
- Anything the circuit breaker stopped
- Anything review raised that two fix rounds did not close

Set `gates.g2` only after the human says go. Same rule as Gate 1: silence is not approval.

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
