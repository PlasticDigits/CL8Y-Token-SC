// SPDX-License-Identifier: AGPL-3.0-only
// Authored by Plastic Digits
pragma solidity ^0.8.30;

import {IBlacklist} from "./interfaces/IBlacklist.sol";
import {IGuardERC20} from "./interfaces/IGuardERC20.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";

contract BlacklistSenderOnly is IBlacklist, IGuardERC20, AccessManaged {
    mapping(address account => bool status) public override isBlacklisted;

    error Blacklisted(address account);

    constructor(address _initialAuthority) AccessManaged(_initialAuthority) {}

    function check(address sender, address, uint256) external view {
        if (isBlacklisted[sender]) revert Blacklisted(sender);
    }

    function setIsBlacklistedToTrue(
        address[] calldata _accounts
    ) external restricted {
        for (uint256 i = 0; i < _accounts.length; i++) {
            isBlacklisted[_accounts[i]] = true;
        }
    }

    function setIsBlacklistedToFalse(
        address[] calldata _accounts
    ) external restricted {
        for (uint256 i = 0; i < _accounts.length; i++) {
            isBlacklisted[_accounts[i]] = false;
        }
    }

    function revertIfBlacklisted(address _account) external restricted {
        if (isBlacklisted[_account]) revert Blacklisted(_account);
    }
}
