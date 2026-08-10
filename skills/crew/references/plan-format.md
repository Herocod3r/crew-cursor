# Task section format

One `### tN` section per task, under `## Tasks`. The section is the whole contract: a `yaml`
header for the orchestrator, then the interfaces and the steps for the builder. Nothing about a
task is written anywhere else, because a second copy is a copy that drifts.

## Shape

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

## Finding the header

Structure is only what appears **outside** a fenced block. A `### tN` heading or a `yaml` fence
inside a fence is content, which is why the example above sits in a four-backtick fence. Track
fence state while scanning; a fence opened with more backticks closes only on that many.

A task is a `### tN` heading under `## Tasks`, where N is a number. Its header is the first
fenced `yaml` block after that heading. Every later fence in the section is content.

Never collect headers by searching the file for `yaml` fences. The plan for this format did
exactly that and found seven tasks where there were six. An example task takes the id `tX` for
the same reason, so that it cannot collide with a real one even when something scans carelessly.

## Fields

| Field | Meaning |
|---|---|
| `id` | Matches the heading. `t1`, `t2`, in file order. |
| `needs` | Task ids this one waits for. `[]` puts it in wave 0. |
| `files` | Exact paths the task authors. No prefixes, no line ranges. A line hint goes in a `#` comment beside the path. |
| `generates` | Exact paths it produces but does not author — lockfiles, generated code, snapshots. `[]` when none. |
| `verify` | Always a quoted string. Checks this task alone, scoped to its own `files`. Never the whole suite. |

`verify` is quoted because a colon followed by a space separates a key from a value in yaml, and
shell commands contain both. `verify: bash -c 'echo done: ok'` is a syntax error; the same line
in quotes is a string. A header that does not parse stops the phase — that is the header earning
its place, and it is what a bullet in prose could never do.

`**Interfaces**` stays in markdown for the opposite reason. A signature like
`resolve_model_id(name: str) -> str` carries a colon and a space in the middle of the string
that has to match verbatim, and nothing computes on interfaces beyond comparing two strings.

## Paths

Entries in `files` and `generates` are exact paths and nothing is stripped from them. A path can
legitimately end in a colon and digits, so a line range never goes inside the path.

Five readers compare a changed path against a task's `files ∪ generates`: the post-wave guard,
PR staging, the review fix guard, every push babysit makes, and the conformance lane's
unowned-file finding. One owner per path across the whole plan, not per wave.

Paths are relative to the repository root, with no `./` and no `..`. Quote any path containing
`: ` or a leading character yaml would read as syntax.

## The snapshot

Every ownership guard answers one question: which paths did this dispatch change? Take a
snapshot before and after, and compare the two.

A snapshot is a git tree object of the whole working tree, untracked files included, built
through a throwaway index so the real one is never touched:

```bash
crew_snapshot() {
  local i; i="$(mktemp -u)"
  cp "$(git rev-parse --git-path index)" "$i" 2>/dev/null || true
  GIT_INDEX_FILE="$i" git add -A
  GIT_INDEX_FILE="$i" git write-tree
  rm -f "$i"
}
```

Paths changed between two snapshots, and paths changed since the last commit:

```bash
git diff-tree -r --name-only -z "$BEFORE" "$AFTER"
git diff-tree -r --name-only -z HEAD "$(crew_snapshot)"
```

Output is exact paths, NUL separated. Nothing to strip, nothing to unquote. A rename appears as
two paths, a delete and an add, which is what a task must own anyway. `.gitignore` is honoured,
so `.crew/` never enters a snapshot. Copying the index preserves its stat cache, so `add -A` is
a stat walk rather than a rehash of the repository.

**Never use `git status` for this.** Status reports the state a path is in, not whether it
changed, so a file some earlier wave left at `M` stays at `M` when a later builder edits it
again, and the guard sees nothing. Measured on a scratch repository: of three real edits across
two waves, a before-and-after status comparison found one and the tree comparison found all
three. Status also needs the two columns dropped, `-z` to stop it quoting non-ASCII paths and
writing renames as `old -> new`, and `--untracked-files=all` or a new file in a new directory is
reported as the directory. None of that applies to a tree.

## Steps

Test-first by default. Write the check, run it and watch it fail for a named reason, make the
change, run it again. The failing run is not ceremony: it is what proves the check can fail,
which is the difference between a `verify` that tests the task and one that passes on an
unchanged tree.

Where a repository has no test harness, the shape holds with the check in place of the test. An
`rg` assertion that a file does not yet say something is a failing test.

No commit step. Builders never run a git write; the orchestrator stages against the ownership
union.

## Never write these

Each is a plan failure, not a style problem. The builder cannot ask you what you meant.

- `TBD`, `TODO`, "implement later", "fill in details"
- "add appropriate error handling", "add validation", "handle edge cases"
- "similar to task N" — repeat it, because the builder cannot see task N
- a step whose deliverable is code and which shows no code
- a name, type or signature no task defines

## Header validity

A header is valid only when all of these hold. Any failure stops the phase that found it.

- It parses as yaml.
- All five keys are present. `generates: []` is written, not omitted.
- `id` matches its heading, and no two tasks share an `id`.
- `needs` is a list of ids that exist in this plan, and the graph has no cycle.
- `files` and `generates` are lists of strings. `verify` is a non-empty string.
- The number of headers equals the number of `### tN` headings under `## Tasks`.

## Wave list

The plan carries a `## Wave list` section, derived from every task's `needs` by topological
sort. `crew-build` derives it again from the same headers and stops if the two disagree. A plan
missing the section, or carrying one that does not parse, stops the phase — an absent list is
not an agreement.

One fenced block, one wave per line, ids in ascending order within a wave:

```
wave 0   t1
wave 1   t2  t3  t4
wave 2   t5
```

This is not the hand-numbering `crew-build` forbids. A hand-numbered wave is a second source of
truth that drifts from `needs`. This one is computed from `needs`, and it exists so that two
independent derivations can be compared while the human is still looking, at Gate 1.

It earns its place on the edges no interface can check. A task that needs another only for setup
order, for a shared `generates` path, or for shared `verify` state has no `Consumes` to check
against, so nothing else stands behind that edge.
