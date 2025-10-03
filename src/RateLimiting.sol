// SPDX-License-Identifier: AGPL-3.0-only
// Authored by Plastic Digits
pragma solidity ^0.8.30;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGuardERC20} from "./interfaces/IGuardERC20.sol";

/// @title RateLimiting
/// @author Plastic Digits
/// @notice Rate limiting for tokens with opt-in/opt-out support and admin overrides.
/// @dev This contract enforces configurable rate limits with opt-in/opt-out support and admin overrides.
/// @dev Solidity introduced custom require errors in 0.8.26 (legacy pipeline in 0.8.27), so we use them here.
contract RateLimiting is AccessManaged, IGuardERC20 {
    enum AccountStatus {
        DEFAULT,
        OPT_IN,
        OPT_OUT,
        OPT_IN_OVERRIDE,
        OPT_OUT_OVERRIDE
    }

    struct DefaultConfig {
        uint256 rateLimitInterval;
        uint256 rateLimit;
    }

    struct AccountConfig {
        uint256 rateLimitInterval;
        uint256 rateLimit;
        AccountStatus status;
    }

    struct CurrentUsage {
        uint256 transferCumulativeTotal;
        uint256 windowId;
    }

    IERC20 public immutable cl8y;
    DefaultConfig public defaultConfig;

    mapping(address account => AccountConfig config) public accountConfig;
    mapping(address account => CurrentUsage usage) public currentUsage;
    mapping(address account => uint256 timestamp) public optOutRequestTimestamp;
    mapping(address account => uint256 timestamp) public optInRequestTimestamp;

    error InvalidSender(address sender);
    error RateLimitExceeded(address account);
    error OverrideActive(address account);
    error OptOutNotRequested(address account);
    error OptOutNotReady(address account);
    error OptInNotRequested(address account);
    error OptInNotReady(address account);

    constructor(address initialAuthority, IERC20 token, uint256 rateLimitInterval, uint256 rateLimit)
        AccessManaged(initialAuthority)
    {
        cl8y = token;
        defaultConfig = DefaultConfig(rateLimitInterval, rateLimit);
    }

    /// @notice Request to opt out of rate limiting, usually takes one day.
    function optOutRequest() external {
        _revertIfOverride(msg.sender);
        optOutRequestTimestamp[msg.sender] = block.timestamp;
    }

    /// @notice Activate the opt out request. Must call optOutRequest first.
    function optOutActivate() external {
        _revertIfOverride(msg.sender);

        uint256 timestamp = optOutRequestTimestamp[msg.sender];
        if (timestamp == 0) revert OptOutNotRequested(msg.sender);

        uint256 interval = defaultConfig.rateLimitInterval;
        AccountStatus status = accountConfig[msg.sender].status;
        if (status == AccountStatus.OPT_IN) {
            interval = accountConfig[msg.sender].rateLimitInterval;
        }

        if (timestamp + interval >= block.timestamp) {
            revert OptOutNotReady(msg.sender);
        }

        accountConfig[msg.sender].status = AccountStatus.OPT_OUT;
        optOutRequestTimestamp[msg.sender] = 0;
    }

    /// @notice Submit an opt-in request to use customised rate limiting settings.
    function optInRequest() external {
        _revertIfOverride(msg.sender);
        optInRequestTimestamp[msg.sender] = block.timestamp;
    }

    /// @notice Activate the opt-in request with custom limits.
    function optInActivate(uint256 rateLimitInterval, uint256 rateLimit) external {
        _revertIfOverride(msg.sender);

        uint256 timestamp = optInRequestTimestamp[msg.sender];
        if (timestamp == 0) revert OptInNotRequested(msg.sender);

        uint256 interval = defaultConfig.rateLimitInterval;
        if (accountConfig[msg.sender].status == AccountStatus.OPT_IN) {
            interval = accountConfig[msg.sender].rateLimitInterval;
        }

        if (timestamp + interval >= block.timestamp) {
            revert OptInNotReady(msg.sender);
        }

        accountConfig[msg.sender] = AccountConfig(rateLimitInterval, rateLimit, AccountStatus.OPT_IN);
        optInRequestTimestamp[msg.sender] = 0;
    }

    /// @notice Guard hook executed by `cl8y` before processing a transfer.
    function check(address sender, address, uint256 amount) external {
        if (msg.sender != address(cl8y)) revert InvalidSender(msg.sender);

        AccountConfig memory config = accountConfig[sender];
        AccountStatus status = config.status;

        if (status == AccountStatus.OPT_OUT || status == AccountStatus.OPT_OUT_OVERRIDE) {
            return;
        }

        uint256 rateLimitInterval = defaultConfig.rateLimitInterval;
        uint256 rateLimit = defaultConfig.rateLimit;

        if (status == AccountStatus.OPT_IN || status == AccountStatus.OPT_IN_OVERRIDE) {
            rateLimitInterval = config.rateLimitInterval;
            rateLimit = config.rateLimit;
        }

        if (rateLimitInterval == 0) revert RateLimitIntervalZero();

        CurrentUsage storage usage = currentUsage[sender];

        uint256 currentWindowId = block.timestamp / rateLimitInterval;
        uint256 balance = cl8y.balanceOf(sender);

        // Optimization: if no active window and balance <= rate limit, skip rate limiting
        // Small wallets can sell all without triggering rate limit
        // Prevents high volume wallets with low balances from triggering rate limit
        if (usage.windowId != currentWindowId) {
            if (balance <= rateLimit) {
                usage.transferCumulativeTotal = 0;
                usage.windowId = 0;
                return;
            }
        } else if (usage.transferCumulativeTotal == 0 && balance <= rateLimit) {
            return;
        }

        uint256 newTotal = usage.transferCumulativeTotal + amount;
        if (newTotal > rateLimit) revert RateLimitExceeded(sender);

        usage.transferCumulativeTotal = newTotal;
        usage.windowId = currentWindowId;
    }

    // administrative functions
    function setDefaultConfig(uint256 rateLimitInterval, uint256 rateLimit) external restricted {
        defaultConfig = DefaultConfig(rateLimitInterval, rateLimit);
    }

    function setAccountConfig(address account, uint256 rateLimitInterval, uint256 rateLimit, AccountStatus status)
        external
        restricted
    {
        accountConfig[account] = AccountConfig(rateLimitInterval, rateLimit, status);
    }

    function setCurrentUsage(address account, uint256 amount, uint256 windowId) external restricted {
        currentUsage[account] = CurrentUsage(amount, windowId);
    }

    function setAccountToDefault(address account) external restricted {
        delete accountConfig[account];
    }

    // View functions
    /// @notice Get the amount available to transfer in the current window for an account
    /// @param account The account to check
    /// @return The amount available to transfer (type(uint256).max if opted out)
    function availableToTransfer(address account) external view returns (uint256) {
        AccountConfig memory config = accountConfig[account];
        AccountStatus status = config.status;

        // If opted out, no limit
        if (status == AccountStatus.OPT_OUT || status == AccountStatus.OPT_OUT_OVERRIDE) {
            return type(uint256).max;
        }

        uint256 rateLimitInterval = defaultConfig.rateLimitInterval;
        uint256 rateLimit = defaultConfig.rateLimit;

        if (status == AccountStatus.OPT_IN || status == AccountStatus.OPT_IN_OVERRIDE) {
            rateLimitInterval = config.rateLimitInterval;
            rateLimit = config.rateLimit;
        }

        if (rateLimitInterval == 0) return 0;

        CurrentUsage storage usage = currentUsage[account];
        uint256 currentWindowId = block.timestamp / rateLimitInterval;

        // If different window or no usage yet, full limit is available
        if (usage.windowId != currentWindowId) {
            return rateLimit;
        }

        // Return remaining limit in current window
        if (usage.transferCumulativeTotal >= rateLimit) {
            return 0;
        }
        return rateLimit - usage.transferCumulativeTotal;
    }

    /// @notice Get the timestamp when the next window starts for an account
    /// @param account The account to check
    /// @return The timestamp when the next window starts, or current timestamp if no active window
    function nextWindowAt(address account) external view returns (uint256) {
        AccountConfig memory config = accountConfig[account];
        AccountStatus status = config.status;

        uint256 rateLimitInterval = defaultConfig.rateLimitInterval;

        if (status == AccountStatus.OPT_IN || status == AccountStatus.OPT_IN_OVERRIDE) {
            rateLimitInterval = config.rateLimitInterval;
        }

        if (rateLimitInterval == 0) return block.timestamp;

        CurrentUsage storage usage = currentUsage[account];
        uint256 currentWindowId = block.timestamp / rateLimitInterval;

        // If different window or no usage yet, return current timestamp
        if (usage.windowId != currentWindowId || usage.transferCumulativeTotal == 0) {
            return block.timestamp;
        }

        // Return when next window starts
        return (usage.windowId + 1) * rateLimitInterval;
    }

    // Internal helpers
    function _revertIfOverride(address account) internal view {
        AccountStatus status = accountConfig[account].status;
        if (status == AccountStatus.OPT_IN_OVERRIDE || status == AccountStatus.OPT_OUT_OVERRIDE) {
            revert OverrideActive(account);
        }
    }

    error RateLimitIntervalZero();
}
