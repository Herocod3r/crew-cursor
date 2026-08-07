# Making crew's plans smaller

Facts checked at `ecf36cc`. Line numbers in the `archimedes` repo are read from `origin/main`
at `2df6e14a`, which is after PR #1835 merged. That repo's local working tree is 123 commits
behind and was not used.

## Summary

`skills/crew/SKILL.md:9` says a goal in, merged code out. The plans crew produces on the way
are larger than the goal needs, and the cause is how the design agent frames the problem
rather than any gap in what it knows about the codebase.

Three changes. Intake reduces the goal to one sentence naming what must become true, before
any code is read. Design pays a sentence whenever it builds something new where something
close already exists. And task boundaries follow a rule, so nine builders stop doing four
builders' work.

An earlier draft proposed nineteen changes across six files, including a new subagent and a
new plan section for inventorying the codebase. Appendix B records why both were cut.

## Problem

In the user's words: the agent using crew was doing way too much, making designs more
complex when there was often an easier implementation.

The run that prompted this is `archmds-745-model-flag` in the `archimedes` repo, a
`size: full` run that reached a merged PR. Its goal was one sentence of work: evaluate a
Tuner flag against an actor when choosing a model. Parsing the `Tasks` block out of its
`plan.md` and counting gives nine tasks owning thirty distinct files.

Three kinds of excess showed up.

The first is adjacent problems becoming tasks. The plan's `Why` section lists five things
that break once the flag turns on: `max_tokens` differing per model, Opus 5 rejecting
`temperature`, cost mis-tiering to Sonnet, metrics tagging `unknown`, and LiteLLM's Nova
metadata omitting `supports_tool_choice`. Each became a task. Only the first blocked the
goal.

The second is a new mechanism proposed next to an existing one. `t6` introduces
`route_actor(...)`, a third identity builder, while `flags.py` already has `user_actor` and
`build_actor`. `t1` introduces `model_capabilities.py`, an owned per-model metadata table,
while `cost.py` already has `_PRICING_TIERS` at line 51 feeding `_resolve_tier` at line 63.

Neither shipped. Comparing the plan against `origin/main` after the PR merged shows what the
human replaced them with:

| The plan proposed | What merged |
|---|---|
| `route_actor(...)`, a third identity builder | Cut. `set_actor_for_build`, `set_actor_for_user` and `set_actor_for_slack` (`flags.py:94-104`) set an ambient actor built from the existing `user_actor` (`:69`) and `build_actor` (`:123`) |
| `model_capabilities.py`, a new owned metadata table | Cut. `_PRICING_TIERS` gained one row, `nova-2-lite` (`cost.py:67`) |
| `t5`, a LiteLLM tool-choice patch | Cut |
| `t9`, actor plumbing on the API path | Cut |
| `model_routes.py`, the route table itself | Shipped |

One of the plan's new mechanisms survived. The rest were either unnecessary or replaced by
extending something that already existed, and the extension was usually one line. The design
was not wrong. It was several times larger than the thing that worked, and the difference was
found during build rather than at Gate 1.

The third is task boundaries that split work nobody can review separately. `t4` changes one
metrics enum. `t8` writes `.env.example` and a guide. Neither is a deliverable anyone would
approve or reject on its own, and each cost a full builder dispatch.

### It is not a knowledge gap

The obvious diagnosis is that the agent did not know `build_actor` was there. That is wrong,
and the plan says so itself. Under `Why`, alongside the defects, it carries an inventory of
what already works:

> What is already fine: the Anthropic SDK is fully retired (zero `.messages.create(` in
> `archimedes/`), all 28 LLM call sites go through `complete()`, and prefix routing works
> (`resolve_model_id`, `model_config.py:204-213`). Nothing resolves a model inside
> `archimedes/workflows/`, so a flag read at resolution time cannot break Temporal replay.

`crew-scout` did its job. It read the code (`skills/crew-scout/SKILL.md:10-15`) and recorded
what it found with citations (`:51-55`). Every entry in that paragraph is real. Not one of
them is a mechanism the plan went on to duplicate.

The reason is that the inventory is downstream of the framing. "What is already fine" answers
*does my approach work here*, which is a question you can only ask once you have an approach.
It never answers *does this already exist*. That plan's `Goal` opens with "enable Opus 5 and
Nova 2 Lite behind a targeted model-route flag," which is a solution, and its frontmatter
carries three tickets. Against that framing, `build_actor` is genuinely not relevant. Against
"model choice must be able to depend on who the actor is," it is the first thing you find.

So adding a section for the agent to list what exists would produce a tidier version of a
paragraph that was already there and already did not help. The fix has to be upstream of it.

### Why the existing rules did not stop it

Crew already holds the right position in prose, in three places.
`skills/crew-design/SKILL.md:44-46` says to bias to the simplest thing that meets the goal
and to prefer the boring pattern already in the codebase. `agents/crew-builder.md:26` says
not to add abstractions the task did not ask for. `agents/crew-conformance.md:39-41` says
over-building is a finding rather than initiative. All three were in effect during that run.
None fired, which is why this document does not propose more of them.

The human caught every instance in that session and cut them. What they lacked was timing:
the catch happened during build, with the code written, rather than at Gate 1, where the plan
is approved and no code exists.

## Goals

1. Every run names, in one sentence, what must become true, before any code is read. That
   sentence excludes something the stated goal implies.
2. Introducing something new when something close already exists costs a written reason
   naming the property the existing thing lacks.
3. A task is a deliverable a reviewer could reject on its own.

## Non-goals

1. Plan readability. The same run produced a plan the author could not parse, with a dense
   eight-line `Goal` and 1,746 words of task instruction against 1,687 words of prose. Real
   complaint, different one. It gets its own document.
2. A reviewer that checks scope independently. Deferred with a trigger, below.
3. Splitting a run that bundles several concerns. Deferred with a trigger, below.
4. Any change to phases, subagents, or sizing.

## Proposal

```
 INTAKE     reduce. one sentence: what must become true.
            three tests. lands in state.json and in the plan's Goal.
            ── this is the framing fix. everything else follows it

 SCOUT      one clause: read against the reduction, not the goal.

 DESIGN     reject.  building new where something close exists costs
                     one sentence naming the property it lacks.
                     goes in Decisions, which already has that column.

            fold.    a task is the smallest thing a reviewer could
                     reject on its own. setup, config and docs fold
                     into the task whose deliverable needs them.
```

### The reduction

`crew-intake` already restates the problem in a paragraph and grounds it (`:66-78`). It gains
one more output: a single sentence naming what must become true. Three tests, and a bad
reduction fails at least one of them visibly.

1. It is shorter than the stated goal.
2. It excludes something the stated goal implies, and the next line says what.
3. It names no mechanism. A file, function, library or data structure in that sentence means
   it is a solution wearing a requirement's clothes.

For `archmds-745` the reduction is "model choice must be able to depend on who the actor is."
Shorter than the goal, excludes Opus 5, Nova, pricing, metrics and `max_tokens`, names
nothing. "We need a contextvar holding an actor" fails test 3.

It lives in intake rather than design because scout runs in between, and scout reading the
code against a solution-shaped goal is what produced an inventory of preconditions instead of
an inventory of candidates. `state.json` gains a `reduction` field beside `goal`, and the
plan's `Goal` section opens with it.

### The rejection

Every mechanism the design passes over in favour of building something new gets a row in
`Decisions` naming the specific property it lacks. `Decisions` is already a table whose third
column is what was rejected (`skills/crew/SKILL.md:88`), so this is a rule about what has to
be in it rather than a new section.

"It does not fit" is not a property. "It keys on `build_id` and the gate needs `user_sub`,
and extending it changes six callers" is. The reason the plan gave for `route_actor` was that
the two builders disagree on identity. That is true, and it does not survive the obvious
follow-up about whether the gate could accept either shape. It did not survive it: the merged
code sets an ambient actor from the builders that were already there. The reduction alone
would not have forced that question. Writing the reason in one line rather than the two
hundred words the plan spent is what makes it cheap to ask, and cheap to ask at Gate 1.

### The fold

A task is the smallest unit that carries its own test cycle and that a reviewer could
meaningfully reject while approving its neighbour. Setup, configuration, scaffolding and
documentation fold into the task whose deliverable needs them.

Taken from superpowers' `writing-plans`, which has no crew equivalent. Applied to
`archmds-745`, `t4` and `t8` both fold and the plan loses two builder dispatches. It does not
over-collapse: `t2` clamps `max_tokens` and `t3` fixes pricing, both consuming `t1`, and a
reviewer could accept one and reject the other, so they stay split.

## Why this shape

| Decision | Rationale | Rejected |
|---|---|---|
| Fix the framing, not the knowledge | The plan already contains a correct inventory of what works and it listed none of the duplicated mechanisms, because an inventory written after an approach exists lists that approach's preconditions | An `Exists` section in `plan.md` for the agent to record what already exists. It would restate a paragraph that is already there |
| The reduction lives in intake | Scout runs between intake and design. Put the reduction in design and scout still reads against the original framing, which is what happened here | Putting it in design, which touches one fewer file |
| Three mechanical tests, not "think from first principles" | That instruction produces a heading with three bullets restating the goal. Shorter, excludes something, names no mechanism are checkable by reading one sentence | A prose instruction to reduce the problem to basics |
| The rejection rule reuses `Decisions` | It is already a table whose third column is what was rejected. A new section for the same content is the pattern this document exists to stop | A `Reuses` table listing every file and what it was checked against |
| No new reviewer | The human caught every instance already. The problem is that the catch happened at build. All three changes produce text the human reads at Gate 1, hours earlier, and cost no dispatch | A `crew-scope` subagent as a second critique lane. Deferred with a trigger |
| One PR | Nineteen changes from one diagnosed run is the failure this document describes | The three-PR plan in the earlier draft |

## Delivery

One PR, four files. Two carry real additions and two carry a clause each.

- `skills/crew-intake/SKILL.md`: section 2 gains the reduction and its three tests. Section 5
  writes it to `state.json`.
- `skills/crew/SKILL.md`: `state.json` gains `reduction` beside `goal`. The plan schema's
  `Goal` row opens with it, and the `Decisions` row gains the rule about passed-over
  mechanisms.
- `skills/crew-scout/SKILL.md`: read the code against the reduction, not the goal.
- `skills/crew-design/SKILL.md`: the rejection rule and the task-boundary rule.

Verify by running a crew to Gate 1 on a real ticket and checking three things: the reduction
passes all three tests, `Decisions` has a row for every existing mechanism the approach
passed over, and no task exists that a reviewer could not reject on its own.

## Risks

| Risk | Mitigation | Trigger to revisit |
|---|---|---|
| The reduction becomes the goal reworded | The three tests. A reduction that is longer, excludes nothing, or names a mechanism fails visibly | Two consecutive reductions that pass the tests and still carry the whole goal |
| Intake writes the reduction before reading any code, so it may reduce to something the codebase cannot support | That is the point. A reduction constrained by the code inherits the code's framing, which is the failure being fixed. Design can revise it, and a revision is visible at Gate 1 | A reduction revised during design in more than one run out of three |
| The design passes over a mechanism silently, so no `Decisions` row appears and the rule never fires | None. Nothing checks the list is complete | A run where the human finds a duplicated mechanism at Gate 1 with no row for it |
| Adjacent scope survives when the goal itself bundles several concerns, as `archmds-745` did with three tickets | None in this change. The reduction of a bundled goal is a bundled reduction | Any run whose reduction needs the word "and" to stay true |

## Deferred

Cut, not abandoned. None ships before its trigger fires.

| Deferred | Trigger |
|---|---|
| A `crew-scope` subagent as a second critique lane, dispatched in two phases with the plan path withheld from the first | Three runs where Gate 1 shows the reduction and the `Decisions` rows and the plan is still cut during build |
| Splitting a run at intake when the reduction needs "and" to stay true | A run whose reduction needs "and", or whose frontmatter carries more than one ticket |
| A file count at Gate 1, derived from `Tasks` rather than authored | Same as the subagent |
| Plan readability: one-sentence `Goal` enforcement, and banning rationale and placeholders from `instruction` | Its own document |
| Replacing `crew-design:35`'s five-question cap, which exists because the predecessor paid a dispatch per question (`docs/design.md:21`) and now penalises the conversation this change encourages | A design conversation that stops before the design is right |
| A rule for citing another repository: name the ref you read, and check the working tree is not behind | A second citation error traced to a stale checkout |
| Widening the accepted risk at `docs/design.md:234` | When any of the above lands |

## Appendix A: numbers from `archmds-745-model-flag`

Produced by parsing the fenced `json` block under `## Tasks` in
`archimedes/.crew/archmds-745-model-flag/plan.md` and counting whitespace-separated tokens.
Prose is the plan file with that block removed.

| Measure | Value |
|---|---|
| Tasks | 9 |
| Distinct files owned (`files ∪ generates`) | 30 |
| Task instruction words, total | 1,746 |
| Largest single instruction (`t6`) | 451 words |
| Prose words, plan minus the `Tasks` block | 1,687 |
| Plan size | 28,736 bytes |
| Tickets in frontmatter | 3 |

Cut by hand after the code existed, verified against `origin/main` at `2df6e14a`: `t5`, the
LiteLLM tool-choice patch; `t9`, the API path; `route_actor` from `t6`; and
`model_capabilities.py`, the whole of `t1`. Of the modules the plan created, only
`model_routes.py` survives. The reasons for cutting `t5` and `t9` are the author's, not
independently verified here. The other two are verified by absence.

Two incidental observations. `docs/design.md:234` records an accepted risk whose trigger is a
run where the critic passes a plan and the approach turns out wrong at build time. This run
does not match it: `state.json` shows `verdict: BLOCK` with one blocker still standing after
`round: 2`, and `gates.g1: true` anyway. The critic never passed, and the approach was right
at several times the necessary size. Separately, that plan's frontmatter records
`blocker: 3, round: 1` while `state.json` records `blocker: 1, round: 2`. The schema says
`state.json` wins, so nothing broke, but the copy a human reads first was stale.

## Appendix B: what this document used to propose

The first draft proposed a new `crew-scope` subagent, a two-dispatch protocol, a verdict
enum, four finding kinds, a `state.json` split, a phase-4 sizing change, a `Reuses` table, a
derived file count at Gate 1, a one-sentence `Goal`, two `instruction` bans, a task-boundary
rule, an edit to `crew-critic`'s method, and a widening of `docs/design.md:234`. Nineteen
changes across six files, delivered as three PRs, from one diagnosed run.

An adversarial reviewer on a different model family, given read access to both repositories
and asked to attack the reasoning rather than the prose, returned `REVISE` with two blockers
and five majors. It found seven citation errors, including a symbol attributed to the wrong
line range and a byte count that was actually a character count. All seven were verified and
corrected. Its two blockers were that the anti-anchoring mechanism was unenforceable as
written, and that the schema half had never been evaluated as the whole solution.

One of its majors was that the document did not follow its own advice about reusing what
exists. That finding was marked accepted and then nothing was cut, which is the same failure
the document describes. The cut happened only when the human asked for the goal to be
restated and the assumptions questioned.

A second draft still proposed an `Exists` section in `plan.md` for the agent to record what
already exists in the codebase. That survived until the human pointed out it was scout's job
already, at which point the plan's own "what is already fine" paragraph turned out to be
exactly that section, written, cited, and useless. The section was cut and the framing fix
took its place.

Both are recorded as evidence. A reviewer with codebase access and no stake in the draft found
seven things the author's citations concealed, and two rounds of the author agreeing with
findings produced no cuts at all until someone asked for the goal again.
