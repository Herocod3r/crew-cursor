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

Pass: plan path (`<repoRoot>/.crew/<slug>/plan.md`), worktree path, and the changed-path list
from `git diff-tree -r --name-only -z HEAD "$(crew_snapshot)"`. The agent reads the diff itself,
but `git diff` omits untracked files, so a builder's new file would be invisible to it and its
unowned-file finding would come back clean when it is not. Follow its output format in
`agents/crew-conformance.md`.

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

Dispatch in fix mode, which the builder handles differently from a task. Pass: the finding
(location, problem, suggested fix), the owning task's brief path, the plan's
`## Global Constraints` block, the worktree path, and an **explicit allowed-path list** — the
`files ∪ generates` of the task sections involved, narrowed to the paths the finding concerns.
The builder changes code only, no commits.

Take a `crew_snapshot` before each fix dispatch and another after, then compare them with
`git diff-tree -r --name-only -z`, per `skills/crew/references/plan-format.md`. Judge that
delta against the finding's allowed list.

Three traps here. Never judge a `git status` listing: the tree is dirty from the whole build,
so every task's files appear and all of them read as outside a narrow allowed list. Never use
status as the snapshot either — a file the build left at `M` stays at `M` when the fix touches
it again, so the one thing the guard exists to catch is the one thing it would miss. And never
compare against the plan union instead of the finding's list, because the union passes any file
the plan touches anywhere, which lets a one-line fix silently broaden the diff. Anything
outside the allowed list is escalated, never kept silently.

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

After the fix loop, before Gate 2. Read `## Verify` in `plan.md`. Treat each fenced
`bash` block as one command: deduplicate exact block contents and run each once from the
worktree root in a fail-fast shell. Execute with `bash -euo pipefail -c "$block"`. Run prose
manual checks once after the blocks.

Persist `reviewVerify` in `state.json`. Before each command, write enough running evidence
to identify it and set `status` to `running`. On resume with `running`, continue observing
the same live process when possible. If no live process exists, append interrupted `fail`
evidence, set `status` to `fail`, set `phase` to `gate2`, write state, and present blocked Gate 2. Never start a duplicate automatically. Set the final status plus check summaries before Gate 2. Aggregate success: all checks pass → `pass`; any proved gap and no failure → `environment_gap`.

- Run proof commands directly. Do not pipe them through `tail`, `head`, `rg`, or another
  output filter that changes which exit status is observed.
- Keep one process per command. If the user asks for status, report and continue the same running command.
- A code failure stops the phase. Append evidence, set `reviewVerify.status` to `fail` and
  `phase` to `gate2`, write state once, then present blocked Gate 2 with the exact command,
  exit status, and output. Do not dispatch another builder or change the reviewed diff.
- Persist every check result in `reviewVerify.evidence`.
- A malformed invocation can be corrected once.
- A missing prerequisite is an environment gap only after proving it is outside the repository,
  unchanged by the diff, and not replaceable by another local proof. Repo-controlled fixtures,
  generated files, scripts, and harness dependencies are failures. A proved gap is not a pass
  and requires explicit human acceptance at Gate 2.

## 5. Gate 2

Set `phase` to `gate2`. Present, then stop:

- What changed, by file
- Coalesced findings: what was fixed, what was not, and why
- Findings you rejected, and why
- Whole-run verification: every command and prose manual check from `reviewVerify.evidence`
  as `pass`, `fail`, or `environment gap`. An unresolved failure blocks. A proved environment
  gap remains visible and needs explicit acceptance; silence never becomes approval.
- Anything the circuit breaker stopped (build or review)
- Anything review raised that two fix rounds did not close

Set `gates.g2` only after the human says go. Never infer approval from silence, from a
question, or from a comment about something else. Cannot approve while `reviewVerify.status`
is `pending`, `running`, or `fail`; `environment_gap` requires explicit acceptance.

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
- Never set `gates.g2` without explicit human approval or while `reviewVerify.status` is `pending`, `running`, or `fail`.
- Never advance past Gate 2 without writing `state.json`.
