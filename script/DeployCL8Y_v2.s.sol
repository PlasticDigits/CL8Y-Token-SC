// SPDX-License-Identifier: GPL-3.0
// Authored by Plastic Digits
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {IGuardERC20} from "../src/interfaces/IGuardERC20.sol";
import {GuardERC20} from "../src/GuardERC20.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {DatastoreSetAddress} from "../src/DatastoreSetAddress.sol";
import {CL8Y_v2} from "../src/CL8Y_v2.sol";

contract DeployCL8Y_v2 is Script {
    AccessManager public accessManager;
    DatastoreSetAddress public datastoreAddress;
    GuardERC20 public guardERC20;
    CL8Y_v2 public cl8y;

    function run() public {
        vm.startBroadcast();
        accessManager = new AccessManager(0x745A676C5c472b50B50e18D4b59e9AeEEc597046);
        datastoreAddress = new DatastoreSetAddress();
        guardERC20 = new GuardERC20(address(accessManager), datastoreAddress);
        new CL8Y_v2{salt: keccak256("CL8Y_v2.1")}(IGuardERC20(guardERC20), 0xFAC4C56258941D445Afda6BB2Fa87b493A65B8a1);
        vm.stopBroadcast();
    }
}
