// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBlacklist} from "./interfaces/IBlacklist.sol";
import {IGuardExecutor} from "./interfaces/IGuardExecutor.sol";

contract AssetRecovery is AccessManaged {
    using SafeERC20 for IERC20;

    struct WalletRecord {
        uint256 totalReceived;
        uint256 totalReleased;
        uint256 totalRecovered;
    }

    IERC20 public immutable token;
    IGuardExecutor public immutable guard;
    IBlacklist public immutable blacklist;

    mapping(address wallet => WalletRecord record) private _records;

    event Seized(address indexed wallet, uint256 amount);
    event Released(address indexed wallet, uint256 amount);
    event Recovered(
        address indexed wallet,
        address indexed recipient,
        uint256 amount
    );

    error ZeroAddress();
    error ZeroAmount();
    error TransferFailed();
    error AmountExceedsHoldings(uint256 requested, uint256 available);
    error WalletNotBlacklisted(address wallet);

    constructor(
        address initialAuthority,
        IGuardExecutor guard_,
        IERC20 token_,
        IBlacklist blacklist_
    ) AccessManaged(initialAuthority) {
        if (
            address(guard_) == address(0) ||
            address(token_) == address(0) ||
            address(blacklist_) == address(0)
        ) {
            revert ZeroAddress();
        }
        guard = guard_;
        token = token_;
        blacklist = blacklist_;
    }

    function seize(
        address maliciousWallet,
        uint256 amount
    ) external restricted {
        _seize(maliciousWallet, amount);
    }

    function seizeAll(address maliciousWallet) external restricted {
        uint256 balance = token.balanceOf(maliciousWallet);
        _seize(maliciousWallet, balance);
    }

    function release(
        address maliciousWallet,
        uint256 amount
    ) external restricted {
        WalletRecord storage walletRecord = _deduct(maliciousWallet, amount);
        walletRecord.totalReleased += amount;
        token.safeTransfer(maliciousWallet, amount);

        emit Released(maliciousWallet, amount);
    }

    function recover(
        address maliciousWallet,
        address recipient,
        uint256 amount
    ) external restricted {
        if (recipient == address(0)) revert ZeroAddress();

        WalletRecord storage walletRecord = _deduct(maliciousWallet, amount);
        walletRecord.totalRecovered += amount;
        token.safeTransfer(recipient, amount);

        emit Recovered(maliciousWallet, recipient, amount);
    }

    function holdings(address wallet) external view returns (uint256) {
        WalletRecord memory walletRecord = _records[wallet];
        uint256 available = walletRecord.totalReceived;
        available -= walletRecord.totalReleased;
        available -= walletRecord.totalRecovered;
        return available;
    }

    function record(
        address wallet
    ) external view returns (WalletRecord memory) {
        return _records[wallet];
    }

    function _deduct(
        address wallet,
        uint256 amount
    ) private view returns (WalletRecord storage walletRecord) {
        if (wallet == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        walletRecord = _records[wallet];

        uint256 available = walletRecord.totalReceived;
        available -= walletRecord.totalReleased;
        available -= walletRecord.totalRecovered;

        if (available < amount) {
            revert AmountExceedsHoldings(amount, available);
        }
    }

    function _seize(address maliciousWallet, uint256 amount) internal {
        if (maliciousWallet == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (!blacklist.isBlacklisted(maliciousWallet)) {
            revert WalletNotBlacklisted(maliciousWallet);
        }

        uint256 balanceBefore = token.balanceOf(address(this));

        bytes memory result = guard.execute(
            address(token),
            abi.encodeCall(
                IERC20.transferFrom,
                (maliciousWallet, address(this), amount)
            )
        );

        if (result.length != 0 && !abi.decode(result, (bool))) {
            revert TransferFailed();
        }

        uint256 balanceAfter = token.balanceOf(address(this));
        if (balanceAfter != balanceBefore + amount) {
            revert TransferFailed();
        }

        WalletRecord storage walletRecord = _records[maliciousWallet];
        walletRecord.totalReceived += amount;

        emit Seized(maliciousWallet, amount);
    }
}
