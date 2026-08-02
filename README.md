# crew

A goal in, merged code out.

crew guides work through intake, research, design, adversarial critique, build, review,
PR, and merge, stopping at two human gates. You are the architect throughout — subagents
retrieve facts, write code, and attack the plan, but they never hold the design.

## Install

```bash
git clone https://github.com/Herocod3r/crew-cursor && cd crew-cursor
./install.sh            # link the plugin
./install.sh shell      # add the cursor() function to your shell rc
source ~/.zshrc

cd /path/to/your/repo
/path/to/crew-cursor/install.sh agents   # once per repo you run crew in
```

`./install.sh doctor` checks every part of the install.

Two steps because Cursor loads skills and agents differently, and the per-repo one is not
optional — it is what makes the critic run on a different model family and the builders
run on the cheap one. The rest of this section is why.

### Why the shell function

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

### Plugin agents get a reduced schema

Cursor's plugin reference lists only `name` and `description` for plugin-bundled agents.
That is literal, not an omission — `model` and `readonly` are **silently dropped**:

| Field | Project `.cursor/agents/` | Plugin `--plugin-dir` |
|---|---|---|
| `name`, `description` | honoured | honoured |
| `readonly: true` | honoured | **ignored** |
| `model:` | honoured | **ignored** — inherits the parent's model |

Verified by A/B on the *same* agent file, differing only in location, with the parent on
Composer. Read the dispatch off the wire rather than asking the subagent what it is:

```bash
cursor-agent -p --output-format stream-json ... \
  | jq -r 'select(.type=="tool_call") | .tool_call.taskToolCall.args.model'
```

| Location | `model` on the wire | `readonly: true` agent asked to write |
|---|---|---|
| `.cursor/agents/` | the pinned model | refuses |
| `--plugin-dir` | the **parent's** model | writes the file |

Do not ask a subagent which model it is. Self-reports are unreliable and gave
contradictory answers for identical setups — the same plugin agent claimed "Composer"
twice and "OpenAI" once. Latency corroborates the wire: pinning a plugin agent to a flash
model versus a max-thinking model produced no meaningful difference, because both ran on
the parent.

This is not the documented fallback for admin-blocked or plan-limited models: the same
model resolves correctly from the project directory, so nothing is blocking it.

`~/.cursor/agents/` is documented as applying to all projects. **In the CLI it does not
load.** The Task tool's schema is the proof — force a dispatch and the error enumerates
what is actually registered:

```
subagent_type: Invalid enum value.
Expected 'generalPurpose' | 'cursor-guide' | 'bugbot' | 'security-review' |
'best-of-n-runner' | 'agent-creator' | 'plugin-validator' | 'skill-reviewer',
received 'crew-critic'
```

That is with all four agents sitting in `~/.cursor/agents/`. They never enter the enum, so
this is not the list truncation that affects skills. CLI `2026.07.23-e383d2b`.

Precedence, when the same agent name arrives from two places at once:

| Sources present | Enum | Which wins |
|---|---|---|
| user only | built-ins only | — |
| `--plugin-dir` only | + crew agents | plugin, reduced schema |
| `--plugin-dir` + project | + crew agents | **project**, full schema |

The last row is what makes this work: the shell function passes `--plugin-dir` on every
invocation, and the project-level symlinks still take precedence over it. Verified — with
both present, the critic reports OpenAI rather than the parent's Composer.

`install.sh` links user-level too, since it costs nothing if ignored and would remove the
per-repo step if the IDE honours it. Untested there: `~/.cursor/agents/` was empty when
the session that would have shown it began. Restart Cursor and ask an agent to list its
subagent types to find out.

So `crew-intake` symlinks the agents into the worktree's `.cursor/agents/` and adds a
local-only ignore in `.git/info/exclude`. Symlinks work there and the pin survives them,
which keeps the plugin as the single source of truth while restoring the full schema:

- the critic genuinely runs on a different model family
- builders run on `composer-2.5-fast` instead of your expensive parent model
- the read-only reviewers are read-only structurally, not by request

Because this failure is silent, `crew-critique` also has the critic report its own model
family and compares it against the orchestrator's. A same-family critic returns a
confident, agreeable review and nothing else gives it away.

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
