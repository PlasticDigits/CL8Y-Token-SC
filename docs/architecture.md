# Architecture overview

On-chain product (ERC20 + GuardERC20 modules, addresses, tokenomics) stays in
[`README.md`](../README.md). This file is the repo map for **merge and review**.
Do not copy token narrative here.

## Merge plane

Protected `main` is the only release branch. The merge contract is:

| Gate | Contract |
| --- | --- |
| Direct push | Off (`enable_push: false`) |
| Status check | `ci/woodpecker/pr/woodpecker` required |
| Official CODEOWNERS review | Not a merge gate; no catch-all `CODEOWNERS` file |
| `force_merge` | Forbidden |
| Approvals | `required_approvals: 0`; rejected reviews still block |

Catch-all CODEOWNERS removal: [ADR 0001](adr/0001-remove-catchall-codeowners.md)
([#3](https://git.cl8y.com/code/CL8Y-Token-SC/issues/3)). Forge policy that
keeps push/status protection and drops official-review block is
[cl8y-forgejo#48](https://git.cl8y.com/PlasticDigits/cl8y-forgejo/issues/48).
This product tree does not PATCH Forgejo protection and does not edit CAC.

Branch protection is operator-owned. Product PRs must not reintroduce
`CODEOWNERS`, `docs/CODEOWNERS`, or `.forgejo/CODEOWNERS` (Forgejo lookup
paths; Go-regexp, not GitHub globs).

## On-chain (pointer only)

CL8Y v2 is a minimal burnable ERC20 with optional GuardERC20 modules
(blacklist, rate limit, risk flag) under AccessManager. Deploy, key, and
custody changes are out of this merge-plane document
([agent-control #297](https://git.cl8y.com/PlasticDigits/cl8y-agent-control/issues/297)).
