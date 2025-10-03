// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {IGuardERC20} from "./interfaces/IGuardERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CL8Y_v2 is ERC20 {
    IGuardERC20 private immutable guard;

    constructor(IGuardERC20 _guard, address _initialHolder) ERC20("CeramicLiberty.com", "CL8Y") {
        guard = _guard;
        _mint(_initialHolder, 3_000_000 ether);
    }

    function burn(uint256 value) public {
        _burn(_msgSender(), value);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (msg.sender == address(guard)) {
            _approve(from, address(guard), value);
        }
        guard.check(from, to, value);
        super._update(from, to, value);
    }
}
