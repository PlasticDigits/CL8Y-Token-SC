// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {CL8Y_v2} from "../src/CL8Y_v2.sol";
import {GuardERC20} from "../src/GuardERC20.sol";
import {Blacklist} from "../src/BlacklistBasic.sol";
import {DatastoreSetAddress} from "../src/DatastoreSetAddress.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

contract CL8YIntegrationTest is Test {
    // Core contracts
    CL8Y_v2 token;
    GuardERC20 guardERC20;
    Blacklist blacklist;
    DatastoreSetAddress datastoreSetAddress;
    AccessManager accessManager;

    // Test addresses
    address owner = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    address charlie = address(0x4);
    address unauthorizedUser = address(0x5);

    // Events to test
    event Transfer(address indexed from, address indexed to, uint256 value);
    event AccountBlacklisted(address indexed account, bool status);

    function setUp() public {
        vm.startPrank(owner);

        // 1. Deploy AccessManager
        accessManager = new AccessManager(owner);

        // 2. Deploy DatastoreSetAddress
        datastoreSetAddress = new DatastoreSetAddress();

        // 3. Deploy Blacklist with AccessManager
        blacklist = new Blacklist(address(accessManager));

        // 4. Deploy GuardERC20 with AccessManager and DatastoreSetAddress
        guardERC20 = new GuardERC20(
            address(accessManager),
            datastoreSetAddress
        );

        // 5. Configure access controls for Blacklist
        bytes4[] memory blacklistSelectors = new bytes4[](3);
        blacklistSelectors[0] = Blacklist.setIsBlacklistedToTrue.selector;
        blacklistSelectors[1] = Blacklist.setIsBlacklistedToFalse.selector;
        blacklistSelectors[2] = Blacklist.revertIfBlacklisted.selector;

        accessManager.setTargetFunctionRole(
            address(blacklist),
            blacklistSelectors,
            accessManager.ADMIN_ROLE()
        );

        // 6. Configure access controls for GuardERC20
        bytes4[] memory guardSelectors = new bytes4[](3);
        guardSelectors[0] = GuardERC20.addGuardModule.selector;
        guardSelectors[1] = GuardERC20.removeGuardModule.selector;
        guardSelectors[2] = GuardERC20.execute.selector;

        accessManager.setTargetFunctionRole(
            address(guardERC20),
            guardSelectors,
            accessManager.ADMIN_ROLE()
        );

        // 7. Grant admin role to owner
        accessManager.grantRole(accessManager.ADMIN_ROLE(), owner, 0);

        // 8. Add blacklist as a guard module to GuardERC20
        guardERC20.addGuardModule(address(blacklist));

        // 9. Deploy CL8Y_v2 token with GuardERC20 as the guard
        token = new CL8Y_v2(guardERC20);

        vm.stopPrank();
    }

    function testInitialState() public view {
        // Test initial token state
        assertEq(token.name(), "CeramicLiberty.com");
        assertEq(token.symbol(), "CL8Y");
        assertEq(token.totalSupply(), 3_000_000 ether);
        assertEq(token.balanceOf(owner), 3_000_000 ether);

        // Test that blacklist is properly added as guard module
        uint256 guardModulesLength = datastoreSetAddress.length(
            address(guardERC20),
            guardERC20.GUARD_MODULES()
        );
        assertEq(guardModulesLength, 1);

        address firstGuardModule = datastoreSetAddress.at(
            address(guardERC20),
            guardERC20.GUARD_MODULES(),
            0
        );
        assertEq(firstGuardModule, address(blacklist));

        // Test that no addresses are initially blacklisted
        assertFalse(blacklist.isBlacklisted(alice));
        assertFalse(blacklist.isBlacklisted(bob));
        assertFalse(blacklist.isBlacklisted(charlie));

        console.log("Initial state verified successfully");
    }

    function testNormalTransfer() public {
        uint256 transferAmount = 100 ether;

        // Transfer tokens from owner to alice
        vm.prank(owner);
        token.transfer(alice, transferAmount);

        // Verify balances
        assertEq(token.balanceOf(owner), 3_000_000 ether - transferAmount);
        assertEq(token.balanceOf(alice), transferAmount);

        // Test transfer between non-blacklisted users
        vm.prank(alice);
        token.transfer(bob, 50 ether);

        assertEq(token.balanceOf(alice), 50 ether);
        assertEq(token.balanceOf(bob), 50 ether);

        console.log("Normal transfers working correctly");
    }

    function testTransferWithBlacklistedSender() public {
        uint256 transferAmount = 100 ether;

        // First transfer some tokens to alice
        vm.prank(owner);
        token.transfer(alice, transferAmount);

        // Blacklist alice
        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        vm.prank(owner);
        blacklist.setIsBlacklistedToTrue(accounts);

        // Verify alice is blacklisted
        assertTrue(blacklist.isBlacklisted(alice));

        // Attempt transfer from blacklisted alice should fail
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Blacklist.Blacklisted.selector, alice)
        );
        token.transfer(bob, 50 ether);

        console.log("Blacklisted sender correctly blocked");
    }

    function testTransferWithBlacklistedRecipient() public {
        uint256 transferAmount = 100 ether;

        // Blacklist bob (recipient)
        address[] memory accounts = new address[](1);
        accounts[0] = bob;

        vm.prank(owner);
        blacklist.setIsBlacklistedToTrue(accounts);

        // Verify bob is blacklisted
        assertTrue(blacklist.isBlacklisted(bob));

        // Attempt transfer to blacklisted bob should fail
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(Blacklist.Blacklisted.selector, bob)
        );
        token.transfer(bob, transferAmount);

        console.log("Blacklisted recipient correctly blocked");
    }

    function testBlacklistManagement() public {
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        // Blacklist multiple accounts
        vm.prank(owner);
        blacklist.setIsBlacklistedToTrue(accounts);

        assertTrue(blacklist.isBlacklisted(alice));
        assertTrue(blacklist.isBlacklisted(bob));
        assertFalse(blacklist.isBlacklisted(charlie));

        // Remove alice from blacklist
        address[] memory removeAccount = new address[](1);
        removeAccount[0] = alice;

        vm.prank(owner);
        blacklist.setIsBlacklistedToFalse(removeAccount);

        assertFalse(blacklist.isBlacklisted(alice));
        assertTrue(blacklist.isBlacklisted(bob));

        console.log("Blacklist management working correctly");
    }

    function testBurnFunction() public {
        uint256 burnAmount = 1000 ether;
        uint256 initialSupply = token.totalSupply();

        // Transfer some tokens to alice first
        vm.prank(owner);
        token.transfer(alice, burnAmount);

        // Alice burns tokens
        vm.prank(alice);
        token.burn(burnAmount);

        // Verify burn worked
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), initialSupply - burnAmount);

        console.log("Token burning working correctly");
    }

    function testBurnByBlacklistedUser() public {
        uint256 burnAmount = 1000 ether;

        // Transfer tokens to alice
        vm.prank(owner);
        token.transfer(alice, burnAmount);

        // Blacklist alice
        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        vm.prank(owner);
        blacklist.setIsBlacklistedToTrue(accounts);

        // Alice (blacklisted) tries to burn tokens - should fail because burn calls _update
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Blacklist.Blacklisted.selector, alice)
        );
        token.burn(burnAmount);

        console.log("Blacklisted user correctly blocked from burning");
    }

    function testMultipleGuardModules() public {
        vm.startPrank(owner);

        // Deploy a second blacklist for testing multiple guards
        Blacklist secondBlacklist = new Blacklist(address(accessManager));

        // Configure access controls for second blacklist
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = Blacklist.setIsBlacklistedToTrue.selector;
        selectors[1] = Blacklist.setIsBlacklistedToFalse.selector;
        selectors[2] = Blacklist.revertIfBlacklisted.selector;

        accessManager.setTargetFunctionRole(
            address(secondBlacklist),
            selectors,
            accessManager.ADMIN_ROLE()
        );

        // Add second blacklist as guard module
        guardERC20.addGuardModule(address(secondBlacklist));

        vm.stopPrank();

        // Verify we now have 2 guard modules
        uint256 guardModulesLength = datastoreSetAddress.length(
            address(guardERC20),
            guardERC20.GUARD_MODULES()
        );
        assertEq(guardModulesLength, 2);

        // Blacklist alice in first blacklist only
        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        vm.prank(owner);
        blacklist.setIsBlacklistedToTrue(accounts);

        // Transfer should still fail even though alice is only blacklisted in first guard
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(Blacklist.Blacklisted.selector, alice)
        );
        token.transfer(alice, 100 ether);

        console.log("Multiple guard modules working correctly");
    }

    function testAccessControlOnBlacklist() public {
        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        // Unauthorized user should not be able to modify blacklist
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        blacklist.setIsBlacklistedToTrue(accounts);

        vm.prank(unauthorizedUser);
        vm.expectRevert();
        blacklist.setIsBlacklistedToFalse(accounts);

        console.log("Access control on blacklist working correctly");
    }

    function testAccessControlOnGuardERC20() public {
        // Unauthorized user should not be able to add/remove guard modules
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        guardERC20.addGuardModule(address(0x123));

        vm.prank(unauthorizedUser);
        vm.expectRevert();
        guardERC20.removeGuardModule(address(blacklist));

        console.log("Access control on GuardERC20 working correctly");
    }

    function testComplexScenario() public {
        // 1. Transfer tokens to multiple users
        vm.startPrank(owner);
        token.transfer(alice, 1000 ether);
        token.transfer(bob, 1000 ether);
        token.transfer(charlie, 1000 ether);
        vm.stopPrank();

        // 2. Verify initial transfers worked
        assertEq(token.balanceOf(alice), 1000 ether);
        assertEq(token.balanceOf(bob), 1000 ether);
        assertEq(token.balanceOf(charlie), 1000 ether);

        // 3. Users trade with each other
        vm.prank(alice);
        token.transfer(bob, 100 ether);

        vm.prank(bob);
        token.transfer(charlie, 200 ether);

        // 4. Verify balances after trading
        assertEq(token.balanceOf(alice), 900 ether);
        assertEq(token.balanceOf(bob), 900 ether);
        assertEq(token.balanceOf(charlie), 1200 ether);

        // 5. Blacklist alice
        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        vm.prank(owner);
        blacklist.setIsBlacklistedToTrue(accounts);

        // 6. Alice can't send tokens anymore
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Blacklist.Blacklisted.selector, alice)
        );
        token.transfer(bob, 100 ether);

        // 7. Alice can't receive tokens anymore
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(Blacklist.Blacklisted.selector, alice)
        );
        token.transfer(alice, 100 ether);

        // 8. Bob and Charlie can still trade normally
        vm.prank(bob);
        token.transfer(charlie, 100 ether);

        assertEq(token.balanceOf(bob), 800 ether);
        assertEq(token.balanceOf(charlie), 1300 ether);

        // 9. Remove alice from blacklist
        vm.prank(owner);
        blacklist.setIsBlacklistedToFalse(accounts);

        // 10. Alice can trade again
        vm.prank(alice);
        token.transfer(bob, 100 ether);

        assertEq(token.balanceOf(alice), 800 ether);
        assertEq(token.balanceOf(bob), 900 ether);

        console.log("Complex integration scenario completed successfully");
    }

    function testEmptyBlacklistArrays() public {
        address[] memory emptyArray = new address[](0);

        // Should not revert with empty arrays
        vm.prank(owner);
        blacklist.setIsBlacklistedToTrue(emptyArray);

        vm.prank(owner);
        blacklist.setIsBlacklistedToFalse(emptyArray);

        console.log("Empty blacklist arrays handled correctly");
    }

    function testTokenMetadata() public view {
        assertEq(token.name(), "CeramicLiberty.com");
        assertEq(token.symbol(), "CL8Y");
        assertEq(token.decimals(), 18);
    }

    function testOwnerInitialBalance() public view {
        assertEq(token.balanceOf(owner), 3_000_000 ether);
    }
}
