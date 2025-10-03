// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Blacklist} from "../src/BlacklistBasic.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

contract BlacklistBasicTest is Test {
    Blacklist blacklist;
    AccessManager accessManager;

    address owner = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address user3 = address(0x4);
    address unauthorizedUser = address(0x5);

    event AccountBlacklisted(address indexed account, bool status);

    function setUp() public {
        // Start pranking as owner for all setup operations
        vm.startPrank(owner);

        // Deploy AccessManager with owner
        accessManager = new AccessManager(owner);

        // Deploy Blacklist contract
        blacklist = new Blacklist(address(accessManager));

        // Configure function roles - set the restricted functions to be callable by ADMIN_ROLE
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = Blacklist.setIsBlacklistedToTrue.selector;
        selectors[1] = Blacklist.setIsBlacklistedToFalse.selector;
        selectors[2] = Blacklist.revertIfBlacklisted.selector;

        accessManager.setTargetFunctionRole(address(blacklist), selectors, accessManager.ADMIN_ROLE());

        vm.stopPrank();
    }

    function testInitialState() public view {
        // Test that initially no accounts are blacklisted
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

        console.log("Successfully blacklisted users:", user1, user2);
    }

    function testSetIsBlacklistedToFalse() public {
        // First blacklist some accounts
        address[] memory accounts = new address[](2);
        accounts[0] = user1;
        accounts[1] = user2;

        vm.prank(owner);
        blacklist.setIsBlacklistedToTrue(accounts);

        // Verify they are blacklisted
        assertTrue(blacklist.isBlacklisted(user1));
        assertTrue(blacklist.isBlacklisted(user2));

        // Now remove them from blacklist
        vm.prank(owner);
        blacklist.setIsBlacklistedToFalse(accounts);

        assertFalse(blacklist.isBlacklisted(user1));
        assertFalse(blacklist.isBlacklisted(user2));

        console.log("Successfully removed users from blacklist:", user1, user2);
    }

    function testCheckFunctionWithNormalUsers() public view {
        // Should not revert when both sender and recipient are not blacklisted
        blacklist.check(user1, user2, 1000);

        console.log("Check passed for normal users");
    }

    function testCheckFunctionWithBlacklistedSender() public {
        // Blacklist sender
        address[] memory accounts = new address[](1);
        accounts[0] = user1;

        vm.prank(owner);
        blacklist.setIsBlacklistedToTrue(accounts);

        // Should revert when sender is blacklisted
        vm.expectRevert(abi.encodeWithSelector(Blacklist.Blacklisted.selector, user1));
        blacklist.check(user1, user2, 1000);

        console.log("Check correctly reverted for blacklisted sender");
    }

    function testCheckFunctionWithBlacklistedRecipient() public {
        // Blacklist recipient
        address[] memory accounts = new address[](1);
        accounts[0] = user2;

        vm.prank(owner);
        blacklist.setIsBlacklistedToTrue(accounts);

        // Should revert when recipient is blacklisted
        vm.expectRevert(abi.encodeWithSelector(Blacklist.Blacklisted.selector, user2));
        blacklist.check(user1, user2, 1000);

        console.log("Check correctly reverted for blacklisted recipient");
    }

    function testCheckFunctionWithBothBlacklisted() public {
        // Blacklist both sender and recipient
        address[] memory accounts = new address[](2);
        accounts[0] = user1;
        accounts[1] = user2;

        vm.prank(owner);
        blacklist.setIsBlacklistedToTrue(accounts);

        // Should revert when recipient is checked first (order in check function)
        vm.expectRevert(abi.encodeWithSelector(Blacklist.Blacklisted.selector, user2));
        blacklist.check(user1, user2, 1000);

        console.log("Check correctly reverted when both users are blacklisted");
    }

    function testRevertIfBlacklisted() public {
        // Blacklist user1
        address[] memory accounts = new address[](1);
        accounts[0] = user1;

        vm.prank(owner);
        blacklist.setIsBlacklistedToTrue(accounts);

        // Should revert when checking blacklisted account
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Blacklist.Blacklisted.selector, user1));
        blacklist.revertIfBlacklisted(user1);

        // Should not revert when checking non-blacklisted account
        vm.prank(owner);
        blacklist.revertIfBlacklisted(user2);

        console.log("revertIfBlacklisted works correctly");
    }

    function testAccessControlOnSetIsBlacklistedToTrue() public {
        address[] memory accounts = new address[](1);
        accounts[0] = user1;

        // Should revert when called by unauthorized user
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        blacklist.setIsBlacklistedToTrue(accounts);

        console.log("Access control working for setIsBlacklistedToTrue");
    }

    function testAccessControlOnSetIsBlacklistedToFalse() public {
        address[] memory accounts = new address[](1);
        accounts[0] = user1;

        // Should revert when called by unauthorized user
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        blacklist.setIsBlacklistedToFalse(accounts);

        console.log("Access control working for setIsBlacklistedToFalse");
    }

    function testAccessControlOnRevertIfBlacklisted() public {
        // Should revert when called by unauthorized user
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        blacklist.revertIfBlacklisted(user1);

        console.log("Access control working for revertIfBlacklisted");
    }

    function testBlacklistMultipleAccounts() public {
        address[] memory accounts = new address[](3);
        accounts[0] = user1;
        accounts[1] = user2;
        accounts[2] = user3;

        vm.prank(owner);
        blacklist.setIsBlacklistedToTrue(accounts);

        assertTrue(blacklist.isBlacklisted(user1));
        assertTrue(blacklist.isBlacklisted(user2));
        assertTrue(blacklist.isBlacklisted(user3));

        console.log("Successfully blacklisted multiple accounts");
    }

    function testPartialBlacklistRemoval() public {
        // Blacklist three accounts
        address[] memory allAccounts = new address[](3);
        allAccounts[0] = user1;
        allAccounts[1] = user2;
        allAccounts[2] = user3;

        vm.prank(owner);
        blacklist.setIsBlacklistedToTrue(allAccounts);

        // Remove only two from blacklist
        address[] memory partialAccounts = new address[](2);
        partialAccounts[0] = user1;
        partialAccounts[1] = user3;

        vm.prank(owner);
        blacklist.setIsBlacklistedToFalse(partialAccounts);

        assertFalse(blacklist.isBlacklisted(user1));
        assertTrue(blacklist.isBlacklisted(user2));
        assertFalse(blacklist.isBlacklisted(user3));

        console.log("Partial blacklist removal working correctly");
    }

    function testEmptyArrays() public {
        address[] memory emptyArray = new address[](0);

        // Should not revert with empty arrays
        vm.prank(owner);
        blacklist.setIsBlacklistedToTrue(emptyArray);

        vm.prank(owner);
        blacklist.setIsBlacklistedToFalse(emptyArray);

        console.log("Empty array handling works correctly");
    }
}
