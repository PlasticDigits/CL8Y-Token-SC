// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {BlacklistSenderOnly} from "../src/BlacklistSenderOnly.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

contract BlacklistSenderOnlyTest is Test {
    BlacklistSenderOnly blacklist;
    AccessManager accessManager;

    address owner = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address user3 = address(0x4);
    address unauthorizedUser = address(0x5);

    function setUp() public {
        vm.startPrank(owner);

        accessManager = new AccessManager(owner);
        blacklist = new BlacklistSenderOnly(address(accessManager));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = blacklist.setIsBlacklistedToTrue.selector;
        selectors[1] = blacklist.setIsBlacklistedToFalse.selector;
        selectors[2] = blacklist.revertIfBlacklisted.selector;

        accessManager.setTargetFunctionRole(
            address(blacklist),
            selectors,
            accessManager.ADMIN_ROLE()
        );

        vm.stopPrank();
    }

    function testInitialState() public view {
        assertFalse(blacklist.isBlacklisted(user1));
        assertFalse(blacklist.isBlacklisted(user2));
        assertFalse(blacklist.isBlacklisted(user3));
    }

    function testSetIsBlacklistedToTrue() public {
        address[] memory accounts = new address[](2);
        accounts[0] = user1;
        accounts[1] = user2;

        vm.prank(owner);
        blacklist.setIsBlacklistedToTrue(accounts);

        assertTrue(blacklist.isBlacklisted(user1));
        assertTrue(blacklist.isBlacklisted(user2));
        assertFalse(blacklist.isBlacklisted(user3));
    }

    function testSetIsBlacklistedToFalse() public {
        address[] memory accounts = new address[](2);
        accounts[0] = user1;
        accounts[1] = user2;

        vm.prank(owner);
        blacklist.setIsBlacklistedToTrue(accounts);

        vm.prank(owner);
        blacklist.setIsBlacklistedToFalse(accounts);

        assertFalse(blacklist.isBlacklisted(user1));
        assertFalse(blacklist.isBlacklisted(user2));
    }

    function testCheckDoesNotRevertForUnrestrictedSender() public view {
        blacklist.check(user1, user2, 1 ether);
    }

    function testCheckRevertsForBlacklistedSender() public {
        address[] memory accounts = new address[](1);
        accounts[0] = user1;

        vm.prank(owner);
        blacklist.setIsBlacklistedToTrue(accounts);

        vm.expectRevert(
            abi.encodeWithSelector(
                BlacklistSenderOnly.Blacklisted.selector,
                user1
            )
        );
        blacklist.check(user1, user2, 1 ether);
    }

    function testCheckIgnoresRecipientBlacklist() public {
        address[] memory accounts = new address[](1);
        accounts[0] = user2;

        vm.prank(owner);
        blacklist.setIsBlacklistedToTrue(accounts);

        blacklist.check(user1, user2, 1 ether);
    }

    function testRevertIfBlacklisted() public {
        address[] memory accounts = new address[](1);
        accounts[0] = user1;

        vm.prank(owner);
        blacklist.setIsBlacklistedToTrue(accounts);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BlacklistSenderOnly.Blacklisted.selector,
                user1
            )
        );
        blacklist.revertIfBlacklisted(user1);

        vm.prank(owner);
        blacklist.revertIfBlacklisted(user2);
    }

    function testAccessControlOnSetIsBlacklistedToTrue() public {
        address[] memory accounts = new address[](1);
        accounts[0] = user1;

        vm.prank(unauthorizedUser);
        vm.expectRevert();
        blacklist.setIsBlacklistedToTrue(accounts);
    }

    function testAccessControlOnSetIsBlacklistedToFalse() public {
        address[] memory accounts = new address[](1);
        accounts[0] = user1;

        vm.prank(unauthorizedUser);
        vm.expectRevert();
        blacklist.setIsBlacklistedToFalse(accounts);
    }

    function testAccessControlOnRevertIfBlacklisted() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        blacklist.revertIfBlacklisted(user1);
    }
}
