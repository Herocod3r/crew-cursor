# crew

A goal in, an approved implementation plan out.

crew guides work through intake, research, design, and adversarial critique, then stops
at a human gate. You are the architect throughout — subagents retrieve facts and attack
the plan, but they never hold the design.

## Install

```bash
ln -s /Users/jethroekozin/Documents/projects/crew-cursor ~/.cursor/plugins/local/crew
```

Then restart Cursor, or run **Developer: Reload Window**.

## Use

```
/crew <goal|TICKET>          start a run
/crew                        list active runs, resume one
```

Run it from a git worktree you created. crew verifies it is in one and refuses to start
otherwise. It never creates, moves, or deletes a worktree or branch.

## Flow

```
/crew <goal>
  │
  ├─ crew-intake     preconditions → restate → ground → size → slug → state
  ├─ crew-scout      you read the code; 2-4 external sources in one parallel round
  ├─ crew-design     close unknowns → one question at a time → plan.md
  ├─ crew-critique   different-family critic → BLOCK | REVISE | PROCEED
  └─ GATE 1          plan + verdict. Stop. Wait.
```

Size is set at intake and decides what runs.

| Size | Phases | When |
|---|---|---|
| trivial | intake, design | Docs, comments, typos, formatting, tests. Syntactic test only. |
| standard | + scout | Default |
| full | + critique | Money, auth, PII, migration, public API, concurrency, idempotency, background jobs, cross-service, feature flags, irreversible UX, observability |

## Models

| Role | Model | Why |
|---|---|---|
| Architect | yours | Holds the conversation and the code. Never delegated. |
| `crew-retriever` | `composer-2.5-fast` | Retrieval breadth, not reasoning |
| `crew-critic` | `gpt-5.5-extra-high-fast` | Top effort, 1M context, and a different family from the architect. Same-family validation is how bad plans pass. |

## Files per run

Two, at `<main-checkout>/.crew/<slug>/`, git-ignored, surviving worktree teardown.

| File | For |
|---|---|
| `plan.md` | You. Goal, why, decisions, assumptions, approach, tasks, verify, non-goals. |
| `state.json` | The machine. Phase, size, gates, critique counts, git context. |

`Tasks` inside `plan.md` is a JSON block, not prose — it is the contract the build phase
will consume without reinterpreting it.

## Status

| Phase | State |
|---|---|
| intake, scout, design, critique, Gate 1 | shipped |
| build, review, Gate 2 | not built |
| PR, babysit, merge | not built |
| retro | not built |

After Gate 1, hand `plan.md` to whatever builds it.

## Design notes

crew replaces a Claude Code plugin that was slow, artifact-heavy, and produced weak
designs. Four causes, verified against its source, each addressed here:

| Cause | Fix |
|---|---|
| Every design question cost a full subagent round trip | The architect is the main agent. Design is a conversation. |
| The architect was told to produce a complete artifact with coverage maps and code samples for every interface | The design skill forbids both. Length is not thoroughness. |
| Opus critiqued Opus | The critic is always a different model family, and says so out loud if it cannot be. |
| Three gates, thirteen stages, five artifacts | Two gates, ten phases, two files. |

Two things the predecessor got right and were kept: scouting was already selective, and
facts were required to be sufficient before design started.
