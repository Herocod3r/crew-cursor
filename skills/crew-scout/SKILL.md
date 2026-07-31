---
name: crew-scout
description: Establishes facts for a crew run. Reads the codebase directly and dispatches parallel subagents to the external sources this specific problem needs. Use as phase 2 of a crew run.
---

# crew-scout

Phase 2. Facts before design. Skipped when `size: trivial`.

## Read the code yourself

You are the architect. Read the codebase directly with your own tools.

Never delegate codebase reading to a subagent. Design quality depends on holding the real
code, not a summary of it. A subagent returns 400 words about a file you could have read.

## Select sources

Name the external sources this problem actually needs. Usually two to four. Never all of
them, and never a fixed set — relevance is per-problem.

| Source | Use for | Reached by |
|---|---|---|
| Sourcegraph | Cross-repo patterns, who else calls this, prior art in other services | `src` CLI |
| GitHub | PR history, why this code looks like this, recent related changes | GitHub MCP |
| Jira | Ticket detail, acceptance criteria, linked work | Atlassian MCP |
| Confluence | Specs, runbooks, architecture decisions | Atlassian MCP |
| Glean | Anything internal you cannot place — the catch-all | Glean MCP |
| Slack | Recent decisions and context that never made it into a doc | Slack plugin skills |
| Snowflake | Actual data shape and volume, rather than assumed | `snow` CLI |
| Datadog | Production behavior, error rates, latency | `pup` CLI or Datadog MCP |
| Web | External library, API, protocol, or standard | WebSearch, WebFetch |

State which you picked and why, in one line. Then dispatch them in a single parallel
round using the `crew-retriever` subagent, one source each. One round, not a conversation.

## Status contract

Every source returns a status. Handle it.

| Status | Handling |
|---|---|
| `ok` | Use the findings. |
| `empty` | Record as a gap. Feeds fact sufficiency. |
| `unauthenticated` | Tell the human exactly what to authenticate. Continue. Record as a gap. |
| `unavailable` | Retry once. Then record as a gap. |

Never present a design as fact-grounded when a source it depends on returned anything
other than `ok`. Say which source failed and what the design assumes in its absence.

## Record

Facts land in `plan.md` under `Why`, each with a citation: `file:line`, URL, or ticket
key. Gaps carry into the design phase and must be closed, supplied, or recorded as
assumptions there.

There is no separate facts document. Two files per run, no more.

Set `phase` to `design`. Load `crew-design`.

## Never

- Never delegate reading this repository's code.
- Never fan out to every source because it is thorough. It is slow, and the predecessor already learned this.
- Never let an uncited claim into `Why`.
- Never treat a failed source as if it returned nothing relevant.
