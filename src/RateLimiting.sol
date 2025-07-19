// SPDX-License-Identifier: AGPL-3.0-only
// Authored by Plastic Digits
pragma solidity ^0.8.30;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title RateLimiting
/// @author Plastic Digits
/// @notice Rate limiting for the CL8Y token.
/// @dev This contract is responsible for the rate limiting of tokens, with opt out.
/// @dev Also includes an optional locking feature, to lock an account for a period of time.
contract RateLimiting is AccessManaged {
    enum AccountStatus {
        DEFAULT, // 0
        OPT_IN, // 1
        OPT_OUT, // 2
        OPT_IN_OVERRIDE, // 3
        OPT_OUT_OVERRIDE // 4

    }

    struct LargeTransferRequest {
        uint256 amount;
        uint256 readyTimestamp;
    }

    struct CurentUsage {
        uint256 transferCumulativeTotal;
        uint256 lastTransferTimestamp;
    }

    struct TokenDefaultConfig {
        uint256 rateLimitInterval;
        uint256 rateLimitTriggerBalance;
        uint256 rateLimit;
        bool isRegistered;
    }

    struct TokenAccountConfig {
        uint256 rateLimitInterval;
        uint256 rateLimitTriggerBalance;
        uint256 rateLimit;
        AccountStatus status;
    }

    mapping(IERC20 token => TokenDefaultConfig config) public tokenDefaultConfig;
    mapping(IERC20 token => mapping(address account => TokenAccountConfig config)) public tokenAccountConfig;
    mapping(IERC20 token => mapping(address account => LargeTransferRequest largeTransferRequest)) public
        largeTransferRequest;
    mapping(IERC20 token => mapping(address account => CurentUsage usage)) public currentUsage;

    mapping(IERC20 token => mapping(address account => uint256 optOutRequestTimestamp)) public optOutRequestTimestamp;
    mapping(IERC20 token => mapping(address account => uint256 optInRequestTimestamp)) public optInRequestTimestamp;

    error RateLimitExceeded(IERC20 token, address account);
    error OverrideActive(IERC20 token, address account);
    error TokenNotRegistered(IERC20 token);
    error OptOutNotRequested(IERC20 token, address account);
    error OptOutNotReady(IERC20 token, address account);
    error OptInNotRequested(IERC20 token, address account);
    error OptInNotReady(IERC20 token, address account);

    constructor(address _initialAuthority) AccessManaged(_initialAuthority) {}

    // Public functions
    function requestLargeTransfer(IERC20 token, uint256 amount) external {
        TokenAccountConfig memory config = tokenAccountConfig[token][msg.sender];
        uint256 delay = 0;
        if (config.status == AccountStatus.OPT_OUT || config.status == AccountStatus.OPT_OUT_OVERRIDE) {
            delay = 0;
        } else if (config.status == AccountStatus.OPT_IN || config.status == AccountStatus.OPT_IN_OVERRIDE) {
            delay = config.rateLimitInterval;
        } else {
            // default to the default config
            delay = tokenDefaultConfig[token].rateLimitInterval;
        }

        largeTransferRequest[token][msg.sender] = LargeTransferRequest(amount, block.timestamp + delay);
    }

    /// @notice Request to opt out of rate limiting, usually takes one day.
    /// @dev This function will set the opt out request timestamp to the current block timestamp.
    /// @dev The opt out request will be activated after the rate limit interval has passed.
    function optOutRequest(IERC20 token) external {
        _revertIfOverride(token, msg.sender);
        optOutRequestTimestamp[token][msg.sender] = block.timestamp;
    }

    /// @notice Activate the opt out request. Must call optOutRequest first.
    /// @dev This function will set the account status to opt out.
    /// @dev The opt out request will be deactivated after the rate limit interval has passed.
    function optOutActivate(IERC20 token) external {
        _revertIfOverride(token, msg.sender);
        uint256 timestamp = optOutRequestTimestamp[token][msg.sender];
        require(timestamp != 0, OptOutNotRequested(token, msg.sender));
        uint256 rateLimitInterval;
        if (tokenAccountConfig[token][msg.sender].status == AccountStatus.OPT_IN) {
            rateLimitInterval = tokenAccountConfig[token][msg.sender].rateLimitInterval;
        } else {
            rateLimitInterval = tokenDefaultConfig[token].rateLimitInterval;
        }
        require(rateLimitInterval + timestamp < block.timestamp, OptOutNotReady(token, msg.sender));
        tokenAccountConfig[token][msg.sender].status = AccountStatus.OPT_OUT;
        optOutRequestTimestamp[token][msg.sender] = 0;
    }

    /// @notice Activate the opt in request. Must call optInRequest first.
    /// @dev This function will set the account status to opt in.
    /// @dev The opt in request will be deactivated after the rate limit interval has passed.
    function optInRequest(IERC20 token) external {
        _revertIfOverride(token, msg.sender);
        optInRequestTimestamp[token][msg.sender] = block.timestamp;
    }

    function optInActivate(IERC20 token, uint256 rateLimitInterval, uint256 rateLimitTriggerBalance, uint256 rateLimit)
        external
    {
        _revertIfOverride(token, msg.sender);
        uint256 timestamp = optInRequestTimestamp[token][msg.sender];
        require(timestamp != 0, OptInNotRequested(token, msg.sender));
        uint256 interval;
        if (tokenAccountConfig[token][msg.sender].status == AccountStatus.OPT_IN) {
            interval = tokenAccountConfig[token][msg.sender].rateLimitInterval;
        } else {
            interval = tokenDefaultConfig[token].rateLimitInterval;
        }
        require(interval + timestamp < block.timestamp, OptInNotReady(token, msg.sender));
        tokenAccountConfig[token][msg.sender] =
            TokenAccountConfig(interval, rateLimitTriggerBalance, rateLimit, AccountStatus.OPT_IN);
    }

    function reset(IERC20 token) external {
        _revertIfOverride(token, msg.sender);
        tokenAccountConfig[token][msg.sender].status = AccountStatus.DEFAULT;
    }

    // token functions
    function updateOnTransfer(address account, uint256 amount) external {
        IERC20 token = IERC20(msg.sender);
        require(tokenDefaultConfig[token].isRegistered, TokenNotRegistered(token));

        // Check if the account is opt out
        TokenAccountConfig memory config = tokenAccountConfig[token][account];
        if (config.status == AccountStatus.OPT_OUT || config.status == AccountStatus.OPT_OUT_OVERRIDE) {
            return;
        }
        // Check if the account is big enough to be rate limited
        uint256 accountBalance = IERC20(token).balanceOf(account);
        if (
            config.status == AccountStatus.OPT_IN
                || config.status == AccountStatus.OPT_IN_OVERRIDE && accountBalance < config.rateLimitTriggerBalance
        ) {
            return;
        }
        TokenDefaultConfig memory defaultConfig = tokenDefaultConfig[token];
        if (config.status == AccountStatus.DEFAULT && accountBalance < defaultConfig.rateLimitTriggerBalance) {
            return;
        }
        CurentUsage storage usage = currentUsage[token][account];

        // Based on the account status, get the rate limit and rate limit interval
        uint256 rateLimit;
        uint256 rateLimitInterval;
        if (config.status == AccountStatus.OPT_IN || config.status == AccountStatus.OPT_IN_OVERRIDE) {
            rateLimit = config.rateLimit;
            rateLimitInterval = config.rateLimitInterval;
        } else {
            rateLimit = defaultConfig.rateLimit;
            rateLimitInterval = defaultConfig.rateLimitInterval;
        }

        // Check if the currentUsage is too old, if so reset it
        if (usage.lastTransferTimestamp + rateLimitInterval < block.timestamp) {
            usage.transferCumulativeTotal = 0;
            usage.lastTransferTimestamp = block.timestamp;
        }

        //TODO: Fix below

        /*

        // For large transfers, first we need to check if the amount would be rate limited without the large transfer.
        // If it would be rate limited, then we need to rate limit if the amount is larger than the transfer request - if so, its rate limited.
        // If the amoutn is smaller than or equal to the transfer request, reset the large transfer request and return.
        LargeTransferRequest storage req = largeTransferRequest[token][account];
        if (
            req.amount > 0 && req.readyTimestamp < block.timestamp && usage.transferCumulativeTotal + amount > rateLimit
        ) {
            if (amount > req.amount) {
                revert RateLimitExceeded(token, account);
            } else {
                req.amount = 0;
                req.readyTimestamp = 0;
                return;
            }
        }

        // Check if the account is rate limited
        if (usage.transferCumulativeTotal + amount > defaultConfig.rateLimit) {
            revert RateLimitExceeded(token, account);
        }
        currentUsage[token][account] = CurentUsage(usage.transferCumulativeTotal + amount, block.timestamp);*/
    }

    // administrative functions
    function setTokenDefaultConfig(
        IERC20 token,
        uint256 rateLimitInterval,
        uint256 rateLimitTriggerBalance,
        uint256 rateLimit,
        bool isRegistered
    ) external restricted {
        tokenDefaultConfig[token] =
            TokenDefaultConfig(rateLimitInterval, rateLimitTriggerBalance, rateLimit, isRegistered);
    }

    function setTokenAccountConfig(
        IERC20 token,
        address account,
        uint256 rateLimitInterval,
        uint256 rateLimitTriggerBalance,
        uint256 rateLimit,
        AccountStatus status
    ) external restricted {
        tokenAccountConfig[token][account] =
            TokenAccountConfig(rateLimitInterval, rateLimitTriggerBalance, rateLimit, status);
    }

    function setLargeTransferRequest(IERC20 token, address account, uint256 amount) external restricted {
        largeTransferRequest[token][account] = LargeTransferRequest(amount, block.timestamp);
    }

    function setCurrentUsage(IERC20 token, address account, uint256 amount) external restricted {
        currentUsage[token][account] = CurentUsage(amount, block.timestamp);
    }

    function setAccountToDefault(IERC20 token, address account) external restricted {
        tokenAccountConfig[token][account].status = AccountStatus.DEFAULT;
    }

    // Revert internal functions
    function _revertIfOverride(IERC20 token, address account) internal view {
        if (
            tokenAccountConfig[token][account].status == AccountStatus.OPT_IN_OVERRIDE
                || tokenAccountConfig[token][account].status == AccountStatus.OPT_OUT_OVERRIDE
        ) revert OverrideActive(token, account);
    }
}
