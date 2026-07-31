# crew

A goal in, merged code out.

crew guides work through intake, research, design, adversarial critique, build, review,
PR, and merge, stopping at two human gates. You are the architect throughout — subagents
retrieve facts, write code, and attack the plan, but they never hold the design.

## Install

Cursor does not auto-load anything from `~/.cursor/plugins/local/`, and marketplace
imports may be disabled by team policy. `--plugin-dir` is the mechanism that works, so
wrap it in a shell function that expands every plugin you have linked:

```zsh
# ~/.zshrc — replaces `alias cursor="cursor-agent"`
cursor() {
  local -a plugin_flags
  local d
  for d in "$HOME"/.cursor/plugins/local/*(N-/); do
    plugin_flags+=(--plugin-dir "${d:A}")
  done
  command cursor-agent "${plugin_flags[@]}" "$@"
}
```

Then link this repo in and use `cursor` instead of `cursor-agent`:

```bash
mkdir -p ~/.cursor/plugins/local
ln -s /path/to/crew-cursor ~/.cursor/plugins/local/crew
```

It must be a function, not an alias — a zsh alias of the same name shadows the function.

### What loads where

Tested, because the documented paths do not all behave the same:

| Location | Skills | Subagents |
|---|---|---|
| `--plugin-dir` | yes | yes |
| `~/.cursor/skills/` | yes | — |
| `<repo>/.cursor/agents/` | — | yes |
| `~/.cursor/agents/` | — | no |
| `~/.cursor/plugins/local/` alone | no | no |

The agent's ambient skill list is truncated and will not show all ten. That is cosmetic:
every skill is invocable as `/name`, which is how crew loads its phases anyway.

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
  ├─ GATE 1          plan + verdict. Stop. Wait.
  │
  ├─ crew-build      waves from the Tasks JSON → parallel builders → verify each wave
  ├─ crew-review     bugbot ‖ security-review ‖ crew-conformance → coalesce → fix
  ├─ GATE 2          diff + findings. Stop. Wait.
  │
  ├─ crew-pr         stage owned files → ask → push → PR, ready for review
  ├─ crew-babysit    poll CI and threads → fix or escalate → merge when provably safe
  └─ crew-retro      route learnings, report what to clean up
```

Two gates, both human. Everything between them runs on its own.

Size is set at intake and decides what runs.

Size gates only research and critique. Every run builds, reviews, and merges.

| Size | Skips | When |
|---|---|---|
| trivial | scout and critique | Docs, comments, typos, formatting, tests. Syntactic test only. |
| standard | critique | Default |
| full | nothing | Money, auth, PII, migration, public API, concurrency, idempotency, background jobs, cross-service, feature flags, irreversible UX, observability |

## Models

| Role | Model | Why |
|---|---|---|
| Architect | yours | Holds the conversation and the code. Never delegated. |
| `crew-retriever` | `composer-2.5-fast` | Retrieval breadth, not reasoning |
| `crew-critic` | `gpt-5.5-extra-high-fast` | Top effort, 1M context, and a different family from the architect. Same-family validation is how bad plans pass. |
| `crew-builder` | `composer-2.5-fast` | The plan is locked; execution is mechanical |
| `crew-conformance` | `claude-opus-5-thinking-high` | Judging a diff against a plan is judgment, and a different family from the builders |

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
| intake, scout, design, critique | shipped |
| Gate 1 | shipped |
| build, review | shipped |
| Gate 2 | shipped |
| pr, babysit, merge | shipped |
| retro | shipped |

Out of scope: deploy, non-GitHub hosts, multi-repo runs, cloud agents, ticket creation,
worktree and branch lifecycle.

## Merging

crew merges on its own, and only when all five of these hold. Every one is a fact read
from `gh`, and none is something crew can bring about itself.

| Condition | Read from |
|---|---|
| CI green, no conflicts, base current | `mergeStateStatus == CLEAN` |
| Required approvals satisfied | `reviewDecision == APPROVED` |
| Every approval sits on the current head | `latestReviews[].commit.oid == headRefOid` |
| No open objections | zero unresolved threads |
| Both lists complete | thread and review pagination fully fetched |
| Base unchanged since the check | `baseRefOid` re-read immediately before merging |

The third is the one that does the work. `reviewDecision` is a property of the pull
request, not of a commit: a reviewer approves, crew pushes a fix, and unless the repo
dismisses stale reviews the flag still reads `APPROVED` for code nobody read.

crew also never resolves a review thread. It fixes, replies, and leaves the thread for the
reviewer, because zero unresolved threads is one of its own merge preconditions and an
agent that closes its own threads is writing its own permission slip.

The merge itself uses `--match-head-commit`, so GitHub refuses it if the head moves
mid-flight. Where branch protection requires up-to-date branches and dismisses stale
reviews, crew prefers `--auto` and lets the server enforce the policy.

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
