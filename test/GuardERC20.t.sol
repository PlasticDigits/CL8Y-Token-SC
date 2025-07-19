// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {GuardERC20} from "../src/GuardERC20.sol";
import {IGuardERC20} from "../src/interfaces/IGuardERC20.sol";
import {DatastoreSetAddress, DatastoreSetIdAddress} from "../src/DatastoreSetAddress.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

// Mock guard module that always passes
contract MockGuardAlwaysPass is IGuardERC20 {
    bool public called = false;
    address public lastSender;
    address public lastRecipient;
    uint256 public lastAmount;

    function check(address sender, address recipient, uint256 amount) external {
        called = true;
        lastSender = sender;
        lastRecipient = recipient;
        lastAmount = amount;
    }

    function reset() external {
        called = false;
        lastSender = address(0);
        lastRecipient = address(0);
        lastAmount = 0;
    }
}

// Mock guard module that always reverts
contract MockGuardAlwaysRevert is IGuardERC20 {
    error GuardFailed(string reason);

    function check(address, address, uint256) external pure {
        revert GuardFailed("Mock guard always reverts");
    }
}

// Simple mock contract for testing execute function
contract MockExecuteTarget {
    uint256 public value;
    address public caller;
    bool public wasCalled;

    function setValue(uint256 _value) external payable {
        value = _value;
        caller = msg.sender;
        wasCalled = true;
    }

    function reset() external {
        value = 0;
        caller = address(0);
        wasCalled = false;
    }

    function failingFunction() external pure {
        revert("This function always fails");
    }
}

// Mock guard module that reverts for specific addresses
contract MockGuardConditional is IGuardERC20 {
    address public immutable blockedSender;
    address public immutable blockedRecipient;

    error BlockedSender(address sender);
    error BlockedRecipient(address recipient);

    constructor(address _blockedSender, address _blockedRecipient) {
        blockedSender = _blockedSender;
        blockedRecipient = _blockedRecipient;
    }

    function check(address sender, address recipient, uint256) external view {
        if (sender == blockedSender) {
            revert BlockedSender(sender);
        }
        if (recipient == blockedRecipient) {
            revert BlockedRecipient(recipient);
        }
    }
}

contract GuardERC20Test is Test {
    GuardERC20 guardERC20;
    DatastoreSetAddress datastoreSetAddress;
    AccessManager accessManager;

    MockGuardAlwaysPass mockGuardPass;
    MockGuardAlwaysRevert mockGuardRevert;
    MockGuardConditional mockGuardConditional;
    MockExecuteTarget mockExecuteTarget;

    address owner = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address unauthorizedUser = address(0x4);
    address blockedSender = address(0x5);
    address blockedRecipient = address(0x6);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy dependencies
        accessManager = new AccessManager(owner);
        datastoreSetAddress = new DatastoreSetAddress();

        // Deploy GuardERC20
        guardERC20 = new GuardERC20(
            address(accessManager),
            datastoreSetAddress
        );

        // Deploy mock guards
        mockGuardPass = new MockGuardAlwaysPass();
        mockGuardRevert = new MockGuardAlwaysRevert();
        mockGuardConditional = new MockGuardConditional(
            blockedSender,
            blockedRecipient
        );
        mockExecuteTarget = new MockExecuteTarget();

        // Configure function roles for restricted functions
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = GuardERC20.addGuardModule.selector;
        selectors[1] = GuardERC20.removeGuardModule.selector;
        selectors[2] = GuardERC20.execute.selector;

        accessManager.setTargetFunctionRole(
            address(guardERC20),
            selectors,
            accessManager.ADMIN_ROLE()
        );

        // Grant admin role to owner
        accessManager.grantRole(accessManager.ADMIN_ROLE(), owner, 0);

        vm.stopPrank();
    }

    function testInitialState() public view {
        // Test that initially no guard modules are configured
        uint256 length = datastoreSetAddress.length(
            address(guardERC20),
            guardERC20.GUARD_MODULES()
        );
        assertEq(length, 0);

        // Test that datastore address is set correctly
        assertEq(
            address(guardERC20.datastoreAddress()),
            address(datastoreSetAddress)
        );
    }

    function testAddGuardModule() public {
        vm.prank(owner);
        guardERC20.addGuardModule(address(mockGuardPass));

        uint256 length = datastoreSetAddress.length(
            address(guardERC20),
            guardERC20.GUARD_MODULES()
        );
        assertEq(length, 1);

        address guardModule = datastoreSetAddress.at(
            address(guardERC20),
            guardERC20.GUARD_MODULES(),
            0
        );
        assertEq(guardModule, address(mockGuardPass));

        console.log("Successfully added guard module:", address(mockGuardPass));
    }

    function testAddMultipleGuardModules() public {
        vm.startPrank(owner);

        guardERC20.addGuardModule(address(mockGuardPass));
        guardERC20.addGuardModule(address(mockGuardConditional));

        vm.stopPrank();

        uint256 length = datastoreSetAddress.length(
            address(guardERC20),
            guardERC20.GUARD_MODULES()
        );
        assertEq(length, 2);

        address[] memory allModules = datastoreSetAddress.getAll(
            address(guardERC20),
            guardERC20.GUARD_MODULES()
        );
        assertEq(allModules[0], address(mockGuardPass));
        assertEq(allModules[1], address(mockGuardConditional));

        console.log("Successfully added multiple guard modules");
    }

    function testRemoveGuardModule() public {
        // First add a guard module
        vm.startPrank(owner);
        guardERC20.addGuardModule(address(mockGuardPass));
        guardERC20.addGuardModule(address(mockGuardConditional));

        uint256 lengthBefore = datastoreSetAddress.length(
            address(guardERC20),
            guardERC20.GUARD_MODULES()
        );
        assertEq(lengthBefore, 2);

        // Remove one guard module
        guardERC20.removeGuardModule(address(mockGuardPass));

        vm.stopPrank();

        uint256 lengthAfter = datastoreSetAddress.length(
            address(guardERC20),
            guardERC20.GUARD_MODULES()
        );
        assertEq(lengthAfter, 1);

        address remaining = datastoreSetAddress.at(
            address(guardERC20),
            guardERC20.GUARD_MODULES(),
            0
        );
        assertEq(remaining, address(mockGuardConditional));

        console.log("Successfully removed guard module");
    }

    function testCheckWithNoGuardModules() public {
        // Should not revert when no guard modules are configured
        guardERC20.check(user1, user2, 1000);

        console.log("Check passed with no guard modules");
    }

    function testCheckWithSingleGuardModule() public {
        // Add guard module
        vm.prank(owner);
        guardERC20.addGuardModule(address(mockGuardPass));

        // Reset mock state
        mockGuardPass.reset();

        // Call check
        guardERC20.check(user1, user2, 1000);

        // Verify the guard was called with correct parameters
        assertTrue(mockGuardPass.called());
        assertEq(mockGuardPass.lastSender(), user1);
        assertEq(mockGuardPass.lastRecipient(), user2);
        assertEq(mockGuardPass.lastAmount(), 1000);

        console.log("Check successfully called single guard module");
    }

    function testCheckWithMultipleGuardModules() public {
        // Add multiple guard modules
        vm.startPrank(owner);
        guardERC20.addGuardModule(address(mockGuardPass));
        guardERC20.addGuardModule(address(mockGuardConditional));
        vm.stopPrank();

        // Reset mock state
        mockGuardPass.reset();

        // Should not revert when both guards pass
        guardERC20.check(user1, user2, 1000);

        // Verify the first guard was called
        assertTrue(mockGuardPass.called());
        assertEq(mockGuardPass.lastSender(), user1);
        assertEq(mockGuardPass.lastRecipient(), user2);
        assertEq(mockGuardPass.lastAmount(), 1000);

        console.log("Check successfully called multiple guard modules");
    }

    function testCheckWithRevertingGuardModule() public {
        // Add guard module that always reverts
        vm.prank(owner);
        guardERC20.addGuardModule(address(mockGuardRevert));

        // Should revert when guard module reverts
        vm.expectRevert(
            abi.encodeWithSelector(
                MockGuardAlwaysRevert.GuardFailed.selector,
                "Mock guard always reverts"
            )
        );
        guardERC20.check(user1, user2, 1000);

        console.log("Check correctly reverted when guard module failed");
    }

    function testCheckWithConditionalGuardModule() public {
        // Add conditional guard module
        vm.prank(owner);
        guardERC20.addGuardModule(address(mockGuardConditional));

        // Should pass for allowed addresses
        guardERC20.check(user1, user2, 1000);

        // Should revert for blocked sender
        vm.expectRevert(
            abi.encodeWithSelector(
                MockGuardConditional.BlockedSender.selector,
                blockedSender
            )
        );
        guardERC20.check(blockedSender, user2, 1000);

        // Should revert for blocked recipient
        vm.expectRevert(
            abi.encodeWithSelector(
                MockGuardConditional.BlockedRecipient.selector,
                blockedRecipient
            )
        );
        guardERC20.check(user1, blockedRecipient, 1000);

        console.log("Conditional guard module working correctly");
    }

    function testCheckStopsOnFirstFailure() public {
        // Add revert guard first, then pass guard
        vm.startPrank(owner);
        guardERC20.addGuardModule(address(mockGuardRevert));
        guardERC20.addGuardModule(address(mockGuardPass));
        vm.stopPrank();

        mockGuardPass.reset();

        // Should revert on first guard, second guard should not be called
        vm.expectRevert();
        guardERC20.check(user1, user2, 1000);

        // Verify second guard was NOT called due to early revert
        assertFalse(mockGuardPass.called());

        console.log("Check correctly stops on first failure");
    }

    function testAccessControlOnAddGuardModule() public {
        // Should revert when called by unauthorized user
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        guardERC20.addGuardModule(address(mockGuardPass));

        console.log("Access control working for addGuardModule");
    }

    function testAccessControlOnRemoveGuardModule() public {
        // Should revert when called by unauthorized user
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        guardERC20.removeGuardModule(address(mockGuardPass));

        console.log("Access control working for removeGuardModule");
    }

    function testAccessControlOnExecute() public {
        bytes memory data = abi.encodeWithSelector(
            MockExecuteTarget.setValue.selector,
            12345
        );

        // Should revert when called by unauthorized user
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        guardERC20.execute(address(mockExecuteTarget), data);

        console.log("Access control working for execute");
    }

    function testExecuteFunction() public {
        // Test execute by calling setValue on the mock target contract
        uint256 testValue = 12345;
        bytes memory data = abi.encodeWithSelector(
            MockExecuteTarget.setValue.selector,
            testValue
        );

        vm.prank(owner);
        guardERC20.execute(address(mockExecuteTarget), data);

        // Verify the external contract was called correctly
        assertEq(mockExecuteTarget.value(), testValue);
        assertEq(mockExecuteTarget.caller(), address(guardERC20));
        assertTrue(mockExecuteTarget.wasCalled());

        console.log("Execute function working correctly");
    }

    function testExecuteWithFailingCall() public {
        // Call a function that always reverts
        bytes memory data = abi.encodeWithSelector(
            MockExecuteTarget.failingFunction.selector
        );

        vm.prank(owner);
        // Should revert with "GuardERC20: call failed"
        vm.expectRevert("GuardERC20: call failed");
        guardERC20.execute(address(mockExecuteTarget), data);

        console.log("Execute correctly handles failing call");
    }

    function testExecuteWithEther() public {
        // Test execute function with Ether transfer
        uint256 testValue = 12345;
        uint256 etherAmount = 1 ether;

        bytes memory data = abi.encodeWithSelector(
            MockExecuteTarget.setValue.selector,
            testValue
        );

        // Give the owner some ether to send
        vm.deal(owner, etherAmount);

        // Check initial balance of target contract
        uint256 initialBalance = address(mockExecuteTarget).balance;

        vm.prank(owner);
        // Call execute with ether - the ether comes from the caller and gets forwarded
        guardERC20.execute{value: etherAmount}(
            address(mockExecuteTarget),
            data
        );

        // Verify the external contract received the ether and was called correctly
        assertEq(
            address(mockExecuteTarget).balance,
            initialBalance + etherAmount
        );
        assertEq(mockExecuteTarget.value(), testValue);
        assertEq(mockExecuteTarget.caller(), address(guardERC20));
        assertTrue(mockExecuteTarget.wasCalled());

        console.log("Execute function working correctly with Ether");
    }

    function testAddSameGuardModuleTwice() public {
        vm.startPrank(owner);

        guardERC20.addGuardModule(address(mockGuardPass));

        // Adding the same module again should not increase length
        guardERC20.addGuardModule(address(mockGuardPass));

        vm.stopPrank();

        uint256 length = datastoreSetAddress.length(
            address(guardERC20),
            guardERC20.GUARD_MODULES()
        );
        assertEq(length, 1);

        console.log("Duplicate guard module handling works correctly");
    }

    function testRemoveNonExistentGuardModule() public {
        // Should not revert when removing non-existent guard module
        vm.prank(owner);
        guardERC20.removeGuardModule(address(mockGuardPass));

        uint256 length = datastoreSetAddress.length(
            address(guardERC20),
            guardERC20.GUARD_MODULES()
        );
        assertEq(length, 0);

        console.log("Non-existent guard module removal handled correctly");
    }
}
