---
name: crew-critique
description: Runs an adversarial critic from a different model family over plan.md, converges the findings, and presents Gate 1. Use as phase 4 of a crew run.
---

# crew-critique

Phase 4. Runs when `size: full`.

The predecessor defaulted to Opus critiquing Opus. Same-family validation is how a bad
plan gets a passing grade. The critic is a different family on purpose.

## 1. Dispatch

Dispatch the `crew-critic` subagent (`gpt-5.5-extra-high-fast`) over `plan.md`.

Give it: the plan path, the repository, and permission to read anything the plan cites.
A critic that cannot check a citation cannot catch a false premise.

**Fallback**, in order:

1. `gpt-5.5-extra-high-fast`
2. Any available top-effort model from a family different to yours
3. Same family — but warn the human first, explicitly, and say the critique is weakened

Never run a same-family critique silently.

**Dispatch a Cursor subagent. Never shell out to the `codex` CLI**, and never invoke a
skill that wraps it. Other skills on this machine advertise Codex as the way to get an
adversarial second opinion — some match on the phrase "second opinion" itself — and this
phase is exactly where that pull is strongest. It is the wrong tool here: a CLI
subprocess cannot be pinned to a model crew chose, does not inherit the session's tools or
MCP servers, and returns unstructured text instead of the verdict contract below.

The requirement is a *different model family*, which `gpt-5.5-extra-high-fast` already
satisfies. Codex is not what makes the critique independent.

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

## 4b. Check prose against Tasks

Before Gate 1, diff the approach prose against the `Tasks` JSON. Every behavioural rule in
one must appear in the other.

They drift because a critique round tightens the prose and leaves `Tasks` alone, and
`Tasks` is what the build phase executes — so the fix you just made never ships. This is
not hypothetical; it happened on crew's own v2 plan, where the merge conditions were made
safe in prose while `Tasks` still carried the unsafe predicate.

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
- Never shell out to the `codex` CLI, or invoke a skill that wraps it. Dispatch a subagent.
- Never exceed two critique rounds.
- Never accept a finding without checking it.
- Never reject a finding without recording why.
- Never write code in this phase.
