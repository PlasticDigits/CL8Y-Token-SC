// SPDX-License-Identifier: GPL-3.0
// Authored by Plastic Digits
pragma solidity >=0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {RiskFlagAuto} from "../src/RiskFlagAuto.sol";
import {DatastoreSetAddress} from "../src/DatastoreSetAddress.sol";

contract DeployRiskFlagAuto is Script {
    // BSC Mainnet addresses
    address constant ACCESS_MANAGER = 0x745120275A70693cc1D55cD5C81e99b0D2C1dF57;
    address constant DATASTORE_SET_ADDRESS = 0x8a18c91387149806BE5F7c1ebc6fE99e12d183dA;
    address constant GUARD_ERC20 = 0x417580DF7eE35FFA6286255b55B456c992657fB9;

    function run() public {
        vm.startBroadcast();

        // Deploy RiskFlagAuto with AccessManager as authority and DatastoreSetAddress
        RiskFlagAuto riskFlagAuto = new RiskFlagAuto(
            ACCESS_MANAGER,
            DatastoreSetAddress(DATASTORE_SET_ADDRESS)
        );

        console.log("RiskFlagAuto deployed at:", address(riskFlagAuto));
        console.log("");
        console.log("=== NEXT STEPS (execute manually) ===");
        console.log("");
        console.log("1. Add RiskFlagAuto as guard module (requires ADMIN role on AccessManager):");
        console.log("   Target: GuardERC20 at", GUARD_ERC20);
        console.log("   Function: addGuardModule(address)");
        console.log("   Arg: RiskFlagAuto at", address(riskFlagAuto));
        console.log("");
        console.log("2. Configure AccessManager roles for RiskFlagAuto admin functions:");
        console.log("   - setVolumeThreshold(uint256)");
        console.log("   - addHighRiskAccounts(address[])");
        console.log("   - removeHighRiskAccounts(address[])");
        console.log("   - addWhitelistedAccounts(address[])");
        console.log("   - removeWhitelistedAccounts(address[])");
        console.log("   - removeRiskFlaggedAccounts(address[])");
        console.log("   - setWindowFlagged(address,uint256,bool)");
        console.log("   - setWindowVolume(address,uint256,uint256)");
        console.log("");
        console.log("3. Add high-risk accounts (exchanges) to monitor");
        console.log("4. Add whitelisted accounts (known good actors) to exempt");

        vm.stopBroadcast();
    }
}
