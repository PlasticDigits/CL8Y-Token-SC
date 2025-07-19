// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {IGuardERC20} from "./interfaces/IGuardERC20.sol";
import {DatastoreSetAddress, DatastoreSetIdAddress} from "./DatastoreSetAddress.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";

contract GuardERC20 is IGuardERC20, DatastoreSetAddress, AccessManaged {
    DatastoreSetAddress public immutable datastoreAddress;

    DatastoreSetIdAddress public constant GUARD_MODULES =
        DatastoreSetIdAddress.wrap(keccak256("GUARD_MODULES"));

    constructor(
        address _initialAuthority,
        DatastoreSetAddress _datastoreAddress
    ) AccessManaged(_initialAuthority) {
        datastoreAddress = _datastoreAddress;
    }

    // iterate over all guard modules and call the check function on each one
    function check(address sender, address recipient, uint256 amount) external {
        // Iterate over all guard modules
        uint256 length = datastoreAddress.length(address(this), GUARD_MODULES);
        for (uint256 i; i < length; i++) {
            address guardModule = datastoreAddress.at(
                address(this),
                GUARD_MODULES,
                i
            );
            IGuardERC20(guardModule).check(sender, recipient, amount);
        }
    }

    // add a guard module
    function addGuardModule(address guardModule) external restricted {
        datastoreAddress.add(GUARD_MODULES, guardModule);
    }

    // remove a guard module
    function removeGuardModule(address guardModule) external restricted {
        datastoreAddress.remove(GUARD_MODULES, guardModule);
    }

    // Execute an arbitrary function on an external contract
    function execute(
        address target,
        bytes calldata data
    ) external payable restricted returns (bytes memory) {
        (bool success, bytes memory result) = target.call{value: msg.value}(
            data
        );
        if (!success) {
            revert("GuardERC20: call failed");
        }
        return result;
    }
}
