# Guard-wide emergency pause module

`GuardERC20Pause` is an optional new module for the existing `GuardERC20`
pipeline. It starts unpaused and pins one parent guard at construction. Its
balance-control operations are `pause()` and `unpause()`, both controlled
by the existing AccessManager selector permissions. Inherited authority
management remains with the current authority and governance. It has no token transfer,
arbitrary executor, recovery function, exemption list, mutable parent guard or
automatic resume behavior. Existing token and parent guard source are unchanged.

## Scope is the whole parent guard

`CL8Y_v2._update` calls its immutable guard. The parent calls modules with only
sender, recipient and amount, so a module sees the parent guard as caller and
receives no originating token identity. This module rejects direct/nonparent
callers, but it cannot selectively pause one token among several sharing the
same parent. A cosmetic token address would not enforce that distinction.

Admit a single-token target only after verifying that the exact deployed token
uses this exact dedicated guard and all tokens sharing that guard are known.
An unknown/shared guard cannot be enrolled as a single-token pause. Any wider
guard scope needs its own complete, explicitly authorized inventory; otherwise
use a separately reviewed new guard/token with voluntary migration. README
addresses alone do not prove deployed code, immutable bindings or module wiring.

## Selector permissions and recovery

Governance must configure an independently inventoried non-admin emergency
role for **only** `GuardERC20Pause.pause.selector`, with immediate execution.
Keep `unpause.selector` governance-only. Keep the parent's `addGuardModule`,
`removeGuardModule` and `execute`, authority changes, role administration and
role grants under governance, with no such power held by the emergency identity.
Check indirect role-admin/guardian authority too. Do not assume a numeric role
ID is unused from example documentation; role77 in tests is synthetic.

Until that configuration is made, AccessManager's default administrative
permissions apply; deploying this module does not enroll an emergency signer.
Rotation/revocation uses the manager and never changes the paused flag. Resume
is an explicit governance action. Governance module removal can bypass a paused
module by disconnecting it, so both membership and authority must be checked
when reporting containment. The module is non-upgradeable; governance retains
the existing authority-management and parent module-management paths.

Closing an AccessManager target is not a token pause. The parent's `check` and
ordinary token transfers are unrestricted. Closing the module likewise does
not change its flag or suppress its hook: unpaused transfers still pass, and
paused transfers still revert. Closure can block restricted pause/resume calls,
so it must not be substituted for a working emergency selector assignment.

## Balance updates, approvals and asset exits

| Path through the configured parent guard | Paused behavior |
| --- | --- |
| `transfer`, `transferFrom`, including zero-value updates | Revert before balance updates complete; transaction rollback preserves balances and allowance consumption. |
| `CL8Y_v2.burn`, including zero | Revert; holder burns are not an emergency exit. |
| Constructor initial `_mint` | Token construction reverts if the module is already installed and paused. This source has no public post-deployment mint entry point. |
| Existing `GuardERC20.execute`/`AssetRecovery` token updates | No bypass: updates reaching this hook revert too. Existing independent authorization/allowance requirements remain. |
| ERC20 approvals and views | Continue because they do not invoke `_update`; approvals cannot bypass a blocked balance update. |

Other modules retain their independent rules when resumed. A later pause revert
also rolls back earlier modules' state changes in the same transaction. No fees,
supply schedule, user refund, withdrawal, allowance wipe or seizure right is
introduced. Recovery releases/transfers through this token need explicit
governance resume or separately reviewed module removal; existing recovery and
blacklist requirements still apply. No automated asset movement is added.

## Immutable legacy and bridged tokens

Existing `CL8Y.sol` has no retrofit global pause, and already-open trading cannot
be closed. Existing `TokenCl8yBridged` public transfers and burns do not consult
AccessManager restrictions; restricted mint authority is a separate capability.
This module cannot attach freeze rights to either immutable deployment. Record
an honest no-pause capability or separately approve a new version and voluntary
migration. Pausing a bridge does not globally pause token transfers on any chain.

## Validation and live admission

Focused local tests cover selector separation, initial/transfer/allowance/burn
and test-only mint hooks, atomic rollback, role revocation, both target-closure
distinctions, other modules, recovery paths and the shared-guard boundary. The
test-only mint harness is not a production issuance method.

Before production enrollment, verify chain/finality, exact token/guard/module
runtime and immutable identity, authority and selector roles/delays, dedicated
guard scope, current datastore module membership, governance recovery custody,
bounded signing/gas policy and an independently reviewed canary. A finalized
`module.paused() == true` alone is insufficient if the module is detached or the
token uses another guard. Require the exact binding/membership and actual token
call/post-state evidence too. Source tests do not establish a deployed pause
capability. No deployment, signer enrollment or live token pause is performed by
these files.
