---
name: crew-critique
description: Runs an adversarial critic from a different model family over plan.md, converges the findings, and presents Gate 1. Use as phase 4 of a crew run.
---

# crew-critique

Phase 4. Runs when `size: full`.

The predecessor defaulted to Opus critiquing Opus. Same-family validation is how a bad
plan gets a passing grade. The critic is a different family on purpose.

## 1. Dispatch

Dispatch the `crew-critic` subagent over `plan.md`, by `subagent_type` alone. Never pass a
model parameter — the Task enum holds only `composer-2.5-fast` and
`claude-opus-5-thinking-max-fast`, so naming the critic's model gets it rejected.

The model comes from `agents/crew-critic.md`, which works **only because intake symlinked
the agents into `.cursor/agents/`**. Plugin-bundled agents silently ignore `model`, so
without that link the critic runs on your model and the critique is same-family.

Give it the plan path and permission to read anything the plan cites. A critic that cannot
check a citation cannot catch a false premise.

### Verify the critique was actually independent

The critic's first output section reports its model family. Compare it against yours.

| Result | Action |
|---|---|
| Different family | Proceed. |
| Same family | Say so at Gate 1, plainly, and record the critique as weakened. |

Do this every round. The failure is silent by construction — a same-family critic returns
a confident, well-formatted, agreeable review, and nothing else signals the problem.

**The fallback fires only when the dispatch itself fails.** A `crew-critic` subagent that
returned is the critique. Do not run the subprocess as well, and never run it because you want a
second opinion on the first one.

That happened on `archmds-1198`: `crew-critic` was dispatched and returned, and the subprocess
was then run twice anyway, blocking five minutes and ten. Both calls named
`claude-opus-5-thinking-max-fast`, the same family as the orchestrator, so fifteen minutes bought
a critique with exactly the independence this phase exists to guarantee against.

Two conditions, both required, before shelling out. The subagent dispatch failed. And the
`--model` you name is a different family from your own — check it before running, because a
same-family subprocess is strictly worse than the subagent you just failed to get.

```bash
cursor-agent -p --model gpt-5.5-extra-high-fast --plan --auto-review --trust \
  --workspace "$WORKTREE" "$(cat "$CRITIC_PROMPT")"
```

where `$CRITIC_PROMPT` is the body of `agents/crew-critic.md` minus frontmatter, plus the
task. The CLI accepts any model from `cursor-agent --list-models`, unlike the Task enum.
Slower and without shared context, but genuinely cross-family.

**Never shell out to the `codex` CLI**, and never invoke a skill that wraps it. Other
skills on this machine advertise Codex as the route to an adversarial second opinion, some
matching on the phrase "second opinion" itself, and this phase is where that pull is
strongest. Independence comes from a different *model family*, not from Codex, and
`cursor-agent --model` supplies it while keeping the output contract below.

**Fallback**, in order. Only on genuine failure — a rejected model parameter is a dispatch
bug, not an unavailable model.

1. `cursor-agent --model gpt-5.5-extra-high-fast`
2. `cursor-agent --model` with any available top-effort model from a different family
3. A Task subagent, which is same-family — warn the human explicitly and record the
   critique as weakened at Gate 1

Never run a same-family critique silently.

## 2. Read the verdict

| Verdict | Meaning |
|---|---|
| `BLOCK` | Ship-stopping problems. Fix and re-critique. |
| `REVISE` | Major issues, no redesign needed. Fix; re-critique only if a blocker appears. |
| `PROCEED` | Minor only. Fix or note them. Go to Gate 1. |

Record `verdict`, counts, and `round` in `state.json.critique`.

## 3. Converge

Resolve findings and re-critique **only while blockers remain. Two rounds maximum.**

After two rounds, stop. Present what is unresolved at Gate 1 and let the human decide.
A third round is the critic and the author disagreeing, not the plan improving.

Round two must tell the critic what it said in round one and what changed, and ask it to
mark each prior finding resolved, partial, or unresolved. Otherwise it re-litigates.

## 4. Disagree deliberately

You may reject a finding. Rejecting is a decision, so it gets recorded like one: add it
to `Decisions` in `plan.md` with your reason, and surface it at Gate 1.

Verify before you accept, too. The critic is confident by construction and will
occasionally be confidently wrong. Check its claims against the code the way it was
asked to check yours.

Read `Alternative not considered` properly. It is the one section written free of the
plan's framing, and it is where an approach you never evaluated shows up.

## 4b. Re-check the plan against itself

Any round that edited the plan invalidates the checks from `crew-design` section 6. Run all
of them again before Gate 1.

A round that edits a task must leave that task's `yaml` header, its `Interfaces` and its steps
saying the same thing. Tightening a step and leaving the header alone is the same defect the
old format had between prose and `Tasks`, moved inside one section, and the section 6 table is
what proves it did not happen.

Interfaces break the most quietly. Renaming a symbol in one task's `Produces` and not in its
consumers' `Consumes` reads as a clean edit and lands as two names for one thing.

## 5. Gate 1

Set `phase` to `gate1`. Present, then stop:

- The plan, or its path
- Verdict and counts
- Findings you rejected, and why
- Anything in `Assumptions`
- Anything the critic raised that you could not resolve in two rounds

Set `gates.g1` only after the human says go. Never infer approval from silence, from a
question, or from a comment about something else.

## Never

- Never run a same-family critique without warning.
- Never shell out to `cursor-agent` after a `crew-critic` dispatch returned. That is the critique.
- Never shell out on a model from your own family. A same-family subprocess buys nothing and costs minutes.
- Never shell out to the `codex` CLI, or invoke a skill that wraps it. Dispatch a subagent.
- Never exceed two critique rounds.
- Never accept a finding without checking it.
- Never reject a finding without recording why.
- Never write code in this phase.
