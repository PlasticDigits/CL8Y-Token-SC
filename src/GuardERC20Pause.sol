// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {IGuardERC20} from "./interfaces/IGuardERC20.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @notice Pause every balance update routed through one immutable parent guard.
/// @dev The hook has no token context: this permission is guard-wide. Governance
/// must configure a separate immediate pause-only role, retaining resume and
/// module/authority administration. There is no transfer or recovery bypass.
contract GuardERC20Pause is IGuardERC20, AccessManaged, Pausable {
    address public immutable guard;

    error InvalidContract(address account);
    error UnauthorizedGuard(address caller);

    constructor(address initialAuthority, address parentGuard) AccessManaged(initialAuthority) {
        if (initialAuthority.code.length == 0) revert InvalidContract(initialAuthority);
        if (parentGuard.code.length == 0) revert InvalidContract(parentGuard);
        guard = parentGuard;
    }

    /// @notice Stop all updates through this guard; selector requires its own pause-only role.
    function pause() external restricted {
        _pause();
    }

    /// @notice Explicit governance recovery; never assign this selector to the emergency role.
    function unpause() external restricted {
        _unpause();
    }

    function check(address, address, uint256) external view {
        if (msg.sender != guard) revert UnauthorizedGuard(msg.sender);
        _requireNotPaused();
    }
}
