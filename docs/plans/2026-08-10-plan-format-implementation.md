# Plan format implementation plan

> **For agentic workers:** implement this task by task. Each `### tN` section is one task.
> Its `yaml` header is the contract; the checkboxes below it are the work.

**Goal:** Replace the `## Tasks` JSON array in a crew plan with one markdown section per task,
each opening with a `yaml` header, so that every behaviour in a plan is written once and a
builder is told exactly what to write.

**Architecture:** `skills/crew/SKILL.md` owns the format and delegates its detail to a new
`references/plan-format.md`, because that skill is at 190 of its 200 permitted lines. Every
other skill and agent cites that reference rather than restating it. Nothing executes; these are
instruction documents read by an agent, so a task's `verify` is an `rg` assertion about what the
document now says.

**Tech Stack:** Markdown skills and agents for the Cursor plugin system. Verified with `rg` and
`cursor-agent --plugin-dir`.

**Spec:** `docs/plans/2026-08-10-plan-format-design.md`

## Global Constraints

- Every `skills/*/SKILL.md` body stays under 200 lines. `skills/crew/SKILL.md` is at 190, so new
  depth goes to `skills/crew/references/plan-format.md`, one level deep.
- Ownership guards compare two tree snapshots, never `git status`. The helper is named
  `crew_snapshot` and is defined once, in the reference.
- A `verify` value inside a plan's yaml header is always a quoted string.
- Skill frontmatter `name` equals its parent folder name. Agent frontmatter `name` equals its
  filename. Only `skills/crew` sets `disable-model-invocation`.
- Every agent keeps `model:` and `force-default-model: true` exactly as they are. Do not retune
  a model in this work.
- Never edit `.cursor/agents/*`. Those four files are symlinks into `agents/`.
- Do not add a rule that already exists elsewhere. Cite `skills/crew/references/plan-format.md`
  instead of repeating it.

## File map

| File | Responsibility after this change |
|---|---|
| `skills/crew/references/plan-format.md` | New. The task section format, the yaml fields, path rules, the snapshot helper, the wave list. The one place any of it is defined |
| `skills/crew/SKILL.md` | The plan schema table points at the reference. State layout gains the briefs directory |
| `skills/crew-design/SKILL.md` | How to write task sections, and the self-check run before every gate |
| `skills/crew-critique/SKILL.md` | Re-checks task sections after a round. No longer checks prose against `Tasks` |
| `skills/crew-build/SKILL.md` | Waves from `needs`, the wave-list comparison, the brief file, dedupe on `verify` |
| `skills/crew-review/SKILL.md` | Fix-loop allowed-path guard reads task sections |
| `skills/crew-babysit/SKILL.md` | Push guard reads task sections |
| `skills/crew-pr/SKILL.md` | Staging union reads task sections |
| `agents/crew-builder.md` | Receives a brief path, works the checkboxes in order |
| `agents/crew-conformance.md` | Reads the end-to-end contract and task sections |
| `README.md` | Describes the new format |
| `docs/design.md` | Dated amendment note. Not rewritten |

## Tasks

---

### t1: define the format in one place

```yaml
id: t1
needs: []
files:
  - skills/crew/references/plan-format.md
  - skills/crew/SKILL.md          # schema table ~line 82-124, state ~line 53-58
generates: []
verify: "rg -q 'crew_snapshot' skills/crew/references/plan-format.md && rg -q 'briefs/' skills/crew/SKILL.md && ! rg -q 'instruction' skills/crew/SKILL.md && [ $(wc -l < skills/crew/SKILL.md) -lt 200 ]"
```

**Interfaces**

- Consumes: nothing.
- Produces, and every later task cites these strings verbatim:
  - the reference path `skills/crew/references/plan-format.md`
  - the yaml keys `id`, `needs`, `files`, `generates`, `verify`
  - the helper name `crew_snapshot` and the command `git diff-tree -r --name-only -z`
  - the brief path `<repoRoot>/.crew/<slug>/briefs/<id>.md`
  - the section heading `## Wave list`

- [ ] **Run the check first, and watch it fail**

```bash
rg -q 'crew_snapshot' skills/crew/references/plan-format.md
```

Expect FAIL: the file does not exist yet.

- [ ] **Create `skills/crew/references/plan-format.md`.** It opens with the task section shape,
      shown as a complete example rather than described:

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
- [ ] **Run it.** Expect FAIL, and say why it fails.
- [ ] **Write the implementation**
- [ ] **Run it.** Expect PASS.
````

- [ ] **State how a header is found, immediately after that example.** Writing this plan found
      the reason: it contains the example above, so scanning the file for fenced `yaml` blocks
      yields seven headers for six tasks, and the example's `id: t3` collides with a real task.

```markdown
Structure is only what appears outside a fenced block. A `### tN` heading or a `yaml` fence
inside a fence is content, which is why an example of a task section is written inside a
four-backtick fence. Track fence state while scanning; a fence opened with more backticks closes
only on that many.

A task is a `### tN` heading under `## Tasks`, where N is a number. Its header is the first
fenced `yaml` block after that heading. An example task in prose is numbered `tX` so that it
cannot collide with a real one even if something scans carelessly.

Never collect headers by searching the file for `yaml` fences. Writing the plan for this change
did exactly that and found seven tasks where there were six.
```

- [ ] **State the step pattern in the same file**

```markdown
Steps are test-first by default. Write the check, run it and watch it fail for a named reason,
make the change, run it again. The failing run is not ceremony: it is what proves the check
can fail, which is the difference between a `verify` that tests the task and one that passes on
an unchanged tree.

Where a repository has no test harness, the shape holds with the check in place of the test. An
`rg` assertion that the file does not yet say something is a failing test.
```

- [ ] **Add the field table to the same file**

| Field | Meaning |
|---|---|
| `id` | Matches the section heading. `t1`, `t2`, in file order |
| `needs` | Task ids this one waits for. `[]` puts it in wave 0 |
| `files` | Exact paths the task authors. No prefixes, no line ranges. A line hint goes in a `#` comment beside the path |
| `generates` | Exact paths it produces but does not author: lockfiles, generated code, snapshots. `[]` when none |
| `verify` | Always a quoted string. Checks this task alone, scoped to its own `files`. Never the whole suite |

- [ ] **Add the two rules that make paths comparable.** Both in the same file, stated once,
      because five readers compare a changed path against a task's `files ∪ generates`: the
      post-wave guard, PR staging, the review fix guard, every push babysit makes, and the
      conformance lane's unowned-file finding.

````markdown
Entries in `files` and `generates` are exact paths, relative to the repository root, with no
`./` and no `..`. Nothing is stripped from them. A path can legitimately end in a colon and
digits, so a line range never goes inside the path; it goes in a `#` comment beside it.

A guard answers one question: which paths did this dispatch change? Snapshot the working tree
before and after, and diff the two. A snapshot is a tree object built through a throwaway index,
so the real one is never touched:

```bash
crew_snapshot() {
  local i; i="$(mktemp -u)"
  cp "$(git rev-parse --git-path index)" "$i" 2>/dev/null || true
  GIT_INDEX_FILE="$i" git add -A
  GIT_INDEX_FILE="$i" git write-tree
  rm -f "$i"
}

git diff-tree -r --name-only -z "$BEFORE" "$AFTER"
```

Exact paths, NUL separated, untracked files included, `.gitignore` honoured, a rename reported
as its two paths. Never `git status`: it reports the state a path is in rather than whether it
changed, so a file an earlier wave left at `M` stays at `M` when a later builder edits it and
the guard sees nothing.
````

- [ ] **Add the wave list rule to the same file**

```markdown
The plan carries a `## Wave list` section, derived from every task's `needs` by topological
sort. `crew-build` derives it again from the same headers and stops if the two disagree.

This is not the hand-numbering `crew-build` forbids. A hand-numbered wave is a second source of
truth that drifts from `needs`. This one is computed from `needs`, and it exists so two
independent derivations can be compared while the human is still looking, at Gate 1.
```

- [ ] **Add a no-placeholders list to the same file**

```markdown
Each of these is a plan failure, not a style problem:

- `TBD`, `TODO`, "implement later", "fill in details"
- "add appropriate error handling", "add validation", "handle edge cases"
- "similar to task N". Repeat it. The builder cannot see task N
- a step whose deliverable is code and which shows no code
- a name, type or function no task defines
```

- [ ] **Rewrite the `plan.md schema` table in `skills/crew/SKILL.md`.** Delete the JSON block
      and the field table under it, and delete the paragraph beginning "Never write a
      requirement-to-task coverage map", which the reference now covers. The table becomes
      exactly these rows, in this order:

| Section | Contents |
|---|---|
| Goal | One paragraph. What done looks like |
| Why | The problem. Evidence, with `file:line` or URL |
| Architecture | Two or three sentences on the approach |
| Tech Stack | The technologies it is built on. One line |
| Decisions | Table: decision, rationale, what was rejected |
| Assumptions | Unknowns accepted without closing, each human-approved. Empty is valid |
| Global Constraints | Project-wide requirements, one line each, exact values copied verbatim. Every task's requirements implicitly include this |
| Approach | A diagram and a file map: which file is created or changed, and what each is responsible for. Never a description of what a task does |
| Tasks | One `### tN` section per task. Format in `references/plan-format.md` |
| Wave list | Derived from every task's `needs` by topological sort |
| Verify | Commands proving the whole thing works. The one place a whole-suite run belongs, and it runs once |
| Non-goals | Explicitly out of scope |

      The body must stay under 200 lines, which is why the format detail is in the reference and
      not here.

- [ ] **Add the briefs directory to the State section** of the same file, beside `plan.md` and
      `state.json`: `briefs/<id>.md` holds one task section, written at dispatch, read by one
      builder.

- [ ] **Run the check.** Expect PASS on all four clauses, including the line count.

---

### t2: write and check task sections

```yaml
id: t2
needs: [t1]
files:
  - skills/crew-design/SKILL.md
  - skills/crew-critique/SKILL.md
generates: []
verify: "rg -q 'plan-format.md' skills/crew-design/SKILL.md && ! rg -q 'Names in the prose match' skills/crew-design/SKILL.md && ! rg -q 'prose against' skills/crew-critique/SKILL.md && rg -q 'Wave list' skills/crew-design/SKILL.md"
```

**Interfaces**

- Consumes, verbatim from t1: `skills/crew/references/plan-format.md`, the yaml keys, and the
  heading `## Wave list`.
- Produces: the self-check table that `crew-critique` re-runs, cited as
  `crew-design` section 6.

- [ ] **Run the check first, and watch it fail**

```bash
! rg -q 'Names in the prose match' skills/crew-design/SKILL.md
```

Expect FAIL: that row is at `skills/crew-design/SKILL.md:107` today.

- [ ] **Replace section 4 of `crew-design`.** It currently tells the author to write a fenced
      `json` block. It now says: one `### tN` section per task, format in
      `skills/crew/references/plan-format.md`, and a `## Wave list` derived from `needs`. Keep
      the existing paragraphs on scoping `verify` narrowly; they are unchanged and correct.

- [ ] **Leave section 5 alone except for its field names.** Interfaces stay markdown bullets.
      `produces` becomes `Produces` and `consumes` becomes `Consumes`, matching the bullet
      labels in the reference. The rule that a `Consumes` entry whose producer is missing from
      `needs` is a dependency bug rather than an interface one is unchanged.

- [ ] **Replace the section 6 check table with exactly these rows**

| Check | Failure it catches |
|---|---|
| Every task's yaml header parses | A quoting slip in `verify` reads as a broken task, and it should stop the phase, not the build |
| The number of headers equals the number of `### tN` headings under `## Tasks` | A `yaml` block shown as an example parses as a task nobody meant to schedule |
| Every `Consumes` string appears verbatim in some `Produces` | `clearLayers()` in one task, `clearFullLayers()` in another. Both builders are right; the code does not compile |
| No symbol appears in two tasks' `Produces` | Two builders define the same thing in parallel and the second overwrites the first |
| Every `Consumes` has its producer in `needs` | The two tasks land in the same wave and race |
| No path appears in two tasks' `files ∪ generates` | Two builders write one file at the same time |
| The `## Wave list` matches a topological sort of `needs` | A `needs` edge for setup order or shared state has no interface to check it |
| Nothing from the no-placeholders list appears in any step | The builder gets "handle edge cases" and invents a design |
| Every task's `verify` can actually fail | A check that passes on the unchanged tree verifies nothing |
| No task's `verify` runs the whole suite | The suite runs once per task per wave instead of once, and the build takes hours |

- [ ] **Delete the row about prose matching `Tasks`, and the paragraph after the table that
      explains it.** There is no second copy to drift from. That paragraph currently ends the
      section at `skills/crew-design/SKILL.md:113-116`.

- [ ] **Invert the anti-bloat section.** Keep every existing ban: no coverage map, no restating
      the goal in three sections, no padding `Decisions`, length is not thoroughness. Replace
      the ban on code samples with its opposite, in one line: a step whose deliverable is code
      and which shows no code is a plan failure. Add one line saying `## Approach` carries a
      diagram and a file map and never describes what a task does.

- [ ] **Rewrite `crew-critique` §4b.** It keeps re-running `crew-design` section 6 after any
      round that edited the plan. It stops referring to prose and `Tasks` as two things. The
      paragraph beginning "Prose and `Tasks` drift" is replaced by one sentence: a round that
      edits a task section must leave that task's header, interfaces and steps consistent, and
      the section 6 table is what proves it.

- [ ] **Run the check.** Expect PASS on all four clauses.

---

### t3: build from task sections

```yaml
id: t3
needs: [t1]
files:
  - skills/crew-build/SKILL.md
generates: []
verify: "rg -q 'crew_snapshot' skills/crew-build/SKILL.md && rg -q 'briefs/' skills/crew-build/SKILL.md && rg -q 'Wave list' skills/crew-build/SKILL.md && ! rg -qi 'tasks json' skills/crew-build/SKILL.md && [ $(wc -l < skills/crew-build/SKILL.md) -lt 200 ]"
```

**Interfaces**

- Consumes, verbatim from t1: `skills/crew/references/plan-format.md`, the yaml keys,
  `crew_snapshot`, `<repoRoot>/.crew/<slug>/briefs/<id>.md`, `## Wave list`.
- Produces, and t5 consumes: the dispatch payload is the brief path, the plan's
  `## Global Constraints` block, and the worktree path. Nothing else.

- [ ] **Run the check first, and watch it fail**

```bash
! rg -qi 'tasks json' skills/crew-build/SKILL.md
```

Expect FAIL: the frontmatter description and line 10 both say it.

- [ ] **Change the frontmatter description.** It reads "Executes the Tasks JSON from plan.md".
      It now says it executes the task sections of `plan.md`. The `name` field does not change.

- [ ] **Change the opening read.** Instead of reading the Tasks JSON block, read every `### tN`
      section from `<repoRoot>/.crew/<slug>/plan.md` and parse each yaml header.

- [ ] **Add the wave-list comparison to §1.** After the topological sort, compare the result
      against the plan's `## Wave list`. On a disagreement, stop and surface both. Keep the
      existing rule that waves are never hand-numbered, and keep `waveCursor` behaviour
      unchanged.

- [ ] **Add the brief to §3, before the dispatch**

```markdown
Write the task's section verbatim to `<repoRoot>/.crew/<slug>/briefs/<id>.md`, then dispatch
`crew-builder` with that path, the plan's `## Global Constraints` block, and the worktree path.

Never paste the section into the prompt. A task section carries real code, and everything in a
dispatch prompt stays in your context for the rest of the run and is re-read every turn.
```

- [ ] **Replace the snapshots in §4.** Both become `crew_snapshot`, compared with
      `git diff-tree -r --name-only -z`. Say why status cannot do this job: a file an earlier
      wave left at `M` stays at `M` when this wave edits it. Do not restate the rest of the
      rule; cite `skills/crew/references/plan-format.md`.

- [ ] **Leave §5 and §6 alone.** Dedupe still collects `verify` strings into a set, and the
      circuit breaker is unchanged.

- [ ] **Add three lines to the Never list:** never paste a task section into a dispatch prompt,
      never use `git status` as an ownership snapshot, never proceed when the derived
      waves disagree with the plan's `## Wave list`.

- [ ] **Run the check.** Expect PASS on all five clauses.

---

### t4: the three union readers

```yaml
id: t4
needs: [t1]
files:
  - skills/crew-review/SKILL.md
  - skills/crew-babysit/SKILL.md
  - skills/crew-pr/SKILL.md
generates: []
verify: "for f in skills/crew-review/SKILL.md skills/crew-babysit/SKILL.md skills/crew-pr/SKILL.md; do rg -q 'crew_snapshot' \"$f\" || exit 1; rg -q 'plan-format.md' \"$f\" || exit 1; [ $(wc -l < \"$f\") -lt 200 ] || exit 1; done; ! rg -qi 'tasks json' skills/crew-pr/SKILL.md"
```

**Interfaces**

- Consumes, verbatim from t1: `skills/crew/references/plan-format.md`, `crew_snapshot`,
  `git diff-tree -r --name-only -z`, and the keys `files` and `generates`.
- Produces: nothing. Three leaves.

- [ ] **Run the check first, and watch it fail**

```bash
rg -q 'crew_snapshot' skills/crew-pr/SKILL.md
```

Expect FAIL: none of the three uses a snapshot today.

- [ ] **`crew-pr`.** Line 13 reads the Tasks JSON block; it now reads the task sections. The
      staging union at line 53 is the union of every task's `files` and `generates` from the
      yaml headers. The changed-path check at line 34 becomes
      `git diff-tree -r --name-only -z HEAD "$(crew_snapshot)"`, which is every path differing
      from the last commit. Never `git add .` is unchanged.

- [ ] **`crew-review`.** The fix-loop guard near line 111 keeps its existing and correct rule
      that a fixer is scoped to the finding's own paths and never to the whole plan union. Two
      things change: paths come from the task sections, and the before-and-after pair becomes
      `crew_snapshot`. Also pass the conformance lane the changed-path list, because it reads a
      diff and a diff cannot show an untracked file.

- [ ] **`crew-babysit`.** Same change at its push guard near line 109. This file is at 174
      lines, so cite the reference rather than restating the path rule, and put nothing new in
      `references/merge-query.md`, which is about something else.

- [ ] **Run the check.** Expect PASS. It asserts all three files carry both strings and all
      three stay under 200 lines.

---

### t5: the two agents

```yaml
id: t5
needs: [t1, t3]
files:
  - agents/crew-builder.md
  - agents/crew-conformance.md
generates: []
verify: "rg -q 'brief' agents/crew-builder.md && ! rg -qi 'tasks json' agents/crew-builder.md && rg -q 'Architecture' agents/crew-conformance.md && rg -q '^model: composer-2.5-fast' agents/crew-builder.md && rg -q '^force-default-model: true' agents/crew-conformance.md"
```

**Interfaces**

- Consumes, verbatim from t3: the dispatch payload is the brief path, the plan's
  `## Global Constraints` block, and the worktree path.
- Consumes, verbatim from t1: `<repoRoot>/.crew/<slug>/briefs/<id>.md`, and the keys `files` and
  `generates`.
- Produces: nothing. Leaf.

- [ ] **Run the check first, and watch it fail**

```bash
! rg -qi 'tasks json' agents/crew-builder.md
```

Expect FAIL: the frontmatter description says "from a crew plan's Tasks JSON".

- [ ] **`crew-builder` frontmatter.** The description now says it implements one task from a
      brief file. `model` and `force-default-model` do not change, and the verify command
      asserts that.

- [ ] **`crew-builder` method.** It is given a brief path. Step 1 becomes: read the brief, then
      read every file its `files` list names before changing any of them. Add: work the
      checkboxes in order and do not skip the step that runs a check expecting failure, because
      a check that passes before the change proves nothing. The existing two-attempt fix rule,
      the ban on touching files outside `files ∪ generates`, and the ban on git writes are all
      unchanged.

- [ ] **`crew-builder` output.** Unchanged. It still lists every file it changed, and the
      orchestrator still compares that list against the union.

- [ ] **`crew-conformance` method step 1.** It currently reads `Goal`, `Approach` and `Tasks`.
      It now reads `Goal`, `**Architecture:**`, the `Approach` diagram and file map, `Verify`,
      and the task sections. Name those as the end-to-end contract, because step 3 tells it to
      work backward from the goal and a file map alone cannot answer that.

- [ ] **`crew-conformance` findings table.** The `Unowned` row now says: files changed that no
      task's `files` or `generates` claimed, read from the yaml headers, compared exactly per
      `skills/crew/references/plan-format.md`, and with a note that a diff omits untracked
      files so absence of evidence is reported rather than counted as clean.

- [ ] **Add an `Unconstrained` row to the same table**

```markdown
| Unconstrained | A `Global Constraints` line the diff breaks |
```

`Global Constraints` is new to the schema in t1, and without this row nothing reads it. The
lane that judges a diff against the approved plan is where a constraint the plan states and the
diff breaks should surface.

- [ ] **Run the check.** Expect PASS on all five clauses, including both model pins.

---

### t6: the documentation

```yaml
id: t6
needs: [t2, t3, t4, t5]
files:
  - README.md
  - docs/design.md
  - docs/plans/2026-08-10-plan-format-design.md          # ships as written
  - docs/plans/2026-08-10-plan-format-example.md         # ships as written
  - docs/plans/2026-08-10-plan-format-implementation.md  # this file
generates: []
verify: "! rg -qi 'tasks json' README.md && rg -q 'plan-format' README.md && rg -q '2026-08-10' docs/design.md && ls docs/plans/2026-08-10-plan-format-{design,example,implementation}.md"
```

The last three are already written and are not edited by this task. They are listed because
every changed path must sit in some task's union or the PR guard stops the commit, and these
three are in the change. A planning artifact that ships with its own work still has to be owned
by something.

**Interfaces**

- Consumes: nothing. `needs` carries the ordering.
- Produces: nothing. Leaf.

- [ ] **Run the check first, and watch it fail**

```bash
! rg -qi 'tasks json' README.md
```

Expect FAIL: `README.md:230` and `:270` both describe it.

- [ ] **`README.md:230`.** The flow line reads "waves from the Tasks JSON". It now reads waves
      from each task's `needs`.

- [ ] **`README.md:270`.** The paragraph explaining that `Tasks` is a JSON block is replaced by
      one describing a task section: a yaml header for dispatch, interfaces and checkbox steps
      below it, and a pointer to `skills/crew/references/plan-format.md`.

- [ ] **`docs/design.md`.** Add a dated note under the plan schema section at `:147-156` saying
      the `Tasks` JSON block was replaced on 2026-08-10, naming
      `docs/plans/2026-08-10-plan-format-design.md`. Do not rewrite the section. It records what
      was decided then, and narrowing it on the record is the honest edit.

- [ ] **Run the check.** Expect PASS on all three clauses.

---

## Wave list

Derived from `needs`.

```
wave 0   t1
wave 1   t2  t3  t4
wave 2   t5
wave 3   t6
```

`t5` waits on `t3` rather than joining wave 1, because `crew-builder`'s contract is whatever
`crew-build` dispatches and the two must say the same thing.

t1 through t5 are one PR and t6 is the second. The split is not cosmetic: every file in t1
through t5 is read during a run, and on a `size: full` run `crew-critique` reads the plan before
Gate 1, so shipping the new format without the phases that understand it breaks a run. Nothing
in t6 is read during a run.

## Verify

Run all of these after t6, from the repository root.

```bash
# every skill body under the cap, and the frontmatter rules
for f in skills/*/SKILL.md; do
  [ "$(basename "$(dirname "$f")")" = "$(rg -m1 -or '$1' '^name: (.+)$' "$f")" ] || echo "NAME MISMATCH $f"
  [ "$(wc -l < "$f")" -lt 200 ] || echo "OVER 200 LINES $f"
done

# only the entry skill hides from model invocation
[ "$(rg -l 'disable-model-invocation' skills/*/SKILL.md)" = "skills/crew/SKILL.md" ]

# the old contract is gone from every runtime reader
! rg -i 'tasks json' skills/ agents/ README.md

# no guard uses git status. every remaining mention must be a prohibition
rg -n 'git status' skills/ agents/ | rg -v -i 'never'
# expect no output

# every guard names the snapshot helper
for f in skills/crew-build skills/crew-review skills/crew-babysit skills/crew-pr; do
  rg -q 'crew_snapshot' "$f/SKILL.md" || echo "NO SNAPSHOT $f"
done

# the plugin still loads
cursor-agent --plugin-dir . 2>&1 | rg -i 'skill|subagent'
```

Checking this took three tries, and each failure is worth keeping. A negative lookahead on
`porcelain(?!=v1 -z)` matched the reference's own prohibition, because the reference has to name
the banned form in order to ban it. Filtering on `--porcelain` alone then matched
`git worktree list --porcelain`, a different command that is correct as written, in
`crew-intake` and in `crew`'s State section. The version above works because the rule got
simpler: no guard uses `git status` at all, so any line mentioning it is prose, and prose about
a banned thing says "never".

Then run `/crew` on a real ticket through Gate 1 to a built wave, and check four things: no
sentence in `Approach` restates a task, every task section opens with a yaml header that parses
and carries `needs`, `files` and `verify`, every step whose deliverable is code shows the code,
and the wave list `crew-build` derives matches the one the plan carries.

## Non-goals

Plan size, which `2026-08-07-smaller-plans-design.md` owns. Parallel waves, the ownership guard
and the circuit breaker, all unchanged. Splitting `plan.md` into a spec and a plan. Any change
to phases, subagents, sizing, or the two gates. Any change to a model pin.
