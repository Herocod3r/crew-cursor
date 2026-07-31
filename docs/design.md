# crew v1 — design record

The plan crew was built from, covering the front half of the pipeline
(intake through Gate 1). Shaped by two rounds of adversarial critique.
Kept as a record of what was decided and what was rejected. Not live state.

## Goal

A Cursor plugin that guides work from a stated goal to an approved implementation plan:
restate the problem, establish facts, design with the human, break the design
adversarially, converge. Ship the front half first. Build, review, PR, babysit, merge,
retro come next.

## Why this exists

The predecessor (`~/Documents/projects/crew`, Claude Code) was slow, artifact-bloated, and
produced weak designs. Four causes, verified against its source — not one.

| Cause | Evidence | Symptom |
|---|---|---|
| Relayed dialogue | `skills/architect/SKILL.md:69` — architect returns exactly one of FACT_REQUEST, one question, or the design, per turn. A 5-question design costs 5 Opus dispatches through the orchestrator. | slow |
| Completeness pressure | `skills/architect/SKILL.md:58-60` — demands every requirement mapped in a coverage map, plus code samples for every interface and every non-trivial task. | bloated, generic designs |
| Same-family validation | `config/model_config.json` — `critique_backend: claude`, architect `opus`, critic `opus`. The plan was validated by its own model family. | weak designs survive critique |
| Stage and artifact count | 3 gates, 13 stages, `FACTS.md` + `DESIGN.md` + `REVIEW.md` + `state.json` + `evidence/`, worktree and workflow setup before any value. | slow, bloated |

Two things the predecessor got right and were wrongly blamed: scout fan-out was already
selective (`skills/scout-stage/SKILL.md:47` — "Do NOT fan out to all tools for every goal.
Pick the relevant subset"; 8 was a cap), and the architect could already ask questions.
Do not "fix" either.

## Decisions

| Decision | Rationale | Rejected |
|---|---|---|
| Main agent is the architect | Kills the per-question subagent round trip. Design dialogue is conversational, not relayed. | Architect subagent; competing architects + evaluator |
| Design skill forbids exhaustive completeness | Coverage maps and code-samples-for-everything caused the bloat. Pseudocode only where an interface is genuinely ambiguous. | Predecessor's complete-artifact contract |
| Critic is a different model family, always | Same-family validation was a real defect, not a theoretical one. | Opus critiquing Opus |
| Subagents only for retrieval, build, review | Isolation pays there. It costs elsewhere. | Agent-per-phase |
| Two files per run | One human-readable, one machine-readable. | 5 artifacts + evidence dir; zero artifacts |
| Selective scout | Carried over from the predecessor unchanged. It was correct. | Fixed fan-out |
| Critic on `gpt-5.5-extra-high-fast` | Newest generation, top effort, 1M context, different family. Fast serving infrastructure: same model, lower latency. Verified available. | Codex 5.3 xhigh (older gen); non-fast variant, which cost 128-169s per round in testing |
| Skills only, no commands | Cursor command arg-passing undocumented; Cursor migrates commands→skills. | `commands/*.md` |
| Two human gates | Go-ahead on plan, review before PR. | Gates after intake/scout/merge |
| crew never creates or deletes worktrees | The human runs crew from a worktree they own. Intake verifies, then stops if not. Removes the 25-cap risk and the create/teardown asymmetry outright. | Worktree at intake; crew-managed teardown at retro |

## Cursor constraints that shaped this

| Constraint | Consequence |
|---|---|
| No subagent `tools` allowlist, only `readonly: true` | Read-only is a boolean. Prompt `Do NOT` lists are defense-in-depth. |
| `/review`, `/babysit` are built-in skill names | All skills prefixed `crew-`. Entry point `crew` is free. |
| Command arg-passing undocumented | Everything is a skill with `disable-model-invocation: true`. |
| Skill `name` must equal folder name | Folder `skills/crew-intake/` ⇒ `name: crew-intake`. |
| Manifest path field replaces folder discovery | Omit `skills`/`agents`/`rules` from `plugin.json`. |
| Subagent nesting ceiling of two levels | Main → subagent only. |
| Worktree cap 25 machine-wide, auto-deleted | Not crew's concern — the human owns worktree lifecycle. State lives in the main checkout, so it survives eviction. |
| `sessionStart` absent in cloud agents | State rule must work without hooks. Hooks are a later upgrade. |

## Approach

Phase skills are runbooks the main agent executes, not subagent prompts.
`skills/crew/SKILL.md` is the entry point and the only place phase order and gates live.

State lives in `.crew/<slug>/state.json` at the main checkout root (git-ignored), with
`plan.md` beside it. No helper script — the agent reads and writes JSON directly.

`rules/crew-phase.mdc` (`alwaysApply: true`) handles recovery: if any
`.crew/*/state.json` has `phase != done`, load it and resume the named phase skill.

### Flow

```
/crew <goal|TICKET>          /crew  (no args) → board: list runs, pick one, resume
  │
  ├─ crew-intake     verify worktree → restate → ground → size → slug → state.json
  ├─ crew-scout      main reads code; selected external sources in one round
  ├─ crew-design     unknowns closed → questions one at a time → plan
  ├─ crew-critique   crew-critic (different family) → BLOCK|REVISE|PROCEED
  └─ GATE 1          present plan + verdict; wait
```

### Preconditions (checked at intake, before anything else)

crew never creates, moves, or deletes a worktree or a branch. The human owns that
lifecycle. crew verifies the context and records it — owning neither is not an excuse for
knowing neither, since later slices need a branch to diff and push.

```bash
git rev-parse --is-inside-work-tree     # must be true
git rev-parse --is-bare-repository      # must be false
git rev-parse --abbrev-ref HEAD         # must not be "HEAD" (detached)
git rev-parse --show-toplevel           # this checkout's root
git worktree list --porcelain           # first "worktree " line = main checkout
```

| Condition | Action |
|---|---|
| `git` exits non-zero (not a repo) | Stop. Report it. |
| Bare repository | Stop. No working tree to plan against. |
| Detached HEAD | Stop. Nothing to push later. |
| Main checkout, not a linked worktree | Say so, ask whether to continue here or stop. Never create one. |
| Linked worktree with a branch | Proceed. |

Record into `state.json.git`: `repoRoot` (main checkout, from the first `git worktree
list` entry), `worktreePath` (`--show-toplevel`), `branch`, `baseRef` (upstream, else
`origin/HEAD`), `gitCommonDir`.

`.crew/` lives at `repoRoot`, so state survives worktree teardown or eviction. Derive it
from `git worktree list`, never from `--git-common-dir` — in a submodule the common dir
resolves under `.git/modules/`, which would write state into Git internals.

### Run selection

Every entry point resolves to exactly one run. `/crew <goal>` starts a new one.
`/crew` with no argument lists runs with `phase != done` and asks which to resume.
Two or more active runs is never resolved by guessing. Malformed or unreadable
`state.json` is reported, never silently ignored.

### state.json

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

`plan.md` frontmatter mirrors `slug`, `phase`, `size`, `gates`, `critique`. state.json is
authoritative on conflict.

### plan.md output schema (the contract the build slice consumes)

Frozen now so the build slice does not have to reinterpret prose. Required sections:

| Section | Contents |
|---|---|
| Goal | One paragraph. What done looks like. |
| Why | The problem. Evidence, with `file:line` or URL. |
| Decisions | Table: decision, rationale, what was rejected. |
| Assumptions | Unknowns accepted without closing, each marked human-approved. Empty is valid. |
| Approach | Prose plus a diagram. Pseudocode **only** where an interface is genuinely ambiguous. |
| Tasks | A fenced `json` block. The machine contract. |
| Verify | Commands proving the whole thing works. |
| Non-goals | Explicitly out of scope. |

`Tasks` is the build slice's input, so it is parseable, not prose. Prose elsewhere is
presentation; this block is the source of truth:

```json
[
  { "id": "t1", "files": ["path/a"], "instruction": "", "verify": "", "needs": [] }
]
```

One owner per file across the whole array. `needs` yields the waves by topological sort;
never hand-number them. Never a requirement-to-task coverage map. Never code samples for
every interface — pseudocode only where an interface is genuinely ambiguous.

### Fact sufficiency

Before writing the plan, list every unknown the design depends on. Each must be closed by
targeted scouting, supplied by the human, or recorded in `Assumptions` as human-approved.
Never design on a silent assumption. Cap at two rounds, then surface the remaining gaps
and ask whether to proceed.

### Scout source contract

Every source returns `status: ok | unavailable | unauthenticated | empty` with findings.

| Status | Handling |
|---|---|
| `ok` | Use it. |
| `empty` | Record as a gap. Feeds fact sufficiency. |
| `unauthenticated` | Tell the human what to authenticate. Continue; record as a gap. |
| `unavailable` | Retry once, then record as a gap. |

Never present a design as fact-grounded when a source the design depends on returned
anything but `ok`.

### Sizing

Default is `standard`. Escalate to `full` on any trigger. Drop to `trivial` only when
every mechanical criterion holds and no trigger fires.

| Size | Runs | Criteria |
|---|---|---|
| trivial | intake → design → Gate 1 | Syntactic only, see below |
| standard | intake → scout → design → Gate 1 | Default |
| full | + critique | Any trigger below |

Triggers, any one of: money, auth, PII, data migration, public API, concurrency,
idempotency, background jobs, cross-service boundaries, feature flags, irreversible
user-visible behavior, production observability.

`trivial` is decided syntactically, never by judgment. All must hold: an explicit
single-file path is named; the change is docs, comments, typo, formatting, or test-only;
it touches no package manifest, lockfile, config, schema, or migration; it changes no
exported symbol; and no trigger word appears in the goal. Anything requiring a judgment
call about whether an interface changed is `standard`, by definition.

State the chosen size and its reason in one line. Do not ask. A wrong `full` costs time;
a wrong `trivial` ships unreviewed risk, so the asymmetry resolves toward `full`.

### Critic model fallback

Preferred `gpt-5.5-extra-high-fast`. If unavailable, any available top-effort model from a
family different to the main agent's. If none exists, warn the human explicitly before
running a same-family critique — never do it silently.

### Critique convergence

Verdict is `BLOCK`, `REVISE`, or `PROCEED` with counts. The main agent resolves findings
and re-critiques only while blockers remain, capped at two rounds. After two, present
the unresolved findings at Gate 1 and let the human decide. Disagreement with the critic
is allowed and must be recorded in `Decisions` with a reason.

The critic must also return **Alternative not considered**: the strongest approach the
plan never evaluated, and whether it is better. A critic reading the plan is anchored to
the decisions the plan exposed, so it will not otherwise surface an architecture the
author never wrote down. This is the cheap half of a fresh design pass. It is not a full
substitute — see `Accepted risks`.

## Accepted risks

Knowingly unfixed. Revisit if either bites.

| Risk | Why accepted | Trigger to revisit |
|---|---|---|
| No fresh design pass. The critic is anchored to the plan it reads, so an architecture the main agent never considered can survive unexamined. | A second design pass costs a full dispatch and reintroduces the latency this plan exists to remove. The critic's `Alternative not considered` section buys most of the value for free. | A run where the critic passes a plan and the approach turns out wrong at build time. |
| Phase enforcement is one `alwaysApply` rule with no preflight or helper. A model that ignores it can skip a phase silently. | Hooks are the only stronger mechanism and they do not fire in cloud agents. Adding a state helper reintroduces the machinery that made the predecessor feel bloated. | A run that skips a phase or resumes into the wrong one. Then add `sessionStart` context injection and `stop` advancement. |

## Files

| File | Wave | Contents |
|---|---|---|
| `.cursor-plugin/plugin.json` | 1 | name `crew`, version, description, author. Nothing else. |
| `.gitignore` | 1 | `.crew/` |
| `skills/crew/SKILL.md` | 1 | Entry runbook, run selection, phase order, gates, state schema |
| `rules/crew-phase.mdc` | 2 | `alwaysApply: true`. Resume-from-state. Under 20 lines. |
| `skills/crew-intake/SKILL.md` | 2 | Worktree precondition, restate, ground, size, slug, seed state |
| `skills/crew-scout/SKILL.md` | 2 | Source selection, dispatch, status contract, facts format |
| `skills/crew-design/SKILL.md` | 2 | Fact sufficiency, question discipline, plan schema, anti-bloat rules |
| `skills/crew-critique/SKILL.md` | 2 | Dispatch critic, severity contract, convergence, Gate 1 |
| `agents/crew-retriever.md` | 2 | `composer-2.5-fast`, `readonly: true`. Named apart from the `crew-scout` skill so `/crew-scout` is unambiguous — same split as `crew-critique` / `crew-critic`. |
| `agents/crew-critic.md` | 2 | `gpt-5.5-extra-high-fast`, `readonly: true` |
| `README.md` | 3 | What it is, install, flow, model table, phase status |

Wave 1 fixes the contract every other file references. Wave 2 is parallel — separate
files, no shared state. Wave 3 documents what exists.

## Conventions for every file

Imperative, terse, no hedging, no emoji. Decision before rationale. Name what was
rejected. Tables and diagrams over prose. Categorical `Never` / `Do NOT` lists.
SKILL.md frontmatter is `name`, `description`, `disable-model-invocation` only.
Bodies under 200 lines.

**Only the `crew` entry skill sets `disable-model-invocation: true`.** Phase skills must
stay model-invocable or the chain breaks: a skill with model-invocation disabled loads
only when the human types `/name`, so `crew` could never load `crew-intake`. Verified
empirically — with the flag on all five, `cursor-agent` discovered the two subagents and
zero skills.

Skill names and agent names share one slash namespace. Never reuse a name across the two:
skill `crew-scout` / agent `crew-retriever`, skill `crew-critique` / agent `crew-critic`.

## Verify

- `.cursor-plugin/plugin.json` parses as JSON
- Every `skills/*/SKILL.md` frontmatter `name` equals its parent folder name
- Every `agents/*.md` has `name`, `description`, `model`, `readonly`
- Every `model` value appears in `cursor-agent --list-models`
- No skill name collides with a built-in Cursor skill
- Symlink to `~/.cursor/plugins/local/crew`, reload, `/crew` resolves
- End to end: `/crew` on a real ticket reaches Gate 1 with a plan matching the schema

## Non-goals for v1

Build, review, PR, babysit, merge, retro. Hooks. Worktree lifecycle — the human owns it,
in every slice, including retro cleanup. Multi-repo runs. Cloud agents. Ticket creation.
Anything that writes to a remote.
