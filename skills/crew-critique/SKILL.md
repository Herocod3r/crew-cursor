---
name: crew-critique
description: Runs an adversarial critic from a different model family over plan.md, converges the findings, and presents Gate 1. Use as phase 4 of a crew run.
---

# crew-critique

Phase 4. Runs when `size: full`.

The predecessor defaulted to Opus critiquing Opus. Same-family validation is how a bad
plan gets a passing grade. The critic is a different family on purpose.

## 1. Dispatch

Run the critic as a **`cursor-agent` subprocess with an explicit `--model`**. Do not
dispatch it with the Task tool.

Subagents inherit the parent's model. The `model:` field in `agents/crew-critic.md` is not
honoured for plugin-provided agents — a probe pinned to a nonexistent model dispatched
successfully instead of erroring, and a probe pinned to a different family reported the
parent's family. A Task-dispatched critic is therefore *always* same-family, the precise
failure this phase exists to prevent. The Task `model` enum cannot rescue it either: it
holds only `composer-2.5-fast` and `claude-opus-5-thinking-max-fast`.

The CLI accepts any model from `cursor-agent --list-models`. That is the whole reason for
the subprocess.

```bash
CRITIC=$(mktemp /tmp/crew-critic-XXXX.md)
# Persona = the agent file's body, minus frontmatter.
awk 'BEGIN{n=0} /^---$/{n++; next} n>=2' "$CREW/agents/crew-critic.md" > "$CRITIC"
cat >> "$CRITIC" <<EOF

# Your task
Review the plan at $PLAN. Read the code and evidence it cites, and verify the citations.
<what to attack, specific to this plan>
Follow your output format exactly, including "Alternative not considered".
EOF

cursor-agent -p --model gpt-5.5-extra-high-fast --plan --auto-review --trust \
  --workspace "$WORKTREE" "$(cat "$CRITIC")"
```

`--plan` holds it read-only; a write attempt is refused even under `--trust`.

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
