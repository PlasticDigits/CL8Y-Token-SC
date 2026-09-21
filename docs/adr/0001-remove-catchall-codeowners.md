# ADR 0001: Remove catch-all CODEOWNERS

Status: **Proposed** — [#3](https://git.cl8y.com/code/CL8Y-Token-SC/issues/3).
Keywords in that issue are not architecture approval. Ordinary design is not
a founder card. This ADR does not authorize deploy, spend, custody rotation,
or Forgejo protection PATCH
([agent-control #297](https://git.cl8y.com/PlasticDigits/cl8y-agent-control/issues/297)
/ [ADR 0004](https://git.cl8y.com/PlasticDigits/cl8y-agent-control/src/branch/main/docs/adr/0004-autonomy-policy.md)).

Date: 2026-09-21

Overview: [`architecture.md`](../architecture.md). Org policy:
[cl8y-forgejo#48](https://git.cl8y.com/PlasticDigits/cl8y-forgejo/issues/48).
CAC skip class (do not dismiss reviewers, do not delete CODEOWNERS from
drain): [cl8y-agent-control#388](https://git.cl8y.com/PlasticDigits/cl8y-agent-control/issues/388).
This ticket **is** the product-tree delete; drain agents still must not
delete the file as a workaround.

No in-repo issue dependencies.

## Outcome

1. **No plant.** After land, Forgejo does not request official review from
   `@code/maintainers` (or any team/user) on every change. Files
   `CODEOWNERS`, `docs/CODEOWNERS`, and `.forgejo/CODEOWNERS` are absent.
2. **Merge gates unchanged.** Direct `main` stays closed. Required status
   context remains `ci/woodpecker/pr/woodpecker`. Merge stays `Do: merge`
   with `head_commit_id`. Never `force_merge`.
3. **No on-chain change.** Solidity, scripts, and deployed addresses are
   untouched.

Live protection on this repo (GET, 2026-09-21) already matches the forge
template intended by #48: `enable_push=false`,
`enable_status_check=true` with `ci/woodpecker/pr/woodpecker`,
`required_approvals=0`, `block_on_official_review_requests=false`,
`block_on_rejected_reviews=true`. This ADR does **not** treat that GET as
permission to PATCH protection from implement.

## Context

`main` currently has a root [`CODEOWNERS`](../../CODEOWNERS) (commit
`ad6bbd7`) whose only rule is Forgejo Go-regexp `.* @code/maintainers`.
Forgejo plants official review requests from that file. With a one-person
maintainers team the PR author cannot approve their own pull (405 official
review / 422 self-approve). CAC autoland/drain then skip
(`DrainSkip::OfficialReview`); they must not `force_merge`, dismiss
reviewers, or delete CODEOWNERS ([#388](https://git.cl8y.com/PlasticDigits/cl8y-agent-control/issues/388)).

cl8y-forgejo#48 is the org reversal: stop official-review as a merge gate
on `code/*` and `PlasticDigits/*`, stop migrate/apply from re-planting
templates, keep push + Woodpecker. AC5 of that ticket is per-repo removal
of catch-all CODEOWNERS **via PR**. This repository's occupying work is
pull [`#3`](https://git.cl8y.com/code/CL8Y-Token-SC/pulls/3)
(`chore/remove-catchall-codeowners`, delete-only today).

Deleting the file without flipping `block_on_official_review_requests` can
still 405 if leftover official requests remain on an open PR. Protection
here is already `false`; new PRs after this land must not get a new plant.
Leftover requests on already-open PRs are not dismissed by implement.

## Non-goals

- PATCH Forgejo branch protection, `apply_repo_policy.py`, or migrate
  templates (cl8y-forgejo#48).
- Edit CAC `autoland` / `merge_drain` / `autonomy.rs` / HMAC, dismiss
  reviewers, or retire `DrainSkip::OfficialReview` (optional CAC follow-up).
- Add path-specific CODEOWNERS, required approvals, or a second human
  reviewer.
- Drop or fake `ci/woodpecker/pr/woodpecker`; add a required push context
  on PR tips; POST fake commit statuses.
- `force_merge`, direct push to `main`, or enabling `enable_push`.
- Solidity, deploy scripts, AccessManager, keys, Coolify, or spend.
- Sibling PR `issue/3` while `#3` is open.
- Founder card for this ordinary chrome change.
- Rewriting [`README.md`](../../README.md) token narrative.

## Component / state / interface changes

| Surface | Change |
| --- | --- |
| `CODEOWNERS` (root) | Delete. Do not recreate under `docs/` or `.forgejo/`. |
| `.gitignore` | Stop ignoring all of `docs/` (Foundry default). Ignore only `forge doc` output (`docs/book/`, `docs/src/`, `docs/book.toml`) so this ADR and overview are versioned. |
| `docs/architecture.md` | Merge-plane map (this change). |
| `.woodpecker.yml` | Add a filesystem assertion that the three Forgejo CODEOWNERS paths are absent. Keep the existing nonempty-tree step. |
| Branch protection JSON | No change from this repo. |
| On-chain / Foundry tests of contracts | No change. |

Forgejo CODEOWNERS lookup is root, `docs/`, or `.forgejo/` (Go-regexp, not
GitHub globs). A catch-all is any `.*` team/user rule in those files.

## Affected invariants

This repo had no local invariant file. After this ADR the merge-plane table
in [`architecture.md`](../architecture.md) is the local contract:

- No catch-all (and no CODEOWNERS file at lookup paths) on `main`.
- No direct `main`; Woodpecker PR context required; no `force_merge`.
- Rejected reviews still block; official CODEOWNERS review does not.

Do not weaken cl8y-forgejo protection invariants from product commits.
CAC invariants 29 / 67 / #388 stay: skip official-review deadlock; never
`force_merge`; drain does not delete CODEOWNERS. Product land makes the
skip class stop firing **for this repo** once new PRs have no plant.

## Alternatives

| Option | Why not |
| --- | --- |
| Keep file; operators dismiss self-request | The plant is the bug. Manual dismiss does not scale; drain forbids dismiss. |
| Keep file; CAC dismisses or `force_merge` | Forbidden by #388 / merge policy. |
| Path-specific CODEOWNERS | Out of scope; still plants official review on matching paths. |
| Wait for forge #48 only | Protection can already be off; the file still plants requests and re-infects if protection regresses. AC5 is the product delete. |
| Required approvals = 1 | Same self-approve deadlock with a one-person team. |

## Complexity added / removed

**Removed:** official review plant on every change; self-approve 405/422
class for this repo's later PRs; operator dismiss-to-land ritual.

**Added:** two tracked docs files, a `.gitignore` carve-out, and a tiny CI
existence check. No new runtime, no new merge API.

## Migration

Git only. No contract migration, no Coolify, no token move.

Open PRs opened while root `CODEOWNERS` existed may still show a leftover
official request. Implement does **not** dismiss them. After this lands,
new PRs must not receive a CODEOWNERS plant from this tree.

Occupying pull **#3** already deletes the file. Implementation **reuses**
`chore/remove-catchall-codeowners` / `#3`: preserve this ADR and overview
on that head. Do not open `issue/3`. Title/body need no extra `Fixes #3`
(the pull **is** iid 3).

## Observability

- Forgejo PR “Reviews”: no official CODEOWNERS request on PRs opened after
  land.
- Protection GET (operator): still `enable_push=false`, status context
  `ci/woodpecker/pr/woodpecker`, `block_on_official_review_requests=false`.
  Not a CI job in this repo (no Forgejo admin token in Woodpecker).
- CAC drain skip comments mentioning official CODEOWNERS should stop for
  **new** occupying PRs on this path. No `/health` or `/status` change.

## Failure modes

| Failure | Behavior |
| --- | --- |
| File deleted; leftover official request on an old PR | Protection here does not block on official review. Do not dismiss; do not `force_merge`. |
| File deleted; protection later PATCHed back to official-review block | New PRs still have no plant. Old leftover requests could 405 until they expire or a human dismisses. Re-planting CODEOWNERS is a regression. |
| CODEOWNERS re-added on a later PR | Woodpecker absence check fails; do not merge that tip. |
| `docs/` gitignore swallows this ADR | `.gitignore` carve-out; design files must be tracked. |
| Sibling PR `issue/3` | Occupancy violation. Update `#3` only. |
| Implement PATCHes protection or edits CAC | Out of authority / wrong repo. |
| `force_merge` to land `#3` | Forbidden. Wait for ACCEPT + Woodpecker PR context. |

## Ordered implementation slices

1. **Delete catch-all file** — remove root `CODEOWNERS`. Confirm
   `docs/CODEOWNERS` and `.forgejo/CODEOWNERS` do not exist. No Solidity.
   (Already on `#3` as `0f5c87a`; rebase/amend only per implement rules,
   prefer additive commits on that head.)
2. **Preserve design + gitignore** — keep this ADR, `docs/architecture.md`,
   and the `.gitignore` carve-out on the occupying head.
3. **CI assertion** — Woodpecker (alpine, existing image class) fails if
   any of the three lookup paths exist as files. Do not drop the nonempty-tree
   step; do not add fake status POSTs.

Slice 1 before 3. Slice 2 is the design commit (this branch); implement
cherry-picks or merges it onto `#3`. No CAC or forge-script slice.

## Tests

| Requirement | Check |
| --- | --- |
| No CODEOWNERS at Forgejo lookup paths | Woodpecker / `scripts/check-no-catchall-codeowners.sh`: `test ! -f` for `CODEOWNERS`, `docs/CODEOWNERS`, `.forgejo/CODEOWNERS` |
| Catch-all rule gone | Satisfied by file absence; do not grep this ADR for the historical `.* @code/maintainers` string |
| Tree still nonempty | Existing `.woodpecker.yml` `tree` step |
| Merge docs do not recommend `force_merge` | `rg -n force_merge docs/ README.md` must not advise `force_merge: true` |
| Contracts unchanged | No `src/` / `script/` / `test/*.t.sol` edits on this ticket |
| Not live Forgejo PATCH | No protection API client in this repo |

`forge test` is not the merge-plane oracle. Do not add a Solidity test
that reads `.gitignore`.

## Rollout

1. Design review of this published revision (independent job). Author
   cannot approve.
2. Implement on occupying `#3` (slices 1–3). Controller autoland after
   tip ACCEPT + Woodpecker `ci/woodpecker/pr/woodpecker`. No `force_merge`.
3. Operator glance (not a merge gate): a subsequent PR in this repo has
   no official CODEOWNERS request. Protection GET unchanged.

Chat/issue cannot set protection flags.

## Rollback

Restore a CODEOWNERS file **only via PR** (never direct `main`). That
re-plants official review; do it only if a later ADR wants path owners.
Revert the Woodpecker assertion in the same PR so CI matches the file.
Do not PATCH protection to `block_on_official_review_requests=true` as
rollback of this ticket.

## Integration completion criteria

- Root / `docs/` / `.forgejo/` CODEOWNERS files absent on `main`.
- `.woodpecker.yml` fails closed if those paths return.
- [`architecture.md`](../architecture.md) merge table matches the gates
  above; this ADR remains the decision record.
- No `force_merge` in product docs; no protection PATCH; no CAC source
  edits; no contract/deploy edits.
- Occupying work is still a single PR (`#3`); no sibling head.

Live Grafana/CAC leftover cleanup is not a completion criterion here.

## Requirement-to-test mapping

See **Tests**. Implement keeps the mapping next to the Woodpecker step.

## Cross-links

- [#3](https://git.cl8y.com/code/CL8Y-Token-SC/issues/3)
- [cl8y-forgejo#48](https://git.cl8y.com/PlasticDigits/cl8y-forgejo/issues/48)
- [cl8y-agent-control#388](https://git.cl8y.com/PlasticDigits/cl8y-agent-control/issues/388)
- [cl8y-agent-control#297](https://git.cl8y.com/PlasticDigits/cl8y-agent-control/issues/297)
- [`architecture.md`](../architecture.md)
