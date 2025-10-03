// SPDX-License-Identifier: GPL-3.0
// Authored by Plastic Digits
pragma solidity >=0.8.23;

import {Script} from "forge-std/Script.sol";
import {BlacklistReceiverOnly} from "../src/BlacklistReceiverOnly.sol";

contract DeployBlacklistReceiverOnly is Script {
    function run() public {
        vm.startBroadcast();
        new BlacklistReceiverOnly(
            address(0x5823a01A5372B779cB091e47DBBb176F2831b4c7)
        );
        vm.stopBroadcast();
    }
}
