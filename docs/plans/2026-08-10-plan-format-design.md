# Making crew's plans readable and explicit

Facts checked at `9bdaa53` with a clean working tree. Numbers taken from `archimedes` are
quoted from `docs/plans/2026-08-07-smaller-plans-design.md` rather than re-derived, because
that repository is not checked out here.

## Summary

A crew plan describes each task twice. Once as prose under `## Approach`, and once as an
`instruction` string inside the `## Tasks` JSON block. The two copies say the same thing in
different words, and the builders follow the copy that is harder to read.

This document replaces both with one copy, written in the task format from superpowers'
`writing-plans`: a markdown section per task carrying its interfaces and its steps as checkboxes
with real code and exact commands. The `Approach` prose becomes a diagram and a file map. The
single `Tasks` JSON array is broken up, so that each task section opens with a short fenced
`yaml` header holding only the fields that control dispatch, and the readable half sits below
it.

An earlier document, `2026-08-07-smaller-plans-design.md`, addressed plan *size* and named plan
*readability* as a separate concern to be handled on its own (`:112-114`). This is that
document.

## Terms

A **task** is one unit of work, owned by one builder. A **wave** is the set of tasks whose
dependencies are already built, dispatched in parallel. A task's **ownership union** is every
path it may write, which is how crew stops two parallel builders from touching one file.

## Problem

In the user's words: crew produces bloated plans that are hard to follow, and are not explicit
enough for the builders to follow.

Both halves have the same cause. Take `crew-v2`, the run that built crew's own second half.
Its `## Approach` section spends 1,324 words describing what the build, review, PR and babysit
phases must do. Its ten `instruction` strings spend a further 925 words describing the same
behaviour to the builders. Here is one pair, the build phase, quoted from each:

> Snapshot `git status --porcelain` before dispatching a wave, and compare afterwards. Judge
> only the files *that wave* changed against its own union.
>
> (`.crew/crew-v2/plan.md:95-97`, the `Approach` prose)

> Snapshot git status --porcelain before each wave and compare after, judging only that wave's
> own changes against its own union so earlier waves are not falsely flagged.
>
> (`.crew/crew-v2/plan.md:266`, the `t2` instruction)

Reading the plan means reading that twice and then working out which copy is binding. It is
the second one. So the plan is long because of the first copy, and untrustworthy because of it
too.

The two copies also drift, which crew already knows. `t10` in that same plan exists only to add
a rule about the drift, and its own text records what happened: a critique round made the merge
conditions safe in the prose while `Tasks` still carried the unsafe predicate. The fix shipped
in the copy nobody executes.

The second half of the complaint is that a builder cannot tell what to write. The longest
instruction in that plan is `t5` at 291 words, a single JSON string with escaped punctuation,
carrying five merge preconditions in English. No file map, no signatures, no commands, no
expected output. Across 384 lines the plan has zero checkbox steps and three fenced blocks, one
of which is the `Tasks` JSON itself. The other two are the phase diagram and the merge
conditions, both in prose sections. No task contains one.

That is not an accident of authorship. `crew-design` forbids it:

```121:124:skills/crew/SKILL.md
Never write a requirement-to-task coverage map. Never write code samples for every
interface. `interfaces` carries signatures, not bodies: it exists because tasks hand off to
each other, not to document the design. That combination of a coverage map and code
everywhere is what made the predecessor's designs bloated and generic.
```

The rule was aimed at a real failure in the predecessor, and it took the contract out with it.
It is also the wrong lever, because a code block is usually shorter than the English trying to
describe the same code. The `t5` GraphQL query is about fifteen lines and leaves nothing to
interpret. It got 291 words instead.

The same run in `archimedes` shows the pattern is not specific to this repo. That plan carried
1,746 words of instruction against 1,687 words of prose, with a single instruction reaching 451
words (`2026-08-07-smaller-plans-design.md:243-245`).

## Goals

1. Every behaviour in the plan is written exactly once, in the task that implements it.
2. A builder reading only its own task knows which files to touch, which signatures to match,
   what to type, and what output proves it worked.
3. The human at Gate 1 can see what will be built without reading the same behaviour twice.

## Non-goals

1. Plan size. `2026-08-07-smaller-plans-design.md` covers the reduction, the rejection rule and
   the fold. Nothing here changes how many tasks a plan has.
2. Parallel builds. Waves, the ownership guard and the circuit breaker keep working unchanged.
3. Splitting `plan.md` into a spec and a plan, the way superpowers does. Crew has one artifact
   and one Gate 1.
4. Any change to phases, subagents, sizing or the two gates.

## Proposal

### Where the words go

```
 BEFORE                            AFTER

 ## Approach                       ## Approach
   ### Build      1,324 w            diagram + file map table
   ### Review     behaviour,         no narrative
   ### PR         in prose
   ### Babysit                     ## Tasks
                                     ### t1
 ## Tasks                              [yaml header] id needs files
   [ {"instruction": "..."} ]                        generates verify
   925 w, same behaviour,               Interfaces
   in JSON strings                      - [ ] steps, code, commands
                                     ### t2 ...

                                    one copy. the builders read it.
                                    the human reads it. same words.
```

`Approach` keeps the diagram and gains superpowers' File Structure section, which is a table of
file to responsibility. That table is what a reader needs before the task list: it shows the
shape of the change on one screen. What it does not do is describe behaviour, because behaviour
now lives in exactly one place.

What the prose used to carry, superpowers puts in two lines of header (`writing-plans:58-77`):
`**Architecture:**` in two or three sentences, and `**Tech Stack:**` on one. Crew takes both,
and takes `## Global Constraints` with them, which is the list of project-wide requirements with
exact values copied verbatim that binds every task.

One reader depends on more than the tasks and has to keep depending on it. `crew-conformance`
reads `Goal`, `Approach` and `Tasks` (`:19`) and is told to work backward from the goal, because
every task can be satisfied while the thing as a whole does not work (`:21-23`). A file map does
not answer that. What answers it is `Goal`, `**Architecture:**`, the diagram and `Verify`, and
those four are named in `crew-conformance` as the end-to-end contract in place of the general
pointer at `Approach`. `Verify` already holds the commands proving the whole thing works
(`crew/SKILL.md:92`), so this makes an existing section load-bearing rather than adding one.

What conformance loses is the per-phase narrative, and losing it is the point. A reviewer
checking a diff against a paraphrase of the tasks is checking the wrong document, which is the
same defect as a builder following the paraphrase.
`Why`, `Decisions`, `Assumptions`, `Verify` and `Non-goals` stay as they are, because Gate 1 is
where the human judges them and crew has no separate spec document holding them.

### The task section

````markdown
### tX: price nova-2-lite at its own tier

```yaml
id: tX
needs: [t1]
files:
  - archimedes/llm/cost.py        # line 51, _PRICING_TIERS
  - tests/llm/test_cost.py
generates: []
verify: "pytest tests/llm/test_cost.py -k nova"
```

**Interfaces**
- Consumes: `resolve_model_id(name: str) -> str`   (t1, verbatim)
- Produces: none. Leaf.

- [ ] **Write the failing test**

```python
def test_nova_2_lite_has_own_tier():
    assert _resolve_tier("nova-2-lite") == "nova-lite"
```

- [ ] **Run it.** `pytest tests/llm/test_cost.py -k nova`
      Expect FAIL: falls through to `"sonnet"`.

- [ ] **Add the row to `_PRICING_TIERS`**

```python
"nova-2-lite": Tier(input=0.06, output=0.24),
```

- [ ] **Run it.** Expect PASS.
````

The example above is numbered `tX`, and that convention is part of the format. Writing the
implementation plan for this change in this format found out why: the plan quotes a task section
as an example, so searching the file for `yaml` fences returns seven tasks where there are six,
and the example's id collides with a real one. The rule is that structure is only what appears
outside a fenced block, that a task is a `### tN` heading under `## Tasks` with N a number, and
that its header is the first `yaml` fence after that heading. Examples take `tX`, which cannot
collide even when something scans carelessly.

The header holds the five fields that decide what runs, when, and whether it passed. `needs`
gives the wave graph, which superpowers has no equivalent for because it never runs two builders
at once. `generates` lists files the task produces but does not author, such as lockfiles and
snapshots. `verify` names the task's own check explicitly rather than leaving the orchestrator
to guess which command in the steps it meant, because `crew-build` collects those strings into
a set and runs each once per wave.

Superpowers writes files as a `**Files:**` block with `Create:`, `Modify:` and `Test:` prefixes
and a line range inside the path (`writing-plans:84-87`). Crew cannot use that here without
writing the same paths twice, so the header is the only place paths appear, and the hints that
block was carrying move to yaml comments beside the path they describe. Whether a file is
created or modified is a fact about the repository, not about the plan.

`verify` is always quoted, because a colon followed by a space is how yaml separates a key from
a value and shell commands contain both. Checked against Ruby's YAML parser:
`verify: bash -c 'echo done: ok'` raises a syntax error, the same line in quotes loads as the
string, and `verify: pytest tests/x.py::test_y` is fine because the colons have no space after
them. Failing loudly there is the header earning its place. A malformed bullet had nothing to
fail against, which is why the rule is that a task whose header does not parse stops the phase.

`**Interfaces**` is superpowers' block (`:89-93`), and it stays in markdown rather than joining
the header, for the same reason quoting is needed above. A signature like
`resolve_model_id(name: str) -> str` carries a colon and a space in the middle of the thing that
has to match verbatim, and quoting every signature to store it somewhere nothing computes on it
is cost without benefit. The check on interfaces is two strings being equal, and markdown holds
a string as well as yaml does.

The checkbox steps are superpowers' task structure (`:95-125`), minus the commit step, because
`agents/crew-builder.md:28` forbids builders from running any git write and the orchestrator
stages against the ownership union instead.

Test-first is the default rather than a mandate. It makes crew's existing requirement that
every `verify` can actually fail true by construction, since step two is watching it fail.
Where no test harness exists, as in this repository, the same three beats hold with the check
in place of the test: write the `rg` assertion, run it, watch it fail.

### Paths

Five readers compare a changed path against the ownership union, so a path that does not compare
cleanly breaks all five at once: the post-wave guard (`crew-build:88-94`), PR staging
(`crew-pr:34`), the review fix guard (`crew-review:111`), every push babysit makes
(`crew-babysit:109`), and the conformance lane's unowned-file finding
(`agents/crew-conformance.md:34`).

The header's `files` and `generates` entries are exact paths and nothing is stripped from them,
which is most of the reason the header exists. Superpowers writes a line range inside the path,
as `existing.py:123-145` (`writing-plans:86`), and crew must not: a path can legitimately end in
a colon and digits, and no rule then tells the two apart. Line hints go in a yaml comment beside
the path, where nothing has to parse them.

That leaves reading git. Crew's existing guards say to compare against
`git status --porcelain` without saying how to read it, and that output is not a list of bare
paths. Run in a scratch repository at the time of writing:

```
$ git status --porcelain
 M sub/cost.py:51
R  sub/oldname.py -> sub/newname.py
?? "sub/spac\303\251 name.py"
```

Three things there defeat a naive read. The first two columns are status, not path. A rename is
one entry holding two paths joined by an arrow, and both of them are the task's business, since
the old path is a deletion the task must own. A path outside ASCII is quoted and octal-escaped
unless `core.quotePath` is off.

Use `git status --porcelain=v1 -z`, which drops the quoting and emits a rename as the new path
followed by the old one, each terminated by a NUL. The same scratch repository:

```
$ git status --porcelain=v1 -z | tr '\0' '\n'
 M sub/cost.py:51
R  sub/newname.py
sub/oldname.py
?? sub/spacé name.py
```

Both paths of a rename must appear in the task's union, and a deletion is owned like any other
change. Crew has this defect today and the new format does not introduce it. It gets fixed here
because the format touches all five of those readers anyway, and because a guard that silently
mismatches a renamed path is the kind of failure nobody notices until it lets something through.

### The brief

`crew-build` currently passes the whole task spec inline in the dispatch (`:54-55`). Instead it
copies the task's markdown section verbatim to `.crew/<slug>/briefs/t3.md` and dispatches the
builder with that path, the Global Constraints block, and the worktree path. The builder reads
the brief and never opens `plan.md`.

Superpowers does this with a script (`subagent-driven-development:205-216`) and gives the
reason plainly: everything pasted into a dispatch prompt stays resident in the orchestrator's
context for the rest of the session and is re-read on every later turn. A task section carrying
real code is exactly the thing you do not want ten copies of in context. Crew has no helper
scripts, so the orchestrator writes the file with its own file tools, which is what it already
does for `state.json` and `plan.md`.

### What gets checked

`crew-design`'s self-check table loses one row and gains two. The row that goes is "names in the
prose match names in `Tasks`" (`crew-design:107`), which is unreachable once there is no second
copy. The same deletion applies to `crew-critique` §4b, which re-runs that check after any round
that edited the plan (`:97-108`).

The two new rows come from superpowers. The first is its No Placeholders list
(`writing-plans:128-136`): "TBD", "add appropriate error handling", "similar to Task N", and any
step that describes what to do without showing how. The second is that no path appears in two
tasks' `files ∪ generates`, which crew states as prose today (`crew/SKILL.md:111-112`) and can
state as a check now that every task's paths sit in one place.

The interface invariants are unchanged: every `Consumes` string appears verbatim in some
`Produces`, no symbol is produced twice, and every `Consumes` has its producer in `needs`.

They do not cover every `needs` edge. A task depending on another only for setup order, for a
shared `generates` path, or for shared `verify` state has no `Consumes` to check against, so
nothing but the author's care stands behind that edge. The plan therefore carries the wave list,
derived from `needs` at design time, and `crew-build` derives it again from the same headers and
stops if the two disagree.

That is not the hand-numbering `crew-build:20` forbids. Hand-numbered waves are a second source
of truth that drifts from `needs`. This list is computed from `Needs`, exists so that two
independent derivations can be compared, and is wrong exactly when the human should see it,
which is at Gate 1 rather than at dispatch. Crew's own v2 plan already ends its task list with
one (`.crew/crew-v2/plan.md:366`), written by hand and checked by nobody.

The anti-bloat section inverts on one point. A step that describes without showing becomes a
plan failure. Everything else it bans stays banned: the requirement-to-task coverage map,
restating the goal in three sections, and padding `Decisions` with choices nobody would question.

## Why this shape

| Decision | Rationale | Rejected |
|---|---|---|
| Delete the `Approach` prose rather than shorten it | The prose and the instructions are the same content, and any rule about length leaves both copies in place. `t10` in crew-v2 is a task filed because they drifted | A word cap on `Approach`, or a rule that `Approach` must not repeat a task |
| Keep parallel waves, and pay a header for them | Serial builds would let crew copy superpowers with no machine fields at all, and would cost the wave structure that the ownership guard and the circuit breaker are built around | Serial execution, which is what superpowers does (`subagent-driven-development:230`) |
| A fenced `yaml` header per task, not markdown bullets | `needs`, `files`, `generates` and `verify` decide what runs in parallel and what a builder is allowed to touch. A misread of a bullet is wrong with nothing to catch it, and interface checks cover only the `needs` edges that carry a signature. Six lines of yaml per task removes the argument | Markdown bullets in superpowers' own style, which read better and put four safety fields into prose |
| One header per task, not one array for the plan | The array is what forced `instruction` to be a JSON string in the first place. Splitting it puts each task's dispatch fields next to the steps they belong to, and no task's content lives anywhere but its own section | Keeping the single `## Tasks` array for the graph and cross-referencing sections by id |
| One `plan.md`, not a spec plus a plan | Superpowers gets a thin plan because `brainstorming` wrote the argument to a separate spec the plan can assume you read. Crew has one artifact and one gate, so `Why`, `Decisions` and `Assumptions` have nowhere else to live | Copying superpowers' two-document split |
| `verify` named in the header | `crew-build` dedupes verify strings across a wave (`:100-103`). Scraping the last command out of the steps makes that depend on step phrasing | Deriving the command from the steps |
| The brief is a file | A task section with code in it, pasted into ten dispatches, stays in the orchestrator's context for the whole run | Passing the section inline, which is what crew does today |
| Test-first as default, not mandate | It makes "every verify can actually fail" structural. Mandating it breaks on repos with no test harness, including this one | Requiring a test in every task |

## Delivery

Two PRs, and the first one holds every skill and agent that reads a plan at runtime. It cannot
be split further. The moment `crew-design` writes the new format, any phase still looking for a
`## Tasks` JSON block is looking for something that is not there, and on a `size: full` run the
next phase to read the plan is `crew-critique`, before Gate 1 and before a single builder runs.

**PR 1, the format and every runtime reader.** `skills/crew/SKILL.md` replaces the `Tasks` JSON
schema with the task section format and states the path and porcelain rules.
`skills/crew-design/SKILL.md` rewrites sections 4, 5 and 6 and the anti-bloat section.
`skills/crew-critique/SKILL.md` re-checks task sections and drops the prose check from §4b.
`skills/crew-build/SKILL.md` reads sections, writes the brief and dispatches its path.
`skills/crew-review/SKILL.md` and `skills/crew-babysit/SKILL.md` build their allowed-path guards
from sections. `skills/crew-pr/SKILL.md` builds the staging union from sections.
`agents/crew-builder.md` reads a brief and works the checkboxes in order.
`agents/crew-conformance.md` reads task sections and the end-to-end contract named below.
`.cursor/agents/` needs no edit; both files are symlinks into `agents/`.

**PR 2, the documentation.** `README.md:230,270` stops describing the JSON contract.
`docs/design.md:147-156` gets a dated amendment note rather than a rewrite, since it records
what was decided then. Neither is read during a run, so this can land after.

Verify by running a crew through Gate 1 to a built wave on a real ticket, and checking four
things: no sentence in `Approach` restates a task, every task section opens with a yaml header
that parses and carries `needs`, `files` and `verify`, every step whose deliverable is code
shows the code, and the wave list `crew-build` derives matches the one the plan carries.

## Risks

| Risk | Mitigation | Trigger to revisit |
|---|---|---|
| A run in flight in another repo has a JSON plan when the skills change under it | `crew-build` and `crew-pr` keep reading a `## Tasks` JSON block when they find one. Two sentences, not a migration path | Any JSON plan still being written six runs from now, at which point delete the clause |
| Path normalisation is now a parsing step, and four phases depend on it | The rule is stated once and cited, and every consumer compares normalised paths only | An ownership guard that passes a path it should have stopped, or stops one it should have passed |
| Task sections with code make `plan.md` longer in bytes than the version this replaces | It removes 1,324 duplicated words and adds code where prose was describing code. The claim is that it is shorter to read, not shorter on disk | A plan the human skips reading at Gate 1 |
| The design agent writes code that is wrong, and a builder transcribes it faithfully | Gate 1 is where wrong code is cheapest to catch, which is the point of writing it there. The critic reads the plan and can now read the code in it | Any Gate 1 that approves plan code which turns out wrong at build time |
| An agent reads `needs` wrongly and builds a wave out of order | The yaml header keeps the field in one canonical shape, and the interface invariants catch a `Consumes` whose producer is missing. Neither covers a `needs` edge that exists only for setup order, shared `generates`, or shared `verify` state, so the wave list is derived at design time and derived again at build, and a disagreement stops the line | Any wave that dispatches a task before something it needed, whether or not the build failed because of it |

## Deferred

| Deferred | Trigger |
|---|---|
| A helper script to slice a task section into a brief, the way superpowers does | The orchestrator writing a brief file by hand getting it wrong once |
| Superpowers' per-task review loop, where a reviewer gates each task before the next dispatch | A wave passing verify and failing conformance at Gate 2 |
| Splitting `plan.md` into a spec and a plan | A Gate 1 where the human wants to approve the argument and the tasks separately |
| Enforcing a one-sentence `Goal`, listed as deferred in `2026-08-07-smaller-plans-design.md:228` | Unchanged. It travels with the reduction, not with this |

## Appendix A: numbers from `crew-v2`

Produced by parsing the fenced `json` block under `## Tasks` in `.crew/crew-v2/plan.md` and
counting whitespace-separated tokens. Prose is the file with that block removed. `Approach` is
the text between `## Approach` and the next `##` heading.

| Measure | Value |
|---|---|
| Tasks | 10 |
| Instruction words, total | 925 |
| Largest single instruction (`t5`) | 291 |
| Prose words, plan minus the `Tasks` block | 2,289 |
| `Approach` section words | 1,324 |
| Checkbox steps in the whole plan | 0 |
| Fenced code blocks in the whole plan | 3, one of them the `Tasks` JSON. None inside a task |
| Plan length | 384 lines |

`.crew/crew-v1/plan.md` is not counted. It predates the `Tasks` JSON block and carries a
`## Files` section instead, so it has no instruction strings to measure.

## Appendix B: what crew takes from superpowers, and what it leaves

| From `writing-plans` and `subagent-driven-development` | Taken |
|---|---|
| `**Files:**` block with Create, Modify and Test (`writing-plans:84-87`) | No. Paths live in the yaml header, and a second list would be the duplication this document exists to remove |
| `**Interfaces:**` Consumes and Produces (`:89-93`) | Yes, in markdown. Crew already had this |
| Checkbox steps with real code and exact commands (`:95-125`) | Yes, minus the commit step |
| No Placeholders (`:128-136`) | Yes, as a check |
| `## Global Constraints` (`:69-74`) | Yes |
| `**Architecture:**` and `**Tech Stack:**` one-liners (`:63-67`) | Yes, replacing the `Approach` prose |
| File Structure before the tasks (`:26-34`) | Yes, as the file map |
| Task right-sizing (`:36-43`) | Already taken by `2026-08-07-smaller-plans-design.md` |
| The brief file per task (`subagent-driven-development:205-216`) | Yes, written by hand rather than by script |
| Serial execution, one implementer at a time (`:230`) | No. Crew builds in waves |
| A separate spec document holding the argument (`brainstorming:107`) | No. Crew has one artifact and one gate |
| Per-task review loop with five fix rounds (`:302-375`) | No. Crew reviews once, after the build |
| A progress ledger surviving compaction (`:117-140`) | No. `state.json` and `waveCursor` already do this |
