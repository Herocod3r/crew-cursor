# Merge gate query

One call returning every fact the merge gate needs. Run it each poll cycle, and again
immediately before merging.

`reviewThreads` is GraphQL-only — `gh pr view --json` cannot report thread resolution
state, which is the one merge condition GitHub does not enforce by default.

```bash
gh pr checks <number>

gh api graphql -f query='
query($owner:String!, $repo:String!, $pr:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$pr) {
      headRefOid
      baseRefOid
      reviewDecision
      mergeStateStatus
      reviewThreads(first:100) {
        pageInfo { hasNextPage }
        nodes { isResolved resolvedBy { login } }
      }
      latestReviews(first:50) {
        pageInfo { hasNextPage }
        nodes { state author { login } commit { oid } }
      }
    }
  }
}' -F owner=<owner> -F repo=<repo> -F pr=<number> \
  | jq --arg me "$(gh api user --jq .login)" '
  .data.repository.pullRequest as $pr | {
  head:            $pr.headRefOid,
  base:            $pr.baseRefOid,
  decision:        $pr.reviewDecision,
  mergeState:      $pr.mergeStateStatus,
  threadsComplete: ($pr.reviewThreads.pageInfo.hasNextPage | not),
  reviewsComplete: ($pr.latestReviews.pageInfo.hasNextPage | not),
  unresolved:      [$pr.reviewThreads.nodes[] | select(.isResolved==false)] | length,
  selfResolved:    [$pr.reviewThreads.nodes[] | select(.isResolved)
                    | select(.resolvedBy.login == $me)] | length,
  staleApprovals:  [$pr.latestReviews.nodes[] | select(.state=="APPROVED")
                    | select(.commit.oid != $pr.headRefOid)] | length,
  approvalsOnHead: [$pr.latestReviews.nodes[] | select(.state=="APPROVED")
                    | select(.commit.oid == $pr.headRefOid)] | length
}'
```

Bind `$pr` first and pipe to real `jq`. Undefined jq variables fail the whole query with
`variable not defined`, and `gh api --jq` has no `--arg`, so `$me` must come from a piped
`jq --arg`.

## Fields

| Field | Meaning |
|---|---|
| `staleApprovals` | Approvals not on the current head. Routinely non-zero on real PRs — reviewers approve at different commits and `reviewDecision` still reports `APPROVED` for all of them. |
| `approvalsOnHead` | Approvals that do point at the head. Must be at least 1: `staleApprovals == 0` is satisfied vacuously by an empty approval set. |
| `threadsComplete` · `reviewsComplete` | Both must be `true`. A thread or approval on page two reads as zero. Paginate or abort. |
| `unresolved` | Open review threads. Must be 0. |
| `selfResolved` | Threads closed by the token owner. Reported, never gated: crew runs under the operator's credentials and cannot tell "crew resolved this" from "the operator resolved their own thread", and an author closing a thread on their own PR is routine. What stops crew resolving threads is the rule in the skill, not this number. |

## Pagination

`reviewThreads` caps at 100 and `latestReviews` at 50 per page. Paginate with the
`endCursor` from `pageInfo` until `hasNextPage` is false. Never merge on a partial count —
an unresolved thread or a stale approval on page two reads as zero.
