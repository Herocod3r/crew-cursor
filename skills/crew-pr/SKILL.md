---
name: crew-pr
description: Stages task-owned files, commits, pushes, and opens a ready-for-review PR with the repo template filled. Use as phase 7 of a crew run.
---

# crew-pr

Phase 7. Gate 2 is approved. Everything from here is outward-facing.

Set `phase` to `pr` in `state.json` on entry. Write state on entry, not on exit — a crash
mid-phase must resume into PR, not skip it.

Read the `yaml` header of every `### tN` section in `<repoRoot>/.crew/<slug>/plan.md`, per
`skills/crew/references/plan-format.md`. Work in `state.json.git.worktreePath` on branch
`state.json.git.branch`.

## 1. Compute the staging set

Ownership is `files ∪ generates` for every task. PR staging uses the **union across all
tasks** — the same contract as build dispatch and the post-wave guard.

Never `git add .` or `git add -A`. Stage named paths only:

```bash
git -C <worktreePath> add -- <path1> <path2> …
```

## 2. Guard the tree

```bash
git -C <worktreePath> status --porcelain=v1 -z --untracked-files=all
```

Exactly this string. Without `-z` a rename is one entry with an arrow and non-ASCII paths come
back quoted; without `--untracked-files=all` a new file in a new directory is reported as the
directory. Each would read as a path no task owns. Reading rules in
`skills/crew/references/plan-format.md`.

Every changed path in the worktree must appear in some task's `files ∪ generates`, and a
rename contributes both of its paths.

| Situation | Action |
|---|---|
| Path in the union | OK to stage |
| Path outside the union | Stop. Escalate to the human. Never stage. Never discard. |

The build phase's post-wave guard should have caught this. Reaching PR with unowned
changes means a guard missed something — do not absorb it silently.

## 3. Ask before push

**Ask before any outward-facing action.** Push is the first one in this phase.

Present:

| Field | Source |
|---|---|
| Branch | `state.json.git.branch` |
| Staging set | union of every task's `files` and `generates` |
| Goal | `state.json.goal` |
| Plan | `<repoRoot>/.crew/<slug>/plan.md` |

```
Ready to commit, push <branch>, and open a PR?
Proceed? (yes / no / edit commit message)
```

Do NOT commit, push, or open a PR until the human confirms. If no, stop with `phase: pr`.

## 4. Commit and push

After confirmation:

```bash
git -C <worktreePath> commit -m "<goal summary>

<slug> — crew implementation pass
Refs: <ticketRefs if any>"
git push -u origin <branch>
```

Stage only the union from step 1. Nothing else.

## 5. Resolve the PR template

Read the repo template first — fill its sections, do not replace them:

```bash
gh api repos/{owner}/{repo}/contents/.github/pull_request_template.md \
  --jq '.content' | base64 -d
```

| Template exists | Action |
|---|---|
| Yes | Map each section heading to content: goal, what changed (by task), how verified (task `verify` commands and review summary), link to plan |
| No | Sensible fallback body: goal, what changed, how it was verified, link to `<repoRoot>/.crew/<slug>/plan.md` |

Merge structure with the template. Do not discard required sections the repo expects.

## 6. Open the PR

Open **ready for review**, not draft. A draft cannot collect approvals or auto-merge, so
drafting strands the run one manual step short of the merge the human authorized at Gate 2.
The predecessor opened draft always; crew v2 reverses that. Safe because babysit pins
approvals to the live head SHA — a premature approval stops counting the moment anything
is pushed.

```bash
gh pr create \
  --title "<goal summary>" \
  --body "<filled template or fallback>"
```

Do NOT pass `--draft`.

Capture the PR head SHA immediately after create:

```bash
gh pr view <number> --json headRefOid,url,number
```

## 7. Record state

Write into `state.json.pr`:

| Field | Value |
|---|---|
| `url` | PR URL from `gh pr view` |
| `number` | PR number |
| `headSha` | `headRefOid` at open time |

`headSha` is the commit the PR opened at, recorded for the run log. It is not the merge
check — babysit compares `latestReviews[].commit.oid` against the live `headRefOid` from
GitHub, because the stored value goes stale the moment anything is pushed.

If `pr` is `null` rather than an object — a run created before the object shape existed —
replace the whole value with `{"url": null, "number": null, "headSha": null, "merged":
false}` before writing any field into it.

Mirror `phase`, `gates`, and `pr` fields in `plan.md` frontmatter. `state.json` wins on
conflict.

## 8. Hand off

Set `phase` to `babysit`. Load and follow `crew-babysit`.

## Never

- Never commit, push, or open a PR before Gate 2 is approved.
- Never push without explicit human confirmation.
- Never `git add .` or `git add -A` — stage only the union of `files` and `generates`.
- Never stage or discard a path outside that union — escalate instead.
- Never open a draft PR.
- Never replace the repo PR template — fill its sections.
- Never hardcode secrets or tokens in the commit message or PR body.
- Never skip recording `pr.url`, `pr.number`, and `pr.headSha`.
