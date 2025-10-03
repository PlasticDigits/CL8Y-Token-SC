// SPDX-License-Identifier: GPL-3.0
// Authored by Plastic Digits
pragma solidity >=0.8.23;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RateLimiting} from "../src/RateLimiting.sol";

contract DeployRateLimiting is Script {
    function run() public {
        address authority = address(0x5823a01A5372B779cB091e47DBBb176F2831b4c7);
        IERC20 token = IERC20(0x8F452a1fdd388A45e1080992eFF051b4dd9048d2);
        uint256 interval = 1 days;
        uint256 limit = 7_500 ether;

        vm.startBroadcast();
        new RateLimiting(authority, token, interval, limit);

        vm.stopBroadcast();
    }
}
