// SPDX-License-Identifier: GPL-3.0
// Authored by Plastic Digits
pragma solidity >=0.8.23;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/CL8Y.sol";
import "../src/interfaces/IAmmFactory.sol";

contract DeployCL8Y is Script {
    function run() public {
        vm.startBroadcast();
        new CL8Y(
            IAmmFactory(0x907e8C7D471877b4742dA8aA53d257d0d565A47E), //factory: TidalDex
            IERC20(0xE68b79e51bf826534Ff37AA9CeE71a3842ee9c70), //base liquidity token: CZUSD
            1740870000 // trading open time: 23:00 UTC March 1, 2025
        );
        vm.stopBroadcast();
    }
}
