// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CL8Y_v2} from "../src/CL8Y_v2.sol";
import {GuardERC20} from "../src/GuardERC20.sol";
import {GuardERC20Pause} from "../src/GuardERC20Pause.sol";
import {DatastoreSetAddress} from "../src/DatastoreSetAddress.sol";
import {IGuardERC20} from "../src/interfaces/IGuardERC20.sol";
import {IGuardExecutor} from "../src/interfaces/IGuardExecutor.sol";
import {AssetRecovery} from "../src/AssetRecovery.sol";
import {IBlacklist} from "../src/interfaces/IBlacklist.sol";

contract PauseTestBlacklist is IBlacklist {
    mapping(address => bool) public isBlacklisted;

    function set(address account) external {
        isBlacklisted[account] = true;
    }

    function setIsBlacklistedToTrue(address[] calldata accounts) external {
        for (uint256 i; i < accounts.length; ++i) {
            isBlacklisted[accounts[i]] = true;
        }
    }

    function setIsBlacklistedToFalse(address[] calldata accounts) external {
        for (uint256 i; i < accounts.length; ++i) {
            isBlacklisted[accounts[i]] = false;
        }
    }
}

contract PauseTestOtherModule is IGuardERC20 {
    bool public reject;
    uint256 public calls;

    function setReject(bool value) external {
        reject = value;
    }

    function check(address, address, uint256) external {
        ++calls;
        require(!reject, "other module restriction");
    }
}

/// @dev Test-only issuance hook. Production CL8Y_v2 has no external mint method.
contract PauseTestMintHarness is CL8Y_v2 {
    constructor(IGuardERC20 parent, address holder) CL8Y_v2(parent, holder) {}

    function mintForTest(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract GuardERC20PauseTest is Test {
    uint64 internal constant PAUSE_ROLE = 77; // Synthetic fixture ID, not a live assignment.
    address internal constant GOVERNANCE = address(1);
    address internal constant PAUSER = address(2);
    address internal constant REPLACEMENT = address(3);
    address internal constant HOLDER = address(4);
    address internal constant RECIPIENT = address(5);
    address internal constant SPENDER = address(6);

    AccessManager internal manager;
    GuardERC20 internal parent;
    GuardERC20Pause internal module;
    CL8Y_v2 internal token;

    function setUp() public {
        manager = new AccessManager(GOVERNANCE);
        parent = new GuardERC20(address(manager), new DatastoreSetAddress());
        module = new GuardERC20Pause(address(manager), address(parent));

        vm.startPrank(GOVERNANCE);
        bytes4[] memory pauseSelectors = new bytes4[](1);
        pauseSelectors[0] = GuardERC20Pause.pause.selector;
        manager.setTargetFunctionRole(address(module), pauseSelectors, PAUSE_ROLE);
        bytes4[] memory resume = new bytes4[](1);
        resume[0] = GuardERC20Pause.unpause.selector;
        manager.setTargetFunctionRole(address(module), resume, manager.ADMIN_ROLE());
        bytes4[] memory management = new bytes4[](3);
        management[0] = GuardERC20.addGuardModule.selector;
        management[1] = GuardERC20.removeGuardModule.selector;
        management[2] = GuardERC20.execute.selector;
        manager.setTargetFunctionRole(address(parent), management, manager.ADMIN_ROLE());
        manager.grantRole(PAUSE_ROLE, PAUSER, 0);
        parent.addGuardModule(address(module));
        vm.stopPrank();
        token = new CL8Y_v2(IGuardERC20(parent), HOLDER);
    }

    function pause() internal {
        vm.prank(PAUSER);
        module.pause();
    }

    function test_PauseStartsUnpausedAndAllowsInitialMintTransferAllowanceAndBurn() public {
        assertFalse(module.paused());
        assertEq(module.guard(), address(parent));
        assertEq(token.totalSupply(), 3_000_000 ether);
        vm.startPrank(HOLDER);
        token.transfer(RECIPIENT, 20 ether);
        token.approve(SPENDER, 10 ether);
        token.burn(1 ether);
        vm.stopPrank();
        vm.prank(SPENDER);
        token.transferFrom(HOLDER, RECIPIENT, 10 ether);
        assertEq(token.balanceOf(RECIPIENT), 30 ether);
        assertEq(token.totalSupply(), 2_999_999 ether);
    }

    function test_PauseBlocksAllTransferAndBurnUpdatesAtomicallyButNotApprovalsOrViews() public {
        vm.prank(HOLDER);
        token.approve(SPENDER, 10 ether);
        pause();
        uint256 balance = token.balanceOf(HOLDER);
        uint256 supply = token.totalSupply();
        vm.startPrank(HOLDER);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.transfer(RECIPIENT, 1 ether);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.transfer(RECIPIENT, 0);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.burn(1 ether);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.burn(0);
        token.approve(RECIPIENT, 7 ether);
        vm.stopPrank();
        vm.startPrank(SPENDER);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.transferFrom(HOLDER, RECIPIENT, 1 ether);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.transferFrom(HOLDER, RECIPIENT, 0);
        vm.stopPrank();
        assertEq(token.allowance(HOLDER, SPENDER), 10 ether);
        assertEq(token.allowance(HOLDER, RECIPIENT), 7 ether);
        assertEq(token.balanceOf(HOLDER), balance);
        assertEq(token.balanceOf(RECIPIENT), 0);
        assertEq(token.totalSupply(), supply);
    }

    function test_PauseRejectsInitialMintAndTestOnlyMintHookWithoutChangingSupply() public {
        PauseTestMintHarness harness = new PauseTestMintHarness(IGuardERC20(parent), HOLDER);
        pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        new CL8Y_v2(IGuardERC20(parent), HOLDER);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        harness.mintForTest(RECIPIENT, 1 ether);
        assertEq(harness.totalSupply(), 3_000_000 ether);
        assertEq(harness.balanceOf(RECIPIENT), 0);
    }

    function test_PauseRoleIsImmediateAndCannotResumeManageExecuteOrAdministerAuthority() public {
        uint64 adminRole = manager.ADMIN_ROLE();
        (bool immediate, uint32 delay) = manager.canCall(PAUSER, address(module), GuardERC20Pause.pause.selector);
        assertTrue(immediate);
        assertEq(delay, 0);
        (bool admin,) = manager.hasRole(manager.ADMIN_ROLE(), PAUSER);
        assertFalse(admin);
        assertEq(manager.getRoleAdmin(PAUSE_ROLE), manager.ADMIN_ROLE());
        assertEq(manager.getRoleGuardian(PAUSE_ROLE), manager.ADMIN_ROLE());
        pause();
        vm.startPrank(PAUSER);
        vm.expectRevert();
        module.unpause();
        vm.expectRevert();
        parent.addGuardModule(address(0x777));
        vm.expectRevert();
        parent.removeGuardModule(address(module));
        vm.expectRevert();
        parent.execute(address(token), abi.encodeCall(IERC20.transfer, (RECIPIENT, 1)));
        vm.expectRevert();
        module.setAuthority(address(manager));
        vm.expectRevert();
        manager.updateAuthority(address(module), address(manager));
        vm.expectRevert();
        manager.grantRole(adminRole, PAUSER, 0);
        vm.expectRevert();
        manager.setRoleAdmin(PAUSE_ROLE, PAUSE_ROLE);
        vm.expectRevert();
        manager.setRoleGuardian(PAUSE_ROLE, PAUSE_ROLE);
        vm.expectRevert();
        manager.setTargetClosed(address(parent), true);
        vm.stopPrank();
        assertTrue(module.paused());
    }

    function test_PauseRevocationAndRotationNeverAutomaticallyResume() public {
        pause();
        vm.startPrank(GOVERNANCE);
        manager.revokeRole(PAUSE_ROLE, PAUSER);
        manager.grantRole(PAUSE_ROLE, REPLACEMENT, 0);
        assertTrue(module.paused());
        module.unpause();
        vm.stopPrank();
        vm.prank(PAUSER);
        vm.expectRevert();
        module.pause();
        vm.prank(REPLACEMENT);
        module.pause();
        assertTrue(module.paused());
        vm.prank(GOVERNANCE);
        module.unpause();
        vm.prank(HOLDER);
        token.transfer(RECIPIENT, 1 ether);
    }

    function test_PauseBothTargetClosuresLeaveUnrestrictedTransferChecksRunning() public {
        vm.prank(GOVERNANCE);
        manager.setTargetClosed(address(parent), true);
        vm.prank(HOLDER);
        token.transfer(RECIPIENT, 1 ether);
        vm.prank(PAUSER);
        module.pause();
        vm.prank(HOLDER);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.transfer(RECIPIENT, 1 ether);
        vm.startPrank(GOVERNANCE);
        manager.setTargetClosed(address(parent), false);
        module.unpause();
        manager.setTargetClosed(address(module), true);
        vm.stopPrank();
        vm.prank(HOLDER);
        token.transfer(RECIPIENT, 1 ether);
        vm.prank(PAUSER);
        vm.expectRevert();
        module.pause();
        vm.startPrank(GOVERNANCE);
        manager.setTargetClosed(address(module), false);
        vm.stopPrank();
        pause();
        vm.prank(GOVERNANCE);
        manager.setTargetClosed(address(module), true);
        vm.prank(HOLDER);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.transfer(RECIPIENT, 1 ether);
        assertTrue(module.paused());
    }

    function test_PauseAppliesToEveryTokenSharingTheGuardAndRejectsNonParentCallers() public {
        CL8Y_v2 other = new CL8Y_v2(IGuardERC20(parent), HOLDER);
        vm.expectRevert(abi.encodeWithSelector(GuardERC20Pause.UnauthorizedGuard.selector, address(this)));
        module.check(HOLDER, RECIPIENT, 1);
        pause();
        vm.startPrank(HOLDER);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.transfer(RECIPIENT, 1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        other.transfer(RECIPIENT, 1);
        vm.stopPrank();
    }

    function test_PausePreservesOtherModuleRulesAndRollsBackEarlierModuleChanges() public {
        PauseTestOtherModule other = new PauseTestOtherModule();
        vm.startPrank(GOVERNANCE);
        parent.removeGuardModule(address(module));
        parent.addGuardModule(address(other));
        parent.addGuardModule(address(module));
        vm.stopPrank();
        pause();
        vm.prank(HOLDER);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.transfer(RECIPIENT, 1);
        assertEq(other.calls(), 0);
        vm.prank(GOVERNANCE);
        module.unpause();
        other.setReject(true);
        vm.prank(HOLDER);
        vm.expectRevert(bytes("other module restriction"));
        token.transfer(RECIPIENT, 1);
    }

    function test_PauseNoGovernanceExecuteOrAssetRecoveryBypass() public {
        PauseTestBlacklist blacklist = new PauseTestBlacklist();
        AssetRecovery recovery =
            new AssetRecovery(address(manager), IGuardExecutor(address(parent)), IERC20(address(token)), blacklist);
        vm.startPrank(GOVERNANCE);
        bytes4[] memory execute = new bytes4[](1);
        execute[0] = GuardERC20.execute.selector;
        uint64 recoveryExecuteRole = 78; // Synthetic fixture permission, only this executor selector.
        manager.setTargetFunctionRole(address(parent), execute, recoveryExecuteRole);
        manager.grantRole(recoveryExecuteRole, GOVERNANCE, 0);
        manager.grantRole(recoveryExecuteRole, address(recovery), 0);
        vm.stopPrank();
        blacklist.set(HOLDER);
        vm.prank(HOLDER);
        token.approve(address(parent), 100 ether);
        // The recovery adapter has only its explicit synthetic executor role;
        // the emergency identity never gets that permission.
        vm.prank(GOVERNANCE);
        recovery.seize(HOLDER, 10 ether);
        assertEq(recovery.holdings(HOLDER), 10 ether);
        pause();
        vm.startPrank(GOVERNANCE);
        vm.expectRevert();
        parent.execute(address(token), abi.encodeCall(IERC20.transferFrom, (HOLDER, RECIPIENT, 1 ether)));
        vm.expectRevert();
        recovery.seize(HOLDER, 1 ether);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        recovery.release(HOLDER, 1 ether);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        recovery.recover(HOLDER, RECIPIENT, 1 ether);
        vm.stopPrank();
        assertEq(recovery.holdings(HOLDER), 10 ether);
        assertEq(token.balanceOf(address(recovery)), 10 ether);
    }

    function test_PauseConstructorRejectsZeroOrNonContractPins() public {
        vm.expectRevert(abi.encodeWithSelector(GuardERC20Pause.InvalidContract.selector, address(0)));
        new GuardERC20Pause(address(0), address(parent));
        vm.expectRevert(abi.encodeWithSelector(GuardERC20Pause.InvalidContract.selector, PAUSER));
        new GuardERC20Pause(address(manager), PAUSER);
    }
}
