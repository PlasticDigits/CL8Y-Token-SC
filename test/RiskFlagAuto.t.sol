// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {RiskFlagAuto} from "../src/RiskFlagAuto.sol";
import {DatastoreSetAddress, DatastoreSetIdAddress} from "../src/DatastoreSetAddress.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

contract RiskFlagAutoTest is Test {
    RiskFlagAuto riskFlagAuto;
    DatastoreSetAddress datastore;
    AccessManager accessManager;

    address owner = address(0x1);
    address exchange1 = address(0x100); // High-risk account (exchange)
    address exchange2 = address(0x101); // Another exchange
    address whitelisted1 = address(0x200); // Known good actor
    address whitelisted2 = address(0x201); // Another known good actor
    address attacker1 = address(0x300); // Potential attacker
    address attacker2 = address(0x301); // Another attacker
    address normalUser1 = address(0x400); // Normal user
    address normalUser2 = address(0x401); // Another normal user
    address unauthorizedUser = address(0x999);

    uint256 constant DEFAULT_THRESHOLD = 250 ether;
    uint256 constant WINDOW_DURATION = 86400; // 24 hours

    function setUp() public {
        vm.startPrank(owner);

        // Deploy AccessManager
        accessManager = new AccessManager(owner);

        // Deploy DatastoreSetAddress
        datastore = new DatastoreSetAddress();

        // Deploy RiskFlagAuto
        riskFlagAuto = new RiskFlagAuto(address(accessManager), datastore);

        // Configure function roles - set the restricted functions to be callable by ADMIN_ROLE
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = riskFlagAuto.setVolumeThreshold.selector;
        selectors[1] = riskFlagAuto.addHighRiskAccounts.selector;
        selectors[2] = riskFlagAuto.removeHighRiskAccounts.selector;
        selectors[3] = riskFlagAuto.addWhitelistedAccounts.selector;
        selectors[4] = riskFlagAuto.removeWhitelistedAccounts.selector;
        selectors[5] = riskFlagAuto.removeRiskFlaggedAccounts.selector;
        selectors[6] = riskFlagAuto.setWindowFlagged.selector;
        selectors[7] = riskFlagAuto.setWindowVolume.selector;

        accessManager.setTargetFunctionRole(address(riskFlagAuto), selectors, accessManager.ADMIN_ROLE());

        vm.stopPrank();
    }

    // ============ Initial State Tests ============

    function testInitialState() public view {
        assertEq(riskFlagAuto.volumeThreshold(), DEFAULT_THRESHOLD);
        assertEq(address(riskFlagAuto.datastore()), address(datastore));
        assertFalse(riskFlagAuto.isHighRisk(exchange1));
        assertFalse(riskFlagAuto.isWhitelisted(whitelisted1));
        assertFalse(riskFlagAuto.isRiskFlagged(attacker1));
    }

    function testSetIdConstants() public view {
        // Verify set IDs are deterministic
        assertEq(
            DatastoreSetIdAddress.unwrap(riskFlagAuto.SET_HIGH_RISK()),
            keccak256("RiskFlagAuto.HIGH_RISK")
        );
        assertEq(
            DatastoreSetIdAddress.unwrap(riskFlagAuto.SET_WHITELISTED()),
            keccak256("RiskFlagAuto.WHITELISTED")
        );
        assertEq(
            DatastoreSetIdAddress.unwrap(riskFlagAuto.SET_RISK_FLAGGED()),
            keccak256("RiskFlagAuto.RISK_FLAGGED")
        );
    }

    // ============ Admin Functions: High-Risk Accounts ============

    function testAddHighRiskAccounts() public {
        address[] memory accounts = new address[](2);
        accounts[0] = exchange1;
        accounts[1] = exchange2;

        vm.prank(owner);
        riskFlagAuto.addHighRiskAccounts(accounts);

        assertTrue(riskFlagAuto.isHighRisk(exchange1));
        assertTrue(riskFlagAuto.isHighRisk(exchange2));
        assertFalse(riskFlagAuto.isHighRisk(normalUser1));
    }

    function testRemoveHighRiskAccounts() public {
        address[] memory accounts = new address[](2);
        accounts[0] = exchange1;
        accounts[1] = exchange2;

        vm.prank(owner);
        riskFlagAuto.addHighRiskAccounts(accounts);

        address[] memory toRemove = new address[](1);
        toRemove[0] = exchange1;

        vm.prank(owner);
        riskFlagAuto.removeHighRiskAccounts(toRemove);

        assertFalse(riskFlagAuto.isHighRisk(exchange1));
        assertTrue(riskFlagAuto.isHighRisk(exchange2));
    }

    function testAddHighRiskAccountsAccessControl() public {
        address[] memory accounts = new address[](1);
        accounts[0] = exchange1;

        vm.prank(unauthorizedUser);
        vm.expectRevert();
        riskFlagAuto.addHighRiskAccounts(accounts);
    }

    function testRemoveHighRiskAccountsAccessControl() public {
        address[] memory accounts = new address[](1);
        accounts[0] = exchange1;

        vm.prank(unauthorizedUser);
        vm.expectRevert();
        riskFlagAuto.removeHighRiskAccounts(accounts);
    }

    // ============ Admin Functions: Whitelisted Accounts ============

    function testAddWhitelistedAccounts() public {
        address[] memory accounts = new address[](2);
        accounts[0] = whitelisted1;
        accounts[1] = whitelisted2;

        vm.prank(owner);
        riskFlagAuto.addWhitelistedAccounts(accounts);

        assertTrue(riskFlagAuto.isWhitelisted(whitelisted1));
        assertTrue(riskFlagAuto.isWhitelisted(whitelisted2));
        assertFalse(riskFlagAuto.isWhitelisted(normalUser1));
    }

    function testRemoveWhitelistedAccounts() public {
        address[] memory accounts = new address[](2);
        accounts[0] = whitelisted1;
        accounts[1] = whitelisted2;

        vm.prank(owner);
        riskFlagAuto.addWhitelistedAccounts(accounts);

        address[] memory toRemove = new address[](1);
        toRemove[0] = whitelisted1;

        vm.prank(owner);
        riskFlagAuto.removeWhitelistedAccounts(toRemove);

        assertFalse(riskFlagAuto.isWhitelisted(whitelisted1));
        assertTrue(riskFlagAuto.isWhitelisted(whitelisted2));
    }

    function testAddWhitelistedAccountsAccessControl() public {
        address[] memory accounts = new address[](1);
        accounts[0] = whitelisted1;

        vm.prank(unauthorizedUser);
        vm.expectRevert();
        riskFlagAuto.addWhitelistedAccounts(accounts);
    }

    // ============ Admin Functions: Risk-Flagged Accounts ============

    function testRemoveRiskFlaggedAccounts() public {
        // First, create a scenario where an account gets flagged
        _setupExchange(exchange1);
        
        // Transfer over threshold to flag attacker1
        riskFlagAuto.check(exchange1, attacker1, 300 ether);
        assertTrue(riskFlagAuto.isRiskFlagged(attacker1));

        // Admin removes the flag after review
        address[] memory toRemove = new address[](1);
        toRemove[0] = attacker1;

        vm.prank(owner);
        riskFlagAuto.removeRiskFlaggedAccounts(toRemove);

        assertFalse(riskFlagAuto.isRiskFlagged(attacker1));
    }

    function testRemoveRiskFlaggedAccountsAccessControl() public {
        address[] memory accounts = new address[](1);
        accounts[0] = attacker1;

        vm.prank(unauthorizedUser);
        vm.expectRevert();
        riskFlagAuto.removeRiskFlaggedAccounts(accounts);
    }

    // ============ Admin Functions: Volume Threshold ============

    function testSetVolumeThreshold() public {
        uint256 newThreshold = 500 ether;

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit RiskFlagAuto.VolumeThresholdUpdated(DEFAULT_THRESHOLD, newThreshold);
        riskFlagAuto.setVolumeThreshold(newThreshold);

        assertEq(riskFlagAuto.volumeThreshold(), newThreshold);
    }

    function testSetVolumeThresholdAccessControl() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        riskFlagAuto.setVolumeThreshold(500 ether);
    }

    // ============ Admin Functions: Window Flagging ============

    function testSetWindowFlaggedToTrue() public {
        _setupExchange(exchange1);
        uint256 windowId = block.timestamp / WINDOW_DURATION;

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit RiskFlagAuto.WindowFlagged(exchange1, windowId, 0);
        riskFlagAuto.setWindowFlagged(exchange1, windowId, true);

        assertTrue(riskFlagAuto.isWindowFlagged(exchange1, windowId));
    }

    function testSetWindowFlaggedToFalse() public {
        _setupExchange(exchange1);
        uint256 windowId = block.timestamp / WINDOW_DURATION;

        // First flag the window
        vm.prank(owner);
        riskFlagAuto.setWindowFlagged(exchange1, windowId, true);
        assertTrue(riskFlagAuto.isWindowFlagged(exchange1, windowId));

        // Then unflag it
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit RiskFlagAuto.WindowUnflagged(exchange1, windowId);
        riskFlagAuto.setWindowFlagged(exchange1, windowId, false);

        assertFalse(riskFlagAuto.isWindowFlagged(exchange1, windowId));
    }

    function testSetWindowFlaggedAccessControl() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        riskFlagAuto.setWindowFlagged(exchange1, 0, true);
    }

    // ============ Admin Functions: Window Volume ============

    function testSetWindowVolume() public {
        _setupExchange(exchange1);
        uint256 windowId = block.timestamp / WINDOW_DURATION;
        uint256 volume = 100 ether;

        vm.prank(owner);
        riskFlagAuto.setWindowVolume(exchange1, windowId, volume);

        assertEq(riskFlagAuto.windowVolume(exchange1, windowId), volume);
    }

    function testSetWindowVolumeAccessControl() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        riskFlagAuto.setWindowVolume(exchange1, 0, 100 ether);
    }

    // ============ Check Function: Basic Flow ============

    function testCheckSkipsMintOperation() public {
        // Mint (from = address(0)) should not revert
        riskFlagAuto.check(address(0), normalUser1, 1000 ether);
        // No state changes expected
        assertFalse(riskFlagAuto.isRiskFlagged(normalUser1));
    }

    function testCheckSkipsBurnOperation() public {
        // Burn (to = address(0)) should not revert
        riskFlagAuto.check(normalUser1, address(0), 1000 ether);
        // No state changes expected
    }

    function testCheckNormalUserToNormalUser() public {
        // Normal user transfers should pass through without any tracking
        riskFlagAuto.check(normalUser1, normalUser2, 1000 ether);
        
        // No volume tracked, no flagging
        assertFalse(riskFlagAuto.isRiskFlagged(normalUser1));
        assertFalse(riskFlagAuto.isRiskFlagged(normalUser2));
    }

    function testCheckFromHighRiskBelowThreshold() public {
        _setupExchange(exchange1);

        // Transfer below threshold should track volume but not flag
        riskFlagAuto.check(exchange1, attacker1, 100 ether);

        uint256 windowId = block.timestamp / WINDOW_DURATION;
        assertEq(riskFlagAuto.windowVolume(exchange1, windowId), 100 ether);
        assertFalse(riskFlagAuto.isRiskFlagged(attacker1));
        assertFalse(riskFlagAuto.isWindowFlagged(exchange1, windowId));
    }

    function testCheckFromHighRiskExceedsThreshold() public {
        _setupExchange(exchange1);
        uint256 windowId = block.timestamp / WINDOW_DURATION;

        // Transfer over threshold should flag recipient and window
        vm.expectEmit(true, true, true, true);
        emit RiskFlagAuto.AccountRiskFlagged(attacker1, exchange1, windowId);
        vm.expectEmit(true, true, true, true);
        emit RiskFlagAuto.WindowFlagged(exchange1, windowId, 300 ether);
        
        riskFlagAuto.check(exchange1, attacker1, 300 ether);

        assertEq(riskFlagAuto.windowVolume(exchange1, windowId), 300 ether);
        assertTrue(riskFlagAuto.isRiskFlagged(attacker1));
        assertTrue(riskFlagAuto.isWindowFlagged(exchange1, windowId));
    }

    function testCheckFromHighRiskCumulativeExceedsThreshold() public {
        _setupExchange(exchange1);
        uint256 windowId = block.timestamp / WINDOW_DURATION;

        // First transfer: 200 ether (below threshold)
        riskFlagAuto.check(exchange1, attacker1, 200 ether);
        assertFalse(riskFlagAuto.isRiskFlagged(attacker1));
        assertFalse(riskFlagAuto.isWindowFlagged(exchange1, windowId));

        // Second transfer: 100 ether (cumulative 300, exceeds threshold)
        riskFlagAuto.check(exchange1, attacker2, 100 ether);
        
        assertEq(riskFlagAuto.windowVolume(exchange1, windowId), 300 ether);
        assertTrue(riskFlagAuto.isRiskFlagged(attacker2));
        assertTrue(riskFlagAuto.isWindowFlagged(exchange1, windowId));
        // First recipient was not flagged because threshold wasn't exceeded at that time
        assertFalse(riskFlagAuto.isRiskFlagged(attacker1));
    }

    function testCheckFromHighRiskToWhitelisted() public {
        _setupExchange(exchange1);
        _setupWhitelisted(whitelisted1);

        // Transfer to whitelisted should not track volume
        riskFlagAuto.check(exchange1, whitelisted1, 500 ether);

        uint256 windowId = block.timestamp / WINDOW_DURATION;
        assertEq(riskFlagAuto.windowVolume(exchange1, windowId), 0);
        assertFalse(riskFlagAuto.isRiskFlagged(whitelisted1));
    }

    function testCheckInFlaggedWindowFlagsRecipient() public {
        _setupExchange(exchange1);
        uint256 windowId = block.timestamp / WINDOW_DURATION;

        // First transfer exceeds threshold, flags window
        riskFlagAuto.check(exchange1, attacker1, 300 ether);
        assertTrue(riskFlagAuto.isWindowFlagged(exchange1, windowId));

        // Second transfer in same window should immediately flag recipient
        // even though amount is small
        vm.expectEmit(true, true, true, true);
        emit RiskFlagAuto.AccountRiskFlagged(attacker2, exchange1, windowId);
        riskFlagAuto.check(exchange1, attacker2, 10 ether);

        assertTrue(riskFlagAuto.isRiskFlagged(attacker2));
        // Volume should NOT be incremented when window is already flagged (early return)
        assertEq(riskFlagAuto.windowVolume(exchange1, windowId), 300 ether);
    }

    // ============ Check Function: Risk-Flagged Sender Behavior ============

    function testCheckRiskFlaggedNonHighRiskCannotSend() public {
        _setupExchange(exchange1);

        // Flag attacker1 by sending over threshold
        riskFlagAuto.check(exchange1, attacker1, 300 ether);
        assertTrue(riskFlagAuto.isRiskFlagged(attacker1));

        // Now attacker1 (risk-flagged, NOT high-risk) tries to send
        vm.expectRevert(abi.encodeWithSelector(RiskFlagAuto.RiskFlagged.selector, attacker1));
        riskFlagAuto.check(attacker1, normalUser1, 50 ether);
    }

    function testCheckRiskFlaggedNonHighRiskCanReceive() public {
        _setupExchange(exchange1);

        // Flag attacker1
        riskFlagAuto.check(exchange1, attacker1, 300 ether);
        assertTrue(riskFlagAuto.isRiskFlagged(attacker1));

        // Attacker1 can still receive from normal users
        riskFlagAuto.check(normalUser1, attacker1, 1000 ether);
        // No revert = success
    }

    function testCheckUnflaggedAccountCanSendAfterReview() public {
        _setupExchange(exchange1);

        // Flag attacker1
        riskFlagAuto.check(exchange1, attacker1, 300 ether);
        assertTrue(riskFlagAuto.isRiskFlagged(attacker1));

        // Admin reviews and removes flag
        address[] memory toRemove = new address[](1);
        toRemove[0] = attacker1;
        vm.prank(owner);
        riskFlagAuto.removeRiskFlaggedAccounts(toRemove);

        // Now attacker1 can send again
        riskFlagAuto.check(attacker1, normalUser1, 50 ether);
        // No revert = success
    }

    // ============ Check Function: Window Isolation ============

    function testCheckWindowsAreIsolatedPerHighRisk() public {
        _setupExchange(exchange1);
        _setupExchange(exchange2);
        uint256 windowId = block.timestamp / WINDOW_DURATION;

        // Exchange1 exceeds threshold
        riskFlagAuto.check(exchange1, attacker1, 300 ether);
        assertTrue(riskFlagAuto.isWindowFlagged(exchange1, windowId));

        // Exchange2's window should not be flagged
        assertFalse(riskFlagAuto.isWindowFlagged(exchange2, windowId));

        // Exchange2 transfer below threshold should not flag anyone
        riskFlagAuto.check(exchange2, attacker2, 100 ether);
        assertFalse(riskFlagAuto.isRiskFlagged(attacker2));
    }

    function testCheckNewWindowResetsVolume() public {
        _setupExchange(exchange1);

        // Transfer 200 ether in window 1
        riskFlagAuto.check(exchange1, attacker1, 200 ether);
        uint256 windowId1 = block.timestamp / WINDOW_DURATION;
        assertEq(riskFlagAuto.windowVolume(exchange1, windowId1), 200 ether);

        // Move to next window
        vm.warp(block.timestamp + WINDOW_DURATION);
        uint256 windowId2 = block.timestamp / WINDOW_DURATION;
        assertFalse(windowId1 == windowId2);

        // Transfer 100 ether in window 2 - should not exceed threshold
        riskFlagAuto.check(exchange1, attacker2, 100 ether);
        
        assertEq(riskFlagAuto.windowVolume(exchange1, windowId2), 100 ether);
        assertFalse(riskFlagAuto.isRiskFlagged(attacker2));
        assertFalse(riskFlagAuto.isWindowFlagged(exchange1, windowId2));
    }

    function testCheckFlaggedWindowDoesNotPersistToNextWindow() public {
        _setupExchange(exchange1);

        // Exceed threshold in window 1
        riskFlagAuto.check(exchange1, attacker1, 300 ether);
        uint256 windowId1 = block.timestamp / WINDOW_DURATION;
        assertTrue(riskFlagAuto.isWindowFlagged(exchange1, windowId1));

        // Move to next window
        vm.warp(block.timestamp + WINDOW_DURATION);
        uint256 windowId2 = block.timestamp / WINDOW_DURATION;

        // New window should not be flagged
        assertFalse(riskFlagAuto.isWindowFlagged(exchange1, windowId2));

        // Small transfer should not flag recipient
        riskFlagAuto.check(exchange1, attacker2, 50 ether);
        assertFalse(riskFlagAuto.isRiskFlagged(attacker2));
    }

    // ============ View Functions ============

    function testCurrentWindowId() public view {
        uint256 expected = block.timestamp / WINDOW_DURATION;
        assertEq(riskFlagAuto.currentWindowId(), expected);
    }

    function testGetWindowVolume() public {
        _setupExchange(exchange1);
        uint256 windowId = block.timestamp / WINDOW_DURATION;

        riskFlagAuto.check(exchange1, attacker1, 150 ether);
        
        assertEq(riskFlagAuto.getWindowVolume(exchange1, windowId), 150 ether);
    }

    function testGetCurrentWindowVolume() public {
        _setupExchange(exchange1);

        riskFlagAuto.check(exchange1, attacker1, 175 ether);
        
        assertEq(riskFlagAuto.getCurrentWindowVolume(exchange1), 175 ether);
    }

    function testGetRemainingVolume() public {
        _setupExchange(exchange1);

        // No transfers yet
        assertEq(riskFlagAuto.getRemainingVolume(exchange1), DEFAULT_THRESHOLD);

        // After 100 ether transfer
        riskFlagAuto.check(exchange1, attacker1, 100 ether);
        assertEq(riskFlagAuto.getRemainingVolume(exchange1), DEFAULT_THRESHOLD - 100 ether);

        // After exceeding threshold
        riskFlagAuto.check(exchange1, attacker2, 200 ether);
        assertEq(riskFlagAuto.getRemainingVolume(exchange1), 0);
    }

    // ============ Edge Cases ============

    function testCheckExactThreshold() public {
        _setupExchange(exchange1);
        uint256 windowId = block.timestamp / WINDOW_DURATION;

        // Transfer exactly the threshold - should NOT flag (> not >=)
        riskFlagAuto.check(exchange1, attacker1, DEFAULT_THRESHOLD);
        
        assertFalse(riskFlagAuto.isRiskFlagged(attacker1));
        assertFalse(riskFlagAuto.isWindowFlagged(exchange1, windowId));
    }

    function testCheckOneWeiOverThreshold() public {
        _setupExchange(exchange1);
        uint256 windowId = block.timestamp / WINDOW_DURATION;

        // Transfer threshold + 1 wei - should flag
        riskFlagAuto.check(exchange1, attacker1, DEFAULT_THRESHOLD + 1);
        
        assertTrue(riskFlagAuto.isRiskFlagged(attacker1));
        assertTrue(riskFlagAuto.isWindowFlagged(exchange1, windowId));
    }

    function testCheckZeroAmount() public {
        _setupExchange(exchange1);
        uint256 windowId = block.timestamp / WINDOW_DURATION;

        // Zero amount transfer should pass but not change anything meaningful
        riskFlagAuto.check(exchange1, attacker1, 0);
        
        assertEq(riskFlagAuto.windowVolume(exchange1, windowId), 0);
        assertFalse(riskFlagAuto.isRiskFlagged(attacker1));
    }

    function testCheckLargeAmount() public {
        _setupExchange(exchange1);
        uint256 windowId = block.timestamp / WINDOW_DURATION;
        uint256 largeAmount = 1_000_000 ether;

        riskFlagAuto.check(exchange1, attacker1, largeAmount);
        
        assertEq(riskFlagAuto.windowVolume(exchange1, windowId), largeAmount);
        assertTrue(riskFlagAuto.isRiskFlagged(attacker1));
    }

    function testCheckSameRecipientMultipleTimes() public {
        _setupExchange(exchange1);
        uint256 windowId = block.timestamp / WINDOW_DURATION;

        // Multiple small transfers to same recipient
        riskFlagAuto.check(exchange1, attacker1, 100 ether);
        riskFlagAuto.check(exchange1, attacker1, 100 ether);
        riskFlagAuto.check(exchange1, attacker1, 100 ether); // This one exceeds

        assertEq(riskFlagAuto.windowVolume(exchange1, windowId), 300 ether);
        assertTrue(riskFlagAuto.isRiskFlagged(attacker1));
        assertTrue(riskFlagAuto.isWindowFlagged(exchange1, windowId));
    }

    function testCheckHighRiskAccountCanAlwaysSend() public {
        _setupExchange(exchange1);

        // Even if somehow exchange1 got risk-flagged, it should still be able to send
        // because the check returns early for non-high-risk senders before the revert
        // and high-risk senders bypass the risk-flag check
        
        // This is a theoretical edge case - high-risk accounts shouldn't be risk-flagged
        // But let's verify the logic is correct
        
        // Transfer to trigger flagging of some recipient
        riskFlagAuto.check(exchange1, attacker1, 300 ether);
        
        // Exchange should still be able to send
        riskFlagAuto.check(exchange1, normalUser1, 100 ether);
        // No revert = success
    }

    // ============ Boundary Window Tests ============

    function testCheckAtWindowBoundary() public {
        _setupExchange(exchange1);

        // Warp to just before window boundary
        uint256 windowDuration = WINDOW_DURATION;
        uint256 nearBoundary = ((block.timestamp / windowDuration) + 1) * windowDuration - 1;
        vm.warp(nearBoundary);

        uint256 windowId1 = block.timestamp / WINDOW_DURATION;
        
        // Transfer just before boundary
        riskFlagAuto.check(exchange1, attacker1, 200 ether);
        assertEq(riskFlagAuto.windowVolume(exchange1, windowId1), 200 ether);

        // Warp 2 seconds to cross boundary
        vm.warp(block.timestamp + 2);
        uint256 windowId2 = block.timestamp / WINDOW_DURATION;
        assertTrue(windowId2 > windowId1);

        // Transfer after boundary should be in new window
        riskFlagAuto.check(exchange1, attacker2, 200 ether);
        
        // Old window unchanged
        assertEq(riskFlagAuto.windowVolume(exchange1, windowId1), 200 ether);
        // New window has new volume
        assertEq(riskFlagAuto.windowVolume(exchange1, windowId2), 200 ether);
        // Neither flagged (both under threshold)
        assertFalse(riskFlagAuto.isRiskFlagged(attacker1));
        assertFalse(riskFlagAuto.isRiskFlagged(attacker2));
    }

    // ============ Helper Functions ============

    function _setupExchange(address exchange) internal {
        address[] memory accounts = new address[](1);
        accounts[0] = exchange;
        vm.prank(owner);
        riskFlagAuto.addHighRiskAccounts(accounts);
    }

    function _setupWhitelisted(address account) internal {
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        vm.prank(owner);
        riskFlagAuto.addWhitelistedAccounts(accounts);
    }
}

// ============ Integration Test ============

contract RiskFlagAutoIntegrationTest is Test {
    RiskFlagAuto riskFlagAuto;
    DatastoreSetAddress datastore;
    AccessManager accessManager;

    address admin = address(0x1);
    address binanceHotWallet = address(0xBEEF1);
    address coinbaseHotWallet = address(0xBEEF2);
    address trustedTrader = address(0xABCD1);
    address hacker = address(0xDEAD1);
    address hackerWallet2 = address(0xDEAD2);
    address hackerWallet3 = address(0xDEAD3);
    address innocentUser = address(0x1234);

    uint256 constant WINDOW_DURATION = 86400;

    function setUp() public {
        vm.startPrank(admin);

        accessManager = new AccessManager(admin);
        datastore = new DatastoreSetAddress();
        riskFlagAuto = new RiskFlagAuto(address(accessManager), datastore);

        // Configure access control
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = riskFlagAuto.setVolumeThreshold.selector;
        selectors[1] = riskFlagAuto.addHighRiskAccounts.selector;
        selectors[2] = riskFlagAuto.removeHighRiskAccounts.selector;
        selectors[3] = riskFlagAuto.addWhitelistedAccounts.selector;
        selectors[4] = riskFlagAuto.removeWhitelistedAccounts.selector;
        selectors[5] = riskFlagAuto.removeRiskFlaggedAccounts.selector;
        selectors[6] = riskFlagAuto.setWindowFlagged.selector;
        selectors[7] = riskFlagAuto.setWindowVolume.selector;
        accessManager.setTargetFunctionRole(address(riskFlagAuto), selectors, accessManager.ADMIN_ROLE());

        // Setup: Add exchanges as high-risk
        address[] memory exchanges = new address[](2);
        exchanges[0] = binanceHotWallet;
        exchanges[1] = coinbaseHotWallet;
        riskFlagAuto.addHighRiskAccounts(exchanges);

        // Setup: Add trusted trader to whitelist
        address[] memory whitelist = new address[](1);
        whitelist[0] = trustedTrader;
        riskFlagAuto.addWhitelistedAccounts(whitelist);

        vm.stopPrank();
    }

    /**
     * @notice Integration test simulating a real attack scenario:
     * 1. Hacker exploits a protocol and receives stolen CL8Y
     * 2. Hacker launders funds through an exchange
     * 3. System auto-flags the receiving wallets
     * 4. Hacker's wallets are frozen
     * 5. Admin reviews and takes action
     */
    function testAttackScenario() public {
        console.log("=== ATTACK SCENARIO SIMULATION ===");
        console.log("");

        // --- Phase 1: Normal activity before attack ---
        console.log("Phase 1: Normal activity");
        
        // Trusted trader withdraws from exchange (whitelisted, no flagging)
        riskFlagAuto.check(binanceHotWallet, trustedTrader, 500 ether);
        assertFalse(riskFlagAuto.isRiskFlagged(trustedTrader));
        console.log("  - Trusted trader withdrew 500 CL8Y from Binance: OK");

        // Innocent user withdraws small amount
        riskFlagAuto.check(coinbaseHotWallet, innocentUser, 50 ether);
        assertFalse(riskFlagAuto.isRiskFlagged(innocentUser));
        console.log("  - Innocent user withdrew 50 CL8Y from Coinbase: OK");

        // Current volume tracked
        assertEq(riskFlagAuto.getCurrentWindowVolume(coinbaseHotWallet), 50 ether);
        console.log("");

        // --- Phase 2: Attack begins ---
        console.log("Phase 2: Attack begins (hacker launders through Binance)");
        
        // Hacker withdraws large amount from Binance
        uint256 windowId = block.timestamp / WINDOW_DURATION;
        
        vm.expectEmit(true, true, true, true);
        emit RiskFlagAuto.AccountRiskFlagged(hacker, binanceHotWallet, windowId);
        vm.expectEmit(true, true, true, true);
        emit RiskFlagAuto.WindowFlagged(binanceHotWallet, windowId, 1000 ether);
        
        riskFlagAuto.check(binanceHotWallet, hacker, 1000 ether);
        
        assertTrue(riskFlagAuto.isRiskFlagged(hacker));
        assertTrue(riskFlagAuto.isWindowFlagged(binanceHotWallet, windowId));
        console.log("  - Hacker withdrew 1000 CL8Y: FLAGGED");
        console.log("  - Binance window: FLAGGED");
        console.log("");

        // --- Phase 3: Hacker tries to launder to multiple wallets ---
        console.log("Phase 3: Additional withdrawals in flagged window");
        
        // All subsequent withdrawals from Binance in this window get flagged
        riskFlagAuto.check(binanceHotWallet, hackerWallet2, 10 ether);
        assertTrue(riskFlagAuto.isRiskFlagged(hackerWallet2));
        console.log("  - Hacker wallet 2 withdrew 10 CL8Y: FLAGGED (window is hot)");

        riskFlagAuto.check(binanceHotWallet, hackerWallet3, 5 ether);
        assertTrue(riskFlagAuto.isRiskFlagged(hackerWallet3));
        console.log("  - Hacker wallet 3 withdrew 5 CL8Y: FLAGGED (window is hot)");
        console.log("");

        // --- Phase 4: Hacker tries to move funds ---
        console.log("Phase 4: Flagged accounts cannot send");
        
        vm.expectRevert(abi.encodeWithSelector(RiskFlagAuto.RiskFlagged.selector, hacker));
        riskFlagAuto.check(hacker, address(0x9999), 100 ether);
        console.log("  - Hacker tried to send: BLOCKED");

        vm.expectRevert(abi.encodeWithSelector(RiskFlagAuto.RiskFlagged.selector, hackerWallet2));
        riskFlagAuto.check(hackerWallet2, address(0x9999), 5 ether);
        console.log("  - Hacker wallet 2 tried to send: BLOCKED");
        console.log("");

        // --- Phase 5: Meanwhile, Coinbase is unaffected ---
        console.log("Phase 5: Other exchanges unaffected");
        
        // Coinbase window is independent
        assertFalse(riskFlagAuto.isWindowFlagged(coinbaseHotWallet, windowId));
        
        // Small withdrawal from Coinbase is fine
        riskFlagAuto.check(coinbaseHotWallet, address(0x5555), 100 ether);
        assertFalse(riskFlagAuto.isRiskFlagged(address(0x5555)));
        console.log("  - User withdrew 100 CL8Y from Coinbase: OK (different exchange)");
        console.log("");

        // --- Phase 6: Admin reviews ---
        console.log("Phase 6: Admin reviews flagged accounts");
        
        // Check flagged count
        uint256 flaggedCount = datastore.length(address(riskFlagAuto), riskFlagAuto.SET_RISK_FLAGGED());
        assertEq(flaggedCount, 3);
        console.log("  - Total flagged accounts:", flaggedCount);

        // Get all flagged accounts
        address[] memory flagged = datastore.getAll(address(riskFlagAuto), riskFlagAuto.SET_RISK_FLAGGED());
        for (uint256 i = 0; i < flagged.length; i++) {
            console.log("  - Flagged:", flagged[i]);
        }
        console.log("");

        // --- Phase 7: Admin takes action ---
        console.log("Phase 7: Admin action after review");
        
        // After review, admin determines innocentUser was caught in the crossfire
        // (they withdrew before the attack but same window)
        // Note: In this test, innocentUser withdrew from Coinbase which wasn't flagged
        // So let's say hacker wallet 3 was actually innocent
        
        address[] memory toUnflag = new address[](1);
        toUnflag[0] = hackerWallet3; // Pretend review showed this was innocent
        
        vm.prank(admin);
        riskFlagAuto.removeRiskFlaggedAccounts(toUnflag);
        
        assertFalse(riskFlagAuto.isRiskFlagged(hackerWallet3));
        console.log("  - Wallet 3 cleared after review: CAN SEND");
        
        // Wallet 3 can now send
        riskFlagAuto.check(hackerWallet3, address(0x8888), 5 ether);
        console.log("  - Wallet 3 successfully sent funds");
        console.log("");

        // --- Phase 8: New day, new window ---
        console.log("Phase 8: New window (next day)");
        
        vm.warp(block.timestamp + WINDOW_DURATION);
        uint256 newWindowId = block.timestamp / WINDOW_DURATION;
        assertTrue(newWindowId > windowId);
        
        // Binance window is no longer flagged (new day)
        assertFalse(riskFlagAuto.isWindowFlagged(binanceHotWallet, newWindowId));
        
        // New withdrawals are not auto-flagged
        address newUser = address(0x7777);
        riskFlagAuto.check(binanceHotWallet, newUser, 100 ether);
        assertFalse(riskFlagAuto.isRiskFlagged(newUser));
        console.log("  - New day: Binance withdrawals OK again");
        
        // But hacker wallets are still frozen (risk flag persists until admin removes)
        assertTrue(riskFlagAuto.isRiskFlagged(hacker));
        assertTrue(riskFlagAuto.isRiskFlagged(hackerWallet2));
        console.log("  - Hacker wallets still frozen: CORRECT");
        console.log("");

        console.log("=== ATTACK SCENARIO COMPLETE ===");
    }

    /**
     * @notice Test the edge case of attacking at window boundary
     * Attacker tries to get ~500 CL8Y through by doing 249 at end of window
     * and 249 at start of next window
     */
    function testWindowBoundaryAttack() public {
        console.log("=== WINDOW BOUNDARY ATTACK ===");
        console.log("");

        // Warp to just before window boundary
        uint256 nearBoundary = ((block.timestamp / WINDOW_DURATION) + 1) * WINDOW_DURATION - 10;
        vm.warp(nearBoundary);

        console.log("Step 1: Attacker withdraws 249 CL8Y just before window ends");
        riskFlagAuto.check(binanceHotWallet, hacker, 249 ether);
        assertFalse(riskFlagAuto.isRiskFlagged(hacker));
        console.log("  - Status: NOT FLAGGED (under threshold)");

        // Warp past boundary
        vm.warp(block.timestamp + 20);
        console.log("");
        console.log("Step 2: Attacker withdraws 249 CL8Y just after new window starts");
        riskFlagAuto.check(binanceHotWallet, hackerWallet2, 249 ether);
        assertFalse(riskFlagAuto.isRiskFlagged(hackerWallet2));
        console.log("  - Status: NOT FLAGGED (new window, under threshold)");
        console.log("");

        console.log("Result: Attacker got ~498 CL8Y through unflagged");
        console.log("This is expected behavior - tradeoff for usability");
        console.log("");

        // Both wallets can send
        riskFlagAuto.check(hacker, address(0x9999), 100 ether);
        riskFlagAuto.check(hackerWallet2, address(0x8888), 100 ether);
        console.log("Both attacker wallets can transfer freely.");
        console.log("");
        console.log("=== END WINDOW BOUNDARY ATTACK ===");
    }
}
