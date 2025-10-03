// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {RateLimiting} from "../src/RateLimiting.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

// Mock ERC20 token for testing
contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    RateLimiting public rateLimiting;

    function setRateLimiting(address _rateLimiting) external {
        rateLimiting = RateLimiting(_rateLimiting);
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (address(rateLimiting) != address(0)) {
            rateLimiting.check(msg.sender, to, amount);
        }
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        if (address(rateLimiting) != address(0)) {
            rateLimiting.check(from, to, amount);
        }
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256) {
        return _allowances[owner][spender];
    }
}

contract RateLimitingTest is Test {
    RateLimiting rateLimiting;
    MockERC20 token;
    AccessManager accessManager;

    address owner = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address user3 = address(0x4);
    address unauthorizedUser = address(0x5);

    uint256 constant DEFAULT_INTERVAL = 1 days;
    uint256 constant DEFAULT_LIMIT = 1000 ether;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy AccessManager with owner
        accessManager = new AccessManager(owner);

        // Deploy mock token
        token = new MockERC20();

        // Deploy RateLimiting contract
        rateLimiting = new RateLimiting(
            address(accessManager),
            IERC20(address(token)),
            DEFAULT_INTERVAL,
            DEFAULT_LIMIT
        );

        // Set rate limiting in token
        token.setRateLimiting(address(rateLimiting));

        // Configure function roles - set the restricted functions to be callable by ADMIN_ROLE
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = RateLimiting.setDefaultConfig.selector;
        selectors[1] = RateLimiting.setAccountConfig.selector;
        selectors[2] = RateLimiting.setCurrentUsage.selector;
        selectors[3] = RateLimiting.setAccountToDefault.selector;

        accessManager.setTargetFunctionRole(
            address(rateLimiting),
            selectors,
            accessManager.ADMIN_ROLE()
        );

        // Grant admin role to owner
        accessManager.grantRole(accessManager.ADMIN_ROLE(), owner, 0);

        // Mint some tokens for testing
        token.mint(user1, 10000 ether);
        token.mint(user2, 10000 ether);
        token.mint(user3, 10000 ether);

        vm.stopPrank();
    }

    function testInitialState() public view {
        // Test that default config is set correctly
        (uint256 interval, uint256 limit) = rateLimiting.defaultConfig();
        assertEq(interval, DEFAULT_INTERVAL);
        assertEq(limit, DEFAULT_LIMIT);

        // Test that cl8y token is set correctly
        assertEq(address(rateLimiting.cl8y()), address(token));
    }

    function testCheckWithDefaultConfig() public {
        // User1 should be able to transfer within rate limit
        vm.prank(user1);
        token.transfer(user2, 500 ether);

        // Check usage was updated
        (uint256 total, uint256 windowId) = rateLimiting.currentUsage(user1);
        assertEq(total, 500 ether);
        assertEq(windowId, block.timestamp / DEFAULT_INTERVAL);

        console.log("Default rate limiting working correctly");
    }

    function testCheckWithCumulativeTransfers() public {
        // Multiple transfers should accumulate
        vm.startPrank(user1);
        token.transfer(user2, 300 ether);
        token.transfer(user2, 400 ether);
        vm.stopPrank();

        // Check cumulative usage
        (uint256 total, ) = rateLimiting.currentUsage(user1);
        assertEq(total, 700 ether);

        console.log("Cumulative transfers tracked correctly");
    }

    function testCheckRateLimitExceeded() public {
        // Try to transfer more than rate limit
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                RateLimiting.RateLimitExceeded.selector,
                user1
            )
        );
        token.transfer(user2, DEFAULT_LIMIT + 1);

        console.log("Rate limit exceeded error working correctly");
    }

    function testCheckRateLimitExceededCumulative() public {
        // Transfer close to limit
        vm.prank(user1);
        token.transfer(user2, DEFAULT_LIMIT - 100 ether);

        // Next transfer should exceed limit
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                RateLimiting.RateLimitExceeded.selector,
                user1
            )
        );
        token.transfer(user2, 101 ether);

        console.log("Cumulative rate limit exceeded working correctly");
    }

    function testCheckWindowReset() public {
        // Transfer in first window
        vm.prank(user1);
        token.transfer(user2, 500 ether);

        (uint256 totalBefore, ) = rateLimiting.currentUsage(user1);
        assertEq(totalBefore, 500 ether);

        // Move to next window
        vm.warp(block.timestamp + DEFAULT_INTERVAL);

        // Transfer in new window should reset counter
        vm.prank(user1);
        token.transfer(user2, 600 ether);

        (uint256 totalAfter, uint256 windowId) = rateLimiting.currentUsage(
            user1
        );
        assertEq(totalAfter, 600 ether);
        assertEq(windowId, block.timestamp / DEFAULT_INTERVAL);

        console.log("Window reset working correctly");
    }

    function testCheckInvalidSender() public {
        // Call check directly from non-token address should revert
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(RateLimiting.InvalidSender.selector, user1)
        );
        rateLimiting.check(user1, user2, 100 ether);

        console.log("InvalidSender error working correctly");
    }

    function testOptOutRequest() public {
        vm.prank(user1);
        rateLimiting.optOutRequest();

        uint256 timestamp = rateLimiting.optOutRequestTimestamp(user1);
        assertEq(timestamp, block.timestamp);

        console.log("Opt-out request working correctly");
    }

    function testOptOutActivate() public {
        // First request opt-out
        vm.prank(user1);
        rateLimiting.optOutRequest();

        // Fast forward past the interval
        vm.warp(block.timestamp + DEFAULT_INTERVAL + 1);

        // Activate opt-out
        vm.prank(user1);
        rateLimiting.optOutActivate();

        // Check status changed
        (, , RateLimiting.AccountStatus status) = rateLimiting.accountConfig(
            user1
        );
        assertEq(uint8(status), uint8(RateLimiting.AccountStatus.OPT_OUT));

        // Check timestamp was cleared
        assertEq(rateLimiting.optOutRequestTimestamp(user1), 0);

        console.log("Opt-out activation working correctly");
    }

    function testOptOutActivateNotRequested() public {
        // Try to activate without requesting
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                RateLimiting.OptOutNotRequested.selector,
                user1
            )
        );
        rateLimiting.optOutActivate();

        console.log("OptOutNotRequested error working correctly");
    }

    function testOptOutActivateNotReady() public {
        // Request opt-out
        vm.prank(user1);
        rateLimiting.optOutRequest();

        // Try to activate before interval passes
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(RateLimiting.OptOutNotReady.selector, user1)
        );
        rateLimiting.optOutActivate();

        console.log("OptOutNotReady error working correctly");
    }

    function testOptOutActivateFromOptInStatus() public {
        // First set user to OPT_IN with custom interval
        uint256 customInterval = 2 days;
        vm.prank(owner);
        rateLimiting.setAccountConfig(
            user1,
            customInterval,
            500 ether,
            RateLimiting.AccountStatus.OPT_IN
        );

        // Request opt-out
        vm.prank(user1);
        rateLimiting.optOutRequest();

        // Should need to wait for custom interval, not default
        vm.warp(block.timestamp + customInterval + 1);

        // Activate opt-out
        vm.prank(user1);
        rateLimiting.optOutActivate();

        (, , RateLimiting.AccountStatus status) = rateLimiting.accountConfig(
            user1
        );
        assertEq(uint8(status), uint8(RateLimiting.AccountStatus.OPT_OUT));

        console.log("Opt-out from OPT_IN status working correctly");
    }

    function testOptInRequest() public {
        vm.prank(user1);
        rateLimiting.optInRequest();

        uint256 timestamp = rateLimiting.optInRequestTimestamp(user1);
        assertEq(timestamp, block.timestamp);

        console.log("Opt-in request working correctly");
    }

    function testOptInActivate() public {
        // First request opt-in
        vm.prank(user1);
        rateLimiting.optInRequest();

        // Fast forward past the interval
        vm.warp(block.timestamp + DEFAULT_INTERVAL + 1);

        // Activate opt-in with custom limits
        uint256 customInterval = 12 hours;
        uint256 customLimit = 500 ether;
        vm.prank(user1);
        rateLimiting.optInActivate(customInterval, customLimit);

        // Check config changed
        (
            uint256 interval,
            uint256 limit,
            RateLimiting.AccountStatus status
        ) = rateLimiting.accountConfig(user1);
        assertEq(interval, customInterval);
        assertEq(limit, customLimit);
        assertEq(uint8(status), uint8(RateLimiting.AccountStatus.OPT_IN));

        // Check timestamp was cleared
        assertEq(rateLimiting.optInRequestTimestamp(user1), 0);

        console.log("Opt-in activation working correctly");
    }

    function testOptInActivateNotRequested() public {
        // Try to activate without requesting
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                RateLimiting.OptInNotRequested.selector,
                user1
            )
        );
        rateLimiting.optInActivate(12 hours, 500 ether);

        console.log("OptInNotRequested error working correctly");
    }

    function testOptInActivateNotReady() public {
        // Request opt-in
        vm.prank(user1);
        rateLimiting.optInRequest();

        // Try to activate before interval passes
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(RateLimiting.OptInNotReady.selector, user1)
        );
        rateLimiting.optInActivate(12 hours, 500 ether);

        console.log("OptInNotReady error working correctly");
    }

    function testOptInActivateFromOptInStatus() public {
        // First set user to OPT_IN with custom interval
        uint256 firstInterval = 2 days;
        vm.prank(owner);
        rateLimiting.setAccountConfig(
            user1,
            firstInterval,
            500 ether,
            RateLimiting.AccountStatus.OPT_IN
        );

        // Request opt-in again (to change limits)
        vm.prank(user1);
        rateLimiting.optInRequest();

        // Should need to wait for current custom interval
        vm.warp(block.timestamp + firstInterval + 1);

        // Activate opt-in with new limits
        vm.prank(user1);
        rateLimiting.optInActivate(6 hours, 200 ether);

        (uint256 interval, uint256 limit, ) = rateLimiting.accountConfig(user1);
        assertEq(interval, 6 hours);
        assertEq(limit, 200 ether);

        console.log("Opt-in from OPT_IN status working correctly");
    }

    function testCheckWithOptOutStatus() public {
        // Set user to OPT_OUT
        vm.prank(owner);
        rateLimiting.setAccountConfig(
            user1,
            0,
            0,
            RateLimiting.AccountStatus.OPT_OUT
        );

        // Should be able to transfer any amount
        vm.prank(user1);
        token.transfer(user2, 5000 ether);

        // Usage should not be tracked
        (uint256 total, ) = rateLimiting.currentUsage(user1);
        assertEq(total, 0);

        console.log("OPT_OUT status bypasses rate limiting");
    }

    function testCheckWithOptOutOverrideStatus() public {
        // Set user to OPT_OUT_OVERRIDE
        vm.prank(owner);
        rateLimiting.setAccountConfig(
            user1,
            0,
            0,
            RateLimiting.AccountStatus.OPT_OUT_OVERRIDE
        );

        // Should be able to transfer any amount
        vm.prank(user1);
        token.transfer(user2, 5000 ether);

        // Usage should not be tracked
        (uint256 total, ) = rateLimiting.currentUsage(user1);
        assertEq(total, 0);

        console.log("OPT_OUT_OVERRIDE status bypasses rate limiting");
    }

    function testCheckWithOptInStatus() public {
        // Set user to OPT_IN with custom limits
        uint256 customInterval = 12 hours;
        uint256 customLimit = 500 ether;
        vm.prank(owner);
        rateLimiting.setAccountConfig(
            user1,
            customInterval,
            customLimit,
            RateLimiting.AccountStatus.OPT_IN
        );

        // Should be able to transfer up to custom limit
        vm.prank(user1);
        token.transfer(user2, 400 ether);

        // Should revert if exceeding custom limit
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                RateLimiting.RateLimitExceeded.selector,
                user1
            )
        );
        token.transfer(user2, 101 ether);

        console.log("OPT_IN status uses custom limits");
    }

    function testCheckWithOptInOverrideStatus() public {
        // Set user to OPT_IN_OVERRIDE with custom limits
        uint256 customInterval = 6 hours;
        uint256 customLimit = 300 ether;
        vm.prank(owner);
        rateLimiting.setAccountConfig(
            user1,
            customInterval,
            customLimit,
            RateLimiting.AccountStatus.OPT_IN_OVERRIDE
        );

        // Should be able to transfer up to custom limit
        vm.prank(user1);
        token.transfer(user2, 250 ether);

        // Should revert if exceeding custom limit
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                RateLimiting.RateLimitExceeded.selector,
                user1
            )
        );
        token.transfer(user2, 51 ether);

        console.log("OPT_IN_OVERRIDE status uses custom limits");
    }

    function testOverrideActiveErrorOnOptOutRequest() public {
        // Set user to OPT_IN_OVERRIDE
        vm.prank(owner);
        rateLimiting.setAccountConfig(
            user1,
            1 days,
            1000 ether,
            RateLimiting.AccountStatus.OPT_IN_OVERRIDE
        );

        // Try to request opt-out
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(RateLimiting.OverrideActive.selector, user1)
        );
        rateLimiting.optOutRequest();

        console.log("OverrideActive error on optOutRequest working correctly");
    }

    function testOverrideActiveErrorOnOptOutActivate() public {
        // Set user to OPT_OUT_OVERRIDE
        vm.prank(owner);
        rateLimiting.setAccountConfig(
            user1,
            0,
            0,
            RateLimiting.AccountStatus.OPT_OUT_OVERRIDE
        );

        // Try to activate opt-out
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(RateLimiting.OverrideActive.selector, user1)
        );
        rateLimiting.optOutActivate();

        console.log("OverrideActive error on optOutActivate working correctly");
    }

    function testOverrideActiveErrorOnOptInRequest() public {
        // Set user to OPT_OUT_OVERRIDE
        vm.prank(owner);
        rateLimiting.setAccountConfig(
            user1,
            0,
            0,
            RateLimiting.AccountStatus.OPT_OUT_OVERRIDE
        );

        // Try to request opt-in
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(RateLimiting.OverrideActive.selector, user1)
        );
        rateLimiting.optInRequest();

        console.log("OverrideActive error on optInRequest working correctly");
    }

    function testOverrideActiveErrorOnOptInActivate() public {
        // Set user to OPT_IN_OVERRIDE
        vm.prank(owner);
        rateLimiting.setAccountConfig(
            user1,
            1 days,
            1000 ether,
            RateLimiting.AccountStatus.OPT_IN_OVERRIDE
        );

        // Try to activate opt-in
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(RateLimiting.OverrideActive.selector, user1)
        );
        rateLimiting.optInActivate(12 hours, 500 ether);

        console.log("OverrideActive error on optInActivate working correctly");
    }

    function testRateLimitIntervalZeroError() public {
        // Set default interval to zero
        vm.prank(owner);
        rateLimiting.setDefaultConfig(0, 1000 ether);

        // Try to transfer
        vm.prank(user1);
        vm.expectRevert(RateLimiting.RateLimitIntervalZero.selector);
        token.transfer(user2, 100 ether);

        console.log("RateLimitIntervalZero error working correctly");
    }

    function testRateLimitIntervalZeroErrorWithOptIn() public {
        // Set user to OPT_IN with zero interval
        vm.prank(owner);
        rateLimiting.setAccountConfig(
            user1,
            0,
            500 ether,
            RateLimiting.AccountStatus.OPT_IN
        );

        // Try to transfer
        vm.prank(user1);
        vm.expectRevert(RateLimiting.RateLimitIntervalZero.selector);
        token.transfer(user2, 100 ether);

        console.log(
            "RateLimitIntervalZero error with OPT_IN working correctly"
        );
    }

    function testSetDefaultConfig() public {
        uint256 newInterval = 7 days;
        uint256 newLimit = 5000 ether;

        vm.prank(owner);
        rateLimiting.setDefaultConfig(newInterval, newLimit);

        (uint256 interval, uint256 limit) = rateLimiting.defaultConfig();
        assertEq(interval, newInterval);
        assertEq(limit, newLimit);

        console.log("setDefaultConfig working correctly");
    }

    function testSetDefaultConfigAccessControl() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        rateLimiting.setDefaultConfig(7 days, 5000 ether);

        console.log("Access control on setDefaultConfig working correctly");
    }

    function testSetAccountConfig() public {
        uint256 customInterval = 12 hours;
        uint256 customLimit = 750 ether;

        vm.prank(owner);
        rateLimiting.setAccountConfig(
            user1,
            customInterval,
            customLimit,
            RateLimiting.AccountStatus.OPT_IN
        );

        (
            uint256 interval,
            uint256 limit,
            RateLimiting.AccountStatus status
        ) = rateLimiting.accountConfig(user1);
        assertEq(interval, customInterval);
        assertEq(limit, customLimit);
        assertEq(uint8(status), uint8(RateLimiting.AccountStatus.OPT_IN));

        console.log("setAccountConfig working correctly");
    }

    function testSetAccountConfigAccessControl() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        rateLimiting.setAccountConfig(
            user1,
            12 hours,
            750 ether,
            RateLimiting.AccountStatus.OPT_IN
        );

        console.log("Access control on setAccountConfig working correctly");
    }

    function testSetCurrentUsage() public {
        uint256 amount = 500 ether;
        uint256 windowId = 12345;

        vm.prank(owner);
        rateLimiting.setCurrentUsage(user1, amount, windowId);

        (uint256 total, uint256 window) = rateLimiting.currentUsage(user1);
        assertEq(total, amount);
        assertEq(window, windowId);

        console.log("setCurrentUsage working correctly");
    }

    function testSetCurrentUsageAccessControl() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        rateLimiting.setCurrentUsage(user1, 500 ether, 12345);

        console.log("Access control on setCurrentUsage working correctly");
    }

    function testSetAccountToDefault() public {
        // First set custom config
        vm.prank(owner);
        rateLimiting.setAccountConfig(
            user1,
            12 hours,
            500 ether,
            RateLimiting.AccountStatus.OPT_IN
        );

        // Verify it was set
        (uint256 intervalBefore, , ) = rateLimiting.accountConfig(user1);
        assertEq(intervalBefore, 12 hours);

        // Reset to default
        vm.prank(owner);
        rateLimiting.setAccountToDefault(user1);

        // Verify it was deleted
        (
            uint256 intervalAfter,
            uint256 limitAfter,
            RateLimiting.AccountStatus status
        ) = rateLimiting.accountConfig(user1);
        assertEq(intervalAfter, 0);
        assertEq(limitAfter, 0);
        assertEq(uint8(status), uint8(RateLimiting.AccountStatus.DEFAULT));

        console.log("setAccountToDefault working correctly");
    }

    function testSetAccountToDefaultAccessControl() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        rateLimiting.setAccountToDefault(user1);

        console.log("Access control on setAccountToDefault working correctly");
    }

    function testMultipleUsersIndependentRateLimits() public {
        // User1 transfers
        vm.prank(user1);
        token.transfer(user2, 600 ether);

        // User2 transfers
        vm.prank(user2);
        token.transfer(user3, 700 ether);

        // Check independent tracking
        (uint256 total1, ) = rateLimiting.currentUsage(user1);
        (uint256 total2, ) = rateLimiting.currentUsage(user2);

        assertEq(total1, 600 ether);
        assertEq(total2, 700 ether);

        console.log("Multiple users have independent rate limits");
    }

    function testEdgeCaseExactLimit() public {
        // Transfer exactly the limit
        vm.prank(user1);
        token.transfer(user2, DEFAULT_LIMIT);

        (uint256 total, ) = rateLimiting.currentUsage(user1);
        assertEq(total, DEFAULT_LIMIT);

        // Next transfer should fail
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                RateLimiting.RateLimitExceeded.selector,
                user1
            )
        );
        token.transfer(user2, 1);

        console.log("Exact limit edge case working correctly");
    }

    function testWindowIdCalculation() public {
        uint256 currentWindow = block.timestamp / DEFAULT_INTERVAL;

        vm.prank(user1);
        token.transfer(user2, 100 ether);

        (, uint256 windowId) = rateLimiting.currentUsage(user1);
        assertEq(windowId, currentWindow);

        console.log("Window ID calculation working correctly");
    }

    function testOptOutThenOptInFlow() public {
        // Request and activate opt-out
        vm.prank(user1);
        rateLimiting.optOutRequest();
        vm.warp(block.timestamp + DEFAULT_INTERVAL + 1);
        vm.prank(user1);
        rateLimiting.optOutActivate();

        // Verify OPT_OUT status
        (, , RateLimiting.AccountStatus status1) = rateLimiting.accountConfig(
            user1
        );
        assertEq(uint8(status1), uint8(RateLimiting.AccountStatus.OPT_OUT));

        // Now request and activate opt-in
        vm.prank(user1);
        rateLimiting.optInRequest();
        vm.warp(block.timestamp + DEFAULT_INTERVAL + 1);
        vm.prank(user1);
        rateLimiting.optInActivate(6 hours, 300 ether);

        // Verify OPT_IN status
        (, , RateLimiting.AccountStatus status2) = rateLimiting.accountConfig(
            user1
        );
        assertEq(uint8(status2), uint8(RateLimiting.AccountStatus.OPT_IN));

        console.log("Opt-out then opt-in flow working correctly");
    }

    function testAvailableToTransferNoUsage() public view {
        // Fresh account should have full limit available
        uint256 available = rateLimiting.availableToTransfer(user1);
        assertEq(available, DEFAULT_LIMIT);

        console.log("availableToTransfer with no usage working correctly");
    }

    function testAvailableToTransferAfterTransfer() public {
        // Transfer some amount
        vm.prank(user1);
        token.transfer(user2, 400 ether);

        // Should have remaining limit available
        uint256 available = rateLimiting.availableToTransfer(user1);
        assertEq(available, DEFAULT_LIMIT - 400 ether);

        console.log("availableToTransfer after transfer working correctly");
    }

    function testAvailableToTransferExceeded() public {
        // Transfer up to limit
        vm.prank(user1);
        token.transfer(user2, DEFAULT_LIMIT);

        // Should have 0 available
        uint256 available = rateLimiting.availableToTransfer(user1);
        assertEq(available, 0);

        console.log("availableToTransfer when exceeded working correctly");
    }

    function testAvailableToTransferNewWindow() public {
        // Transfer in first window
        vm.prank(user1);
        token.transfer(user2, 600 ether);

        // Move to next window
        vm.warp(block.timestamp + DEFAULT_INTERVAL);

        // Should have full limit available again
        uint256 available = rateLimiting.availableToTransfer(user1);
        assertEq(available, DEFAULT_LIMIT);

        console.log("availableToTransfer in new window working correctly");
    }

    function testAvailableToTransferOptOut() public {
        // Set user to OPT_OUT
        vm.prank(owner);
        rateLimiting.setAccountConfig(
            user1,
            0,
            0,
            RateLimiting.AccountStatus.OPT_OUT
        );

        // Should have unlimited available
        uint256 available = rateLimiting.availableToTransfer(user1);
        assertEq(available, type(uint256).max);

        console.log("availableToTransfer for OPT_OUT working correctly");
    }

    function testAvailableToTransferOptOutOverride() public {
        // Set user to OPT_OUT_OVERRIDE
        vm.prank(owner);
        rateLimiting.setAccountConfig(
            user1,
            0,
            0,
            RateLimiting.AccountStatus.OPT_OUT_OVERRIDE
        );

        // Should have unlimited available
        uint256 available = rateLimiting.availableToTransfer(user1);
        assertEq(available, type(uint256).max);

        console.log(
            "availableToTransfer for OPT_OUT_OVERRIDE working correctly"
        );
    }

    function testAvailableToTransferOptInCustomLimit() public {
        // Set user to OPT_IN with custom limit
        uint256 customLimit = 500 ether;
        vm.prank(owner);
        rateLimiting.setAccountConfig(
            user1,
            12 hours,
            customLimit,
            RateLimiting.AccountStatus.OPT_IN
        );

        // Should have custom limit available
        uint256 available = rateLimiting.availableToTransfer(user1);
        assertEq(available, customLimit);

        console.log(
            "availableToTransfer for OPT_IN with custom limit working correctly"
        );
    }

    function testAvailableToTransferZeroInterval() public {
        // Set interval to zero
        vm.prank(owner);
        rateLimiting.setDefaultConfig(0, 1000 ether);

        // Should return 0
        uint256 available = rateLimiting.availableToTransfer(user1);
        assertEq(available, 0);

        console.log("availableToTransfer with zero interval working correctly");
    }

    function testNextWindowAtNoActiveWindow() public view {
        // Fresh account should return current timestamp
        uint256 nextWindow = rateLimiting.nextWindowAt(user1);
        assertEq(nextWindow, block.timestamp);

        console.log("nextWindowAt with no active window working correctly");
    }

    function testNextWindowAtActiveWindow() public {
        // Transfer to create active window
        vm.prank(user1);
        token.transfer(user2, 100 ether);

        // Should return next window start time
        uint256 currentWindowId = block.timestamp / DEFAULT_INTERVAL;
        uint256 expectedNextWindow = (currentWindowId + 1) * DEFAULT_INTERVAL;
        uint256 nextWindow = rateLimiting.nextWindowAt(user1);
        assertEq(nextWindow, expectedNextWindow);

        console.log("nextWindowAt with active window working correctly");
    }

    function testNextWindowAtAfterWindowExpires() public {
        // Transfer to create active window
        vm.prank(user1);
        token.transfer(user2, 100 ether);

        // Move to next window
        vm.warp(block.timestamp + DEFAULT_INTERVAL);

        // Should return current timestamp (no active window)
        uint256 nextWindow = rateLimiting.nextWindowAt(user1);
        assertEq(nextWindow, block.timestamp);

        console.log("nextWindowAt after window expires working correctly");
    }

    function testNextWindowAtOptInCustomInterval() public {
        // Set user to OPT_IN with custom interval
        uint256 customInterval = 12 hours;
        vm.prank(owner);
        rateLimiting.setAccountConfig(
            user1,
            customInterval,
            500 ether,
            RateLimiting.AccountStatus.OPT_IN
        );

        // Transfer to create active window
        vm.prank(user1);
        token.transfer(user2, 100 ether);

        // Should return next window based on custom interval
        uint256 currentWindowId = block.timestamp / customInterval;
        uint256 expectedNextWindow = (currentWindowId + 1) * customInterval;
        uint256 nextWindow = rateLimiting.nextWindowAt(user1);
        assertEq(nextWindow, expectedNextWindow);

        console.log(
            "nextWindowAt for OPT_IN with custom interval working correctly"
        );
    }

    function testNextWindowAtZeroInterval() public {
        // Set interval to zero
        vm.prank(owner);
        rateLimiting.setDefaultConfig(0, 1000 ether);

        // Should return current timestamp
        uint256 nextWindow = rateLimiting.nextWindowAt(user1);
        assertEq(nextWindow, block.timestamp);

        console.log("nextWindowAt with zero interval working correctly");
    }

    function testSmallWalletOptimization() public {
        address smallUser = address(0x6);

        // Mint a small amount less than the rate limit
        vm.prank(owner);
        token.mint(smallUser, 500 ether); // Less than DEFAULT_LIMIT (1000 ether)

        // Transfer all tokens - should bypass rate limiting since balance <= limit and no active window
        vm.prank(smallUser);
        token.transfer(user2, 500 ether);

        // Verify transfer succeeded
        assertEq(token.balanceOf(smallUser), 0);
        assertEq(token.balanceOf(user2), 10500 ether);

        // Verify no usage was tracked (windowId should still be 0)
        (uint256 cumulative, uint256 windowId) = rateLimiting.currentUsage(
            smallUser
        );
        assertEq(cumulative, 0);
        assertEq(windowId, 0);

        console.log(
            "Small wallet optimization: balance <= rateLimit bypasses rate limiting"
        );
    }

    function testSmallWalletOptimizationActiveWindow() public {
        address smallUser = address(0x7);

        vm.startPrank(owner);
        token.mint(smallUser, 400 ether);
        uint256 currentWindowId = block.timestamp / DEFAULT_INTERVAL;
        rateLimiting.setCurrentUsage(smallUser, 0, currentWindowId);
        vm.stopPrank();

        vm.prank(smallUser);
        token.transfer(user2, 200 ether);

        (uint256 cumulative, uint256 windowId) = rateLimiting.currentUsage(
            smallUser
        );
        assertEq(cumulative, 0);
        assertEq(windowId, currentWindowId);

        console.log(
            "Small wallet optimization: zero usage in active window bypasses rate limiting"
        );
    }

    function testSmallWalletOptimizationNewWindow() public {
        address smallUser = address(0x8);

        vm.warp(block.timestamp + DEFAULT_INTERVAL);

        vm.startPrank(owner);
        token.mint(smallUser, 600 ether);
        uint256 previousWindowId = (block.timestamp / DEFAULT_INTERVAL) - 1;
        rateLimiting.setCurrentUsage(smallUser, 300 ether, previousWindowId);
        vm.stopPrank();

        vm.prank(smallUser);
        token.transfer(user2, 200 ether);

        (uint256 cumulative, uint256 windowId) = rateLimiting.currentUsage(
            smallUser
        );
        assertEq(cumulative, 300 ether);
        assertEq(windowId, previousWindowId);

        console.log(
            "Small wallet optimization: no active window with prior usage bypasses rate limiting"
        );
    }
}
