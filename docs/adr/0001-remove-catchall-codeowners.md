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
   Outcome 1 is **no file** at those lookup paths, not “no catch-all rule
   inside a remaining CODEOWNERS file.”
2. **Merge gates unchanged.** Direct `main` stays closed. Required status
   context remains `ci/woodpecker/pr/woodpecker`. Merge stays `Do: merge`
   with `head_commit_id`. Never `force_merge`.
3. **No on-chain change.** Solidity, scripts, and deployed addresses are
   untouched.

Author-attested live protection (GET, 2026-09-21, design-author session):
`enable_push=false`, `enable_status_check=true` with
`ci/woodpecker/pr/woodpecker`, `required_approvals=0`,
`block_on_official_review_requests=false`, `block_on_rejected_reviews=true`.
Anonymous `GET /repos/code/CL8Y-Token-SC/branch_protections` returns 401
(`token is required`). Independent review cannot re-verify those flags
without a token. If live flags differ from this attestation, stop and
escalate to forge owners. Do not PATCH protection from this repo. This ADR
does **not** treat the GET as implement write permission.

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
(`chore/remove-catchall-codeowners` @ `0f5c87a`, delete-only,
`mergeable: true`). Issue `#3` **is** pull `#3` (`html_url` → `/pulls/3`).

Occupying leftover plant is live on `#3`: Reviews API team `maintainers`,
`official: true`, `REQUEST_REVIEW`, not dismissed. Drain comments on that
PR are ACCEPT / occupying-job, not `DrainSkip::OfficialReview`. Woodpecker
`ci/woodpecker/pr/woodpecker` is success on `0f5c87a`. Deleting the file
does not dismiss that leftover. “No new plant” is proven on a PR **opened
after** land, not on `#3`.

## Non-goals

- PATCH Forgejo branch protection, `apply_repo_policy.py`, or migrate
  templates (cl8y-forgejo#48).
- Edit CAC `autoland` / `merge_drain` / `autonomy.rs` / HMAC, dismiss
  reviewers (including the leftover on `#3`), or retire
  `DrainSkip::OfficialReview` (optional CAC follow-up).
- Add path-specific CODEOWNERS, required approvals, or a second human
  reviewer.
- Drop or fake `ci/woodpecker/pr/woodpecker`; add a required push context
  on PR tips; POST fake commit statuses.
- `force_merge`, direct push to `main`, or enabling `enable_push`.
- Solidity, deploy scripts, AccessManager, keys, Coolify, or spend.
- Sibling PR `issue/3` while `#3` is open.
- Open `cac-design-issue-3` as a PR, or merge that transport ref to `main`
  (it still carries root `CODEOWNERS` until implement lands `#3`).
- Founder card for this ordinary chrome change.
- Rewriting [`README.md`](../../README.md) token narrative.
- Add `scripts/` (this tree has Foundry `script/` `.s.sol` only).
- `apk add` / `rg` in Woodpecker for this assertion.

## Component / state / interface changes

| Surface | Change |
| --- | --- |
| `CODEOWNERS` (root) | Delete. Do not recreate under `docs/` or `.forgejo/`. |
| `.gitignore` | Stop ignoring all of `docs/` (Foundry default). Ignore `docs/*` with carve-outs `!docs/adr/`, `!docs/adr/**`, and `!docs/architecture.md` so this ADR and overview are versioned and `docs/CODEOWNERS` stays untracked. Foundry `forge doc` output remains ignored via `docs/*`. |
| `docs/architecture.md` | Merge-plane map (this change). |
| `.woodpecker.yml` | Keep the existing `tree` step unchanged. Add exactly the Alpine step in slice 3. No `scripts/`. No `apk add`. No POST statuses. |
| Branch protection JSON | No change from this repo. |
| On-chain / Foundry tests of contracts | No change. |

Forgejo CODEOWNERS lookup is root, `docs/`, or `.forgejo/` (Go-regexp, not
GitHub globs). Outcome 1 is **no file** at those three paths.

## Affected invariants

This repo had no local invariant file. After this ADR the merge-plane table
in [`architecture.md`](../architecture.md) is the local contract:

- No file at `CODEOWNERS`, `docs/CODEOWNERS`, or `.forgejo/CODEOWNERS` on `main`.
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
| Path-specific CODEOWNERS | Out of scope; still plants official review on matching paths; Outcome 1 forbids the file. |
| Wait for forge #48 only | Protection can already be off; the file still plants requests and re-infects if protection regresses. AC5 is the product delete. |
| Required approvals = 1 | Same self-approve deadlock with a one-person team. |
| Merge `cac-design-issue-3` to `main` | That ref still has root `CODEOWNERS`; it is not a valid Outcome 1 tip. |

## Complexity added / removed

**Removed:** official review plant on every change; self-approve 405/422
class for this repo's later PRs; operator dismiss-to-land ritual.

**Added:** two tracked docs files, a `.gitignore` carve-out, and one Alpine
`test ! -f` step in `.woodpecker.yml`. No `scripts/` helper, no new runtime,
no new merge API.

## Migration

Git only. No contract migration, no Coolify, no token move.

Land vehicle is existing pull `#3` (`chore/remove-catchall-codeowners`).
`cac-design-issue-3` / `7956d2b` and successor design SHAs on that branch
are design transport only: do not open it as a PR and do not merge it to
`main`. Implement cherry-picks the accepted design commit(s) onto `0f5c87a`
(additive; `7956d2b` then this revision, or equivalent). The cherry-pick
must not restore `CODEOWNERS`. After slices 1–3 the occupying tip has: file
absent, these docs, `.gitignore` carve-out, and the Alpine step in slice 3.

Open PRs opened while root `CODEOWNERS` existed may still show a leftover
official request. Implement does **not** dismiss them — including the live
leftover on `#3`. After this lands, new PRs must not receive a CODEOWNERS
plant from this tree.

Occupying pull **#3** already deletes the file. Implementation **reuses**
`chore/remove-catchall-codeowners` / `#3`. Do not open `issue/3`. Title/body
need no extra `Fixes #3` (the pull **is** iid 3).

## Observability

- Forgejo PR “Reviews”: no official CODEOWNERS request on PRs **opened after
  land**. `#3` itself is not that oracle (leftover plant remains).
- Protection GET (operator, authenticated): still `enable_push=false`,
  status context `ci/woodpecker/pr/woodpecker`,
  `block_on_official_review_requests=false`. Anonymous GET is 401. Not a CI
  job in this repo (no Forgejo admin token in Woodpecker). If flags differ
  from the author attestation above, escalate; do not PATCH from here.
- CAC drain skip comments mentioning official CODEOWNERS should stop for
  **new** occupying PRs on this path. Leftover on `#3` is not a drain-skip
  failure of this ticket. No `/health` or `/status` change.

## Failure modes

| Failure | Behavior |
| --- | --- |
| File deleted; leftover official request on `#3` or another old PR | Do not dismiss; do not `force_merge`. Land `#3` with tip ACCEPT + PR Woodpecker + SHA-pinned `Do: merge`. If CAC later skips `OfficialReview` on that leftover, operators use the same `Do: merge` path. |
| File deleted; protection later PATCHed back to official-review block | New PRs still have no plant. Old leftover requests could 405 until they expire or a human dismisses. Re-planting CODEOWNERS is a regression. |
| CODEOWNERS re-added on a later PR | Woodpecker `no-catchall-codeowners` fails; do not merge that tip. |
| `docs/` gitignore swallows this ADR | `.gitignore` carve-out; design files must be tracked. |
| Sibling PR `issue/3` | Occupancy violation. Update `#3` only. |
| Merge `cac-design-issue-3` to `main` | Leaves the plant; contradicts Outcome 1. Transport only. |
| Implement PATCHes protection or edits CAC | Out of authority / wrong repo. |
| `force_merge` to land `#3` | Forbidden. Wait for ACCEPT + Woodpecker PR context + SHA-pinned `Do: merge`. |
| Woodpecker `rg` / `scripts/check-no-catchall-codeowners.sh` | Wrong interface. Alpine `3.20` has `test`/`sh` only. Bare `rg force_merge docs/` matches this ADR. |

## Ordered implementation slices

1. **Delete catch-all file** — remove root `CODEOWNERS`. Confirm
   `docs/CODEOWNERS` and `.forgejo/CODEOWNERS` do not exist. No Solidity.
   (Already on `#3` as `0f5c87a`; rebase/amend only per implement rules,
   prefer additive commits on that head.)
2. **Preserve design + gitignore** — keep this ADR, `docs/architecture.md`,
   and the `.gitignore` carve-out on the occupying head via cherry-pick of
   accepted `cac-design-issue-3` commit(s) onto `0f5c87a`.
3. **CI assertion** — add this step to `.woodpecker.yml`; do not change the
   existing `tree` step; do not add `scripts/`; do not `apk add`; do not
   POST statuses:

```yaml
  - name: no-catchall-codeowners
    image: alpine:3.20
    commands:
      - test ! -f CODEOWNERS
      - test ! -f docs/CODEOWNERS
      - test ! -f .forgejo/CODEOWNERS
```

Slice 1 before 3. Slice 2 is the design transport (`cac-design-issue-3`);
implement cherry-picks it onto `#3`. No CAC or forge-script slice.

## Tests

Woodpecker (only):

| Requirement | Check |
| --- | --- |
| No CODEOWNERS at Forgejo lookup paths | Step `no-catchall-codeowners` as in slice 3 (`alpine:3.20`, `test ! -f` on the three paths). Keep existing `tree` step. |

Human / review (not Woodpecker; alpine has no `rg`; do not add `scripts/`):

| Requirement | Check |
| --- | --- |
| Catch-all rule gone | Satisfied by file absence; do not grep this ADR for the historical `.* @code/maintainers` string |
| Merge docs do not advise `force_merge: true` | Reviewers confirm product docs do not recommend enabling `force_merge`. If a docs grep is used at all, match `force_merge:\s*true` as **advice**, not any occurrence of `force_merge` (this ADR names the forbidden API). |
| Contracts unchanged | No `src/` / `script/` / `test/*.t.sol` edits on this ticket |
| Not live Forgejo PATCH | No protection API client in this repo |
| Leftover on `#3` is not the plant oracle | “No new plant” is a PR opened after land |

`forge test` is not the merge-plane oracle. Do not add a Solidity test
that reads `.gitignore`.

## Rollout

1. Design review of this published revision (independent job). Author
   cannot approve. `cac-design-issue-3` stays unpublished as a PR.
2. Implement on occupying `#3` (slices 1–3). Autoland / operator land is
   tip ACCEPT + Woodpecker `ci/woodpecker/pr/woodpecker` + SHA-pinned
   `Do: merge`. Do not dismiss the leftover official request on `#3`. If
   CAC later skips `OfficialReview` on that leftover, use the same
   `Do: merge` path. Never `force_merge`.
3. Operator glance (not a merge gate): a **subsequent** PR in this repo
   (opened after land) has no official CODEOWNERS request. Protection GET
   (authenticated) unchanged vs author attestation; if it differs, escalate
   to forge owners, do not PATCH from this repo.

Chat/issue cannot set protection flags.

## Rollback

Restore a CODEOWNERS file **only via PR** (never direct `main`). That
re-plants official review; do it only if a later ADR wants path owners.
Revert the Woodpecker assertion in the same PR so CI matches the file.
Do not PATCH protection to `block_on_official_review_requests=true` as
rollback of this ticket.

## Integration completion criteria

- Root / `docs/` / `.forgejo/` CODEOWNERS files absent on `main`.
- `.woodpecker.yml` contains the slice 3 Alpine step and fails closed if
  those paths return; existing `tree` step remains.
- [`architecture.md`](../architecture.md) merge table matches Outcome 1
  (no file at the three lookup paths); this ADR remains the decision record.
- No `force_merge: true` advice in product docs; no protection PATCH; no
  CAC source edits; no contract/deploy edits.
- Occupying work is still a single PR (`#3`); no sibling head; design
  transport was not merged to `main`.
- Leftover official request on `#3` may remain until merge; “no new plant”
  is a PR opened after land.

Live Grafana/CAC leftover cleanup is not a completion criterion here.

## Requirement-to-test mapping

See **Tests**. Implement keeps the mapping next to the Woodpecker step
(the YAML in slice 3 is the mapping).

## Cross-links

- [#3](https://git.cl8y.com/code/CL8Y-Token-SC/issues/3)
- [cl8y-forgejo#48](https://git.cl8y.com/PlasticDigits/cl8y-forgejo/issues/48)
- [cl8y-agent-control#388](https://git.cl8y.com/PlasticDigits/cl8y-agent-control/issues/388)
- [cl8y-agent-control#297](https://git.cl8y.com/PlasticDigits/cl8y-agent-control/issues/297)
- [`architecture.md`](../architecture.md)
