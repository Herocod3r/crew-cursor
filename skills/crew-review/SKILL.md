---
name: crew-review
description: Runs three parallel review lanes over the uncommitted diff, coalesces findings, routes fixes through builders, and presents Gate 2. Use as phase 6 of a crew run.
---

# crew-review

Phase 6. Build passed. You orchestrate; lanes review; builders fix.

Set `phase` to `review` in `state.json` on entry. Write state on entry, not on exit — a
crash mid-review must resume into review, not skip it.

Review runs before the commit. The diff is the working tree: `uncommitted changes`.

## 1. Dispatch

Dispatch all three lanes in **one parallel round**. Do not wait for one lane before
starting the next.

| Lane | Agent | Looks for |
|---|---|---|
| Bugs | `bugbot` (built-in) | Correctness |
| Security | `security-review` (built-in) | Secrets, authz, injection |
| Conformance | `crew-conformance` | Plan delivery and over-building |

Both built-ins compute their own diff from the repository path. Do not compute the diff
yourself before launching them.

### bugbot

Launch exactly one `bugbot` subagent:

- `run_in_background: false`
- `description: "Bugbot"`
- `subagent_type: "bugbot"`

Prompt:

```text
Full Repository Path: <absolute worktree path from state.json.git.worktreePath>
Diff: uncommitted changes
```

### security-review

Launch exactly one `security-review` subagent:

- `run_in_background: false`
- `description: "Security Review"`
- `subagent_type: "security-review"`

Same prompt shape as `bugbot`.

### crew-conformance

Launch exactly one `crew-conformance` subagent, by `subagent_type` alone. Its model and
`readonly: true` are pinned in `agents/crew-conformance.md`; never pass a model parameter.

Pass: plan path (`<repoRoot>/.crew/<slug>/plan.md`), worktree path. The agent reads the
diff itself. Follow its output format in `agents/crew-conformance.md`.

### Isolation

**Lanes never see the builders' notes.** Do not pass builder output, task reports, or
orchestrator commentary to any lane. A reviewer told what the author intended reviews the
intention, not the code.

### Built-in override

The built-in review skills end with "do not fix findings." **crew overrides that.** Fixing
findings is the point of this phase. Dispatch builders after coalescing; do not treat the
built-in "do not fix" line as a stop for crew runs.

### Lane failures

Bad invocation — missing path, wrong prompt shape, wrong subagent type — correct it and
retry immediately. Any other failure: retry once. If it persists, mark the lane
`unavailable` and stop retrying.

Never treat an `unavailable` lane as a clean one. Silence is not a pass. Name which lanes
ran and which did not at Gate 2: two of three down means the diff is substantially
unreviewed, and only the human decides whether that is acceptable.

## 2. Coalesce

You coalesce all lane output. No judge agent — with three lanes a fourth round trip buys
nothing.

| Step | Action |
|---|---|
| Dedupe | Same issue from two lanes → one finding, keep the sharper write-up |
| Drop | False positives — verify against the code before you keep a finding |
| Rank | Severity first, then impact |

Record which lane raised each finding. Re-review routes back through that lane only.

You may reject a finding. Rejecting is a decision — note it for Gate 2 with your reason.

## 3. Fix loop

Dispatch `crew-builder` by `subagent_type` alone for each fix — its model is pinned in its
agent definition, so never pass a model parameter. One finding per dispatch when
fixes touch different files; batch only when the same builder owns every path.

Pass: the finding (location, problem, suggested fix), the owning task id if known, the task's
brief path, worktree path, and an **explicit allowed-path list** — the `files ∪ generates` of
the task sections involved, narrowed to the paths the finding concerns. The builder changes
code only, no commits.

After each fix, run `git status --porcelain=v1 -z` — never the plain form, which hides
renames and quotes non-ASCII paths, per `skills/crew/references/plan-format.md` — and compare
against **that finding's allowed list**, not the whole plan union. Comparing against the union would pass any file the plan
touches anywhere, which lets a one-line fix silently broaden the diff. Anything outside the
allowed list is escalated, never kept silently.

After each fix, **re-review only the fix** through **only the lane that raised it**. Do
not re-run the full diff through all three lanes for a two-line change.

| Round | What runs |
|---|---|
| 1 | All three lanes on the full uncommitted diff → coalesce → fix → targeted re-review |
| 2 | Targeted re-review on remaining findings only → fix → targeted re-review |

Two fix rounds maximum. After round two, stop. Surface what remains at Gate 2.

Targeted re-review prompt for built-ins: same shape as round one, plus a line naming the
prior finding and the paths changed for the fix. For `crew-conformance`, pass the prior
finding and ask whether the fix resolves it — still no builder notes.

## 4. Verify the whole run

After the fix loop, read `reviewVerify.status`. If `running`, stop and surface the in-flight
command — do not start another process. Report status and continue the same running command.

Read the plan's `## Verify` section. Set `reviewVerify.status` to `running`, clear or init
`reviewVerify.evidence`, write `state.json`, then run checks. Each fenced `bash` block is one
command — deduplicate exact block contents, then run each block once from the worktree root as
`bash -euo pipefail -c "$block"`. Run prose manual checks once after the blocks. After each
block and each prose check, append a summary to `reviewVerify.evidence` (`pass`, `fail`, or
`environment gap`, plus command or check name, exit status, and output). Set the final
`reviewVerify.status` (`pass`, `fail`, or `environment_gap`) and write `state.json` before §5.

- Run proof commands directly. Do not pipe them through `tail`, `head`, `rg`, or another
  output filter that changes which exit status is observed.
- Keep one process per command. If the user asks for status, report and continue the same running command.
- A code failure: append `fail` evidence, set `reviewVerify.status` to `fail`, write `state.json`,
  set `phase` to `gate2`, and present a **BLOCKED** Gate 2 with the exact command, exit status,
  and output. Do not dispatch another builder or change the reviewed diff.
- Persist every check result in `reviewVerify.evidence`. Gate 2 cannot be approved while
  `reviewVerify.status` is `pending`, `running`, or `fail`; `environment_gap` requires explicit
  acceptance.
- A malformed invocation can be corrected once.
- A missing prerequisite is an **environment gap** only after proving it is outside the repository,
  unchanged by the diff, and not replaceable by another local proof. Repo-controlled fixtures,
  generated files, scripts, and harness dependencies are failures. A proved gap is not a pass
  and requires explicit human acceptance at Gate 2.

## 5. Gate 2

Set `phase` to `gate2`. Present, then stop:

- What changed, by file
- Coalesced findings: what was fixed, what was not, and why
- Findings you rejected, and why
- Anything the circuit breaker stopped (build or review)
- Anything review raised that two fix rounds did not close
- Every fenced `bash` block and every prose manual check from the plan's `## Verify` section:
  `pass`, `fail`, or `environment gap`. An unresolved failure blocks approval. A proved
  environment gap remains visible and needs explicit acceptance; silence never becomes approval.

Set `gates.g2` only after the human says go. Never approve while `reviewVerify.status` is
`pending`, `running`, or `fail`. `pass` allows approval. `environment_gap` requires explicit
human acceptance. Never infer approval from silence, from a question, or from a comment about
something else.

Everything after Gate 2 is outward-facing — push, PR, merge. That is what the gate is for.

On approval: set `phase` to `pr`. Load and follow `crew-pr`.

## Never

- Never dispatch review lanes sequentially when they can run in parallel.
- Never pass builder notes, task reports, or orchestrator commentary to a review lane.
- Never use `branch changes` for crew review — the diff is uncommitted, pre-commit.
- Never run a judge agent to merge lane output.
- Never re-review the full diff when only a fix changed.
- Never re-run a lane that did not raise the finding being re-checked.
- Never exceed two fix rounds.
- Never fix findings yourself — builders own mechanical fixes.
- Never commit, push, or stage in this phase.
- Never set `gates.g2` without explicit human approval.
- Never advance past Gate 2 without writing `state.json`.
