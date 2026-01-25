// SPDX-License-Identifier: AGPL-3.0-only
// Authored by Plastic Digits
pragma solidity ^0.8.30;

import {IGuardERC20} from "./interfaces/IGuardERC20.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {DatastoreSetAddress, DatastoreSetIdAddress} from "./DatastoreSetAddress.sol";

/// @title RiskFlagAuto
/// @author Plastic Digits
/// @notice Automatically risk-flags accounts receiving from high-risk accounts (exchanges) when volume thresholds are exceeded.
/// @dev High-risk accounts are monitored for suspicious outflows. When a 24-hour window exceeds the volume threshold,
/// the window becomes "flagged" and all subsequent recipients in that window are risk-flagged.
/// Risk-flagged accounts cannot send tokens until manually reviewed and unflagged by an administrator.
contract RiskFlagAuto is IGuardERC20, AccessManaged {
    /// @notice External datastore for managing address sets
    DatastoreSetAddress public immutable datastore;

    /// @notice Set ID for high-risk accounts (such as exchanges that cannot be blacklisted but are monitored)
    DatastoreSetIdAddress public constant SET_HIGH_RISK =
        DatastoreSetIdAddress.wrap(keccak256("RiskFlagAuto.HIGH_RISK"));

    /// @notice Set ID for whitelisted accounts (known good actors exempt from risk flagging)
    DatastoreSetIdAddress public constant SET_WHITELISTED =
        DatastoreSetIdAddress.wrap(keccak256("RiskFlagAuto.WHITELISTED"));

    /// @notice Set ID for risk-flagged accounts (accounts that need manual review, cannot send)
    DatastoreSetIdAddress public constant SET_RISK_FLAGGED =
        DatastoreSetIdAddress.wrap(keccak256("RiskFlagAuto.RISK_FLAGGED"));

    /// @notice Volume threshold per high-risk account per 24-hour window (default 250 CL8Y)
    uint256 public volumeThreshold = 250 ether;

    /// @notice Duration of a time window in seconds (24 hours)
    uint256 public constant WINDOW_DURATION = 86400;

    /// @notice Tracks cumulative volume per high-risk account per window
    mapping(address highRiskAccount => mapping(uint256 windowId => uint256 volume)) public windowVolume;

    /// @notice Tracks whether a window is flagged for a high-risk account
    mapping(address highRiskAccount => mapping(uint256 windowId => bool flagged)) public isWindowFlagged;

    /// @notice Emitted when an account is automatically risk-flagged
    event AccountRiskFlagged(address indexed account, address indexed fromHighRisk, uint256 windowId);

    /// @notice Emitted when a window becomes flagged due to exceeding volume threshold
    event WindowFlagged(address indexed highRiskAccount, uint256 indexed windowId, uint256 volume);

    /// @notice Emitted when a window is manually unflagged by admin
    event WindowUnflagged(address indexed highRiskAccount, uint256 indexed windowId);

    /// @notice Emitted when volume threshold is updated
    event VolumeThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    error RiskFlagged(address account);

    constructor(
        address initialAuthority,
        DatastoreSetAddress datastoreSetAddress
    ) AccessManaged(initialAuthority) {
        datastore = datastoreSetAddress;
    }

    /// @notice Guard hook executed before processing a transfer
    /// @param sender The account sending tokens
    /// @param recipient The account receiving tokens
    /// @param amount The amount of tokens being transferred
    function check(address sender, address recipient, uint256 amount) external {
        // Skip mint/burn operations
        if (sender == address(0) || recipient == address(0)) {
            return;
        }

        bool senderIsHighRisk = datastore.contains(address(this), SET_HIGH_RISK, sender);

        // Risk-flagged accounts that are NOT high-risk cannot send (frozen until manual review)
        // Check this BEFORE the high-risk early return to prevent flagged attackers from transferring
        if (!senderIsHighRisk) {
            if (datastore.contains(address(this), SET_RISK_FLAGGED, sender)) {
                revert RiskFlagged(sender);
            }
            // Not high-risk and not risk-flagged: normal account, nothing to track
            return;
        }

        // From here: sender IS high-risk (exchange account)

        // Whitelisted recipients are exempt from risk flagging
        if (datastore.contains(address(this), SET_WHITELISTED, recipient)) {
            return;
        }

        uint256 windowId = block.timestamp / WINDOW_DURATION;

        // If window is already flagged, immediately flag the recipient and skip volume tracking
        if (isWindowFlagged[sender][windowId]) {
            _flagAccount(recipient, sender, windowId);
            return;
        }

        // Increment volume for this high-risk account in current window
        uint256 newVolume = windowVolume[sender][windowId] + amount;
        windowVolume[sender][windowId] = newVolume;

        // If volume exceeds threshold, flag the recipient and the window
        if (newVolume > volumeThreshold) {
            _flagAccount(recipient, sender, windowId);
            _flagWindow(sender, windowId);
        }
    }

    // ============ Admin Functions ============

    /// @notice Set the volume threshold for triggering risk flags
    /// @param newThreshold The new threshold in token units (18 decimals)
    function setVolumeThreshold(uint256 newThreshold) external restricted {
        uint256 oldThreshold = volumeThreshold;
        volumeThreshold = newThreshold;
        emit VolumeThresholdUpdated(oldThreshold, newThreshold);
    }

    /// @notice Add accounts to the high-risk set (exchanges)
    /// @param accounts Array of addresses to add
    function addHighRiskAccounts(address[] calldata accounts) external restricted {
        datastore.addBatch(SET_HIGH_RISK, accounts);
    }

    /// @notice Remove accounts from the high-risk set
    /// @param accounts Array of addresses to remove
    function removeHighRiskAccounts(address[] calldata accounts) external restricted {
        datastore.removeBatch(SET_HIGH_RISK, accounts);
    }

    /// @notice Add accounts to the whitelist (known good actors)
    /// @param accounts Array of addresses to add
    function addWhitelistedAccounts(address[] calldata accounts) external restricted {
        datastore.addBatch(SET_WHITELISTED, accounts);
    }

    /// @notice Remove accounts from the whitelist
    /// @param accounts Array of addresses to remove
    function removeWhitelistedAccounts(address[] calldata accounts) external restricted {
        datastore.removeBatch(SET_WHITELISTED, accounts);
    }

    /// @notice Remove accounts from the risk-flagged set after manual review
    /// @param accounts Array of addresses to unflag
    function removeRiskFlaggedAccounts(address[] calldata accounts) external restricted {
        datastore.removeBatch(SET_RISK_FLAGGED, accounts);
    }

    /// @notice Manually flag or unflag a window for a high-risk account
    /// @param highRiskAccount The high-risk account
    /// @param windowId The window ID to flag/unflag
    function setWindowFlagged(
        address highRiskAccount,
        uint256 windowId,
        bool flagged
    ) external restricted {
        if (flagged) {
            _flagWindow(highRiskAccount, windowId);
        } else {
            isWindowFlagged[highRiskAccount][windowId] = false;
            emit WindowUnflagged(highRiskAccount, windowId);
        }
    }

    /// @notice Manually set window volume (for corrections)
    /// @param highRiskAccount The high-risk account
    /// @param windowId The window ID
    /// @param volume The volume to set
    function setWindowVolume(
        address highRiskAccount,
        uint256 windowId,
        uint256 volume
    ) external restricted {
        windowVolume[highRiskAccount][windowId] = volume;
    }

    // ============ View Functions ============

    /// @notice Check if an account is high-risk
    function isHighRisk(address account) external view returns (bool) {
        return datastore.contains(address(this), SET_HIGH_RISK, account);
    }

    /// @notice Check if an account is whitelisted
    function isWhitelisted(address account) external view returns (bool) {
        return datastore.contains(address(this), SET_WHITELISTED, account);
    }

    /// @notice Check if an account is risk-flagged
    function isRiskFlagged(address account) external view returns (bool) {
        return datastore.contains(address(this), SET_RISK_FLAGGED, account);
    }

    /// @notice Get the current window ID
    function currentWindowId() external view returns (uint256) {
        return block.timestamp / WINDOW_DURATION;
    }

    /// @notice Get volume for a high-risk account in a specific window
    function getWindowVolume(
        address highRiskAccount,
        uint256 windowId
    ) external view returns (uint256) {
        return windowVolume[highRiskAccount][windowId];
    }

    /// @notice Get volume for a high-risk account in the current window
    function getCurrentWindowVolume(address highRiskAccount) external view returns (uint256) {
        return windowVolume[highRiskAccount][block.timestamp / WINDOW_DURATION];
    }

    /// @notice Get remaining volume before threshold is exceeded for current window
    function getRemainingVolume(address highRiskAccount) external view returns (uint256) {
        uint256 windowId = block.timestamp / WINDOW_DURATION;
        uint256 currentVolume = windowVolume[highRiskAccount][windowId];
        if (currentVolume >= volumeThreshold) {
            return 0;
        }
        return volumeThreshold - currentVolume;
    }

    // ============ Internal Functions ============

    /// @dev Flags an account
    function _flagAccount(
        address account,
        address fromHighRisk,
        uint256 windowId
    ) internal {
        datastore.add(SET_RISK_FLAGGED, account);
        emit AccountRiskFlagged(account, fromHighRisk, windowId);
    }

    /// @dev Flags a window
    function _flagWindow(
        address highRiskAccount,
        uint256 windowId
    ) internal {
        isWindowFlagged[highRiskAccount][windowId] = true;
        emit WindowFlagged(highRiskAccount, windowId, windowVolume[highRiskAccount][windowId]);
    }
}
