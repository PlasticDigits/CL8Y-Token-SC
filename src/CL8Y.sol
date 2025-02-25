// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IAmmFactory.sol";
/*

╔═════════════════════════════════════════════════════════════════╗
║─────────────────────────────────────────────────────────────────║
║─██████████████─██████─────────██████████████─████████──████████─║
║─██░░░░░░░░░░██─██░░██─────────██░░░░░░░░░░██─██░░░░██──██░░░░██─║
║─██░░██████████─██░░██─────────██░░██████░░██─████░░██──██░░████─║
║─██░░██─────────██░░██─────────██░░██──██░░██───██░░░░██░░░░██───║
║─██░░██─────────██░░██─────────██░░██████░░██───████░░░░░░████───║
║─██░░██─────────██░░██─────────██░░░░░░░░░░██─────████░░████─────║
║─██░░██─────────██░░██─────────██░░██████░░██───────██░░██───────║
║─██░░██─────────██░░██─────────██░░██──██░░██───────██░░██───────║
║─██░░██████████─██░░██████████─██░░██████░░██───────██░░██───────║
║─██░░░░░░░░░░██─██░░░░░░░░░░██─██░░░░░░░░░░██───────██░░██───────║
║─██████████████─██████████████─██████████████───────██████───────║
║─────────────────────────────────────────────────────────────────║
║─────────────────────𝕔𝕖𝕣𝕒𝕞𝕚𝕔𝕝𝕚𝕓𝕖𝕣𝕥𝕪.𝕔𝕠𝕞──────────────────────────║
╚═════════════════════════════════════════════════════════════════╝

As Presented By:
ｐｌａｓｔｉｃ ｄｉｇｉｔｓ


*/

/// @title CL8Y Token Contract
/// @notice Implementation of the CeramicLiberty.com token with tax and max balance mechanics
/// @dev Extends ERC20 with burning capability, permit functionality, and ownership controls
/// @dev Implements anti-snipe protection for the first 5 seconds of trading
/// @dev Trading cannot be closed once opened
/// @dev Sell burn tax cannot be increased once reduced
/// @dev Max wallet balance cannot be decreased once set
contract CL8Y is ERC20, ERC20Burnable, ERC20Permit, Ownable {
    using SafeERC20 for IERC20;

    uint256 public maxBalance = 1_000 ether;
    uint256 public sellTaxBasis = 3_000; // 30.00%

    uint256 public constant ANTI_SNIPE_BURN = 5_000; // 50.00% for anti-snipe
    uint256 public constant ANTI_SNIPE_DURATION = 5 seconds; // first 5 seconds of trading

    address public immutable basePairV2;
    uint256 public tradingOpenTime;

    error OverMax(uint256 amount, uint256 max);
    error UnderMin(uint256 amount, uint256 max);
    error TradingNotOpen();
    error TradingAlreadyOpen();
    event MaxBalanceUpdated(uint256 oldMaxBalance, uint256 newMaxBalance);
    event SellTaxBasisUpdated(uint256 oldSellTaxBasis, uint256 newSellTaxBasis);

    /// @notice Initializes the token contract with trading parameters
    /// @param _factory The AMM factory contract interface
    /// @param _baseLiquidityToken The token to create the initial liquidity pair with
    /// @param _tradingOpenTime The timestamp when trading becomes enabled
    constructor(
        IAmmFactory _factory,
        IERC20 _baseLiquidityToken,
        uint256 _tradingOpenTime
    )
        ERC20("CeramicLiberty.com", "CL8Y")
        ERC20Permit("CeramicLiberty.com")
        Ownable(msg.sender)
    {
        tradingOpenTime = _tradingOpenTime;

        basePairV2 = _factory.createPair(
            address(this),
            address(_baseLiquidityToken)
        );

        _mint(owner(), 3_000_000 ether);
    }

    /// @notice Internal function to handle token transfers with tax and balance checks
    /// @dev Overrides ERC20's _update to implement sell tax and max balance restrictions
    /// @param from The sender's address
    /// @param to The recipient's address
    /// @param value The amount of tokens to transfer
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        bool isOwner = from == owner() || to == owner();
        if (
            to != basePairV2 || //not a sell
            value == 0 ||
            isOwner
        ) {
            // If trading is not open, and the sender is not the owner, revert.
            if (!tradingOpen() && (!isOwner)) {
                revert TradingNotOpen();
            }
            // If trading open for 5 seconds or less, charge the anti-snipe burn on buys
            if (
                from == basePairV2 && // is a buy
                tradingOpen() && // trading is open
                block.timestamp - tradingOpenTime <= ANTI_SNIPE_DURATION // trading open for 5 seconds or less
            ) {
                uint256 tax = (value * ANTI_SNIPE_BURN) / 10_000;
                super._update(from, to, value);
                super._burn(to, tax);
            } else {
                //Default behavior for mints, burns, exempt, transfers
                super._update(from, to, value);
            }
        } else {
            //sell
            uint256 tax = (value * sellTaxBasis) / 10_000;
            super._update(from, to, value - tax);
            super._burn(from, tax);
        }

        if (from != owner()) {
            _revertIfStandardWalletAndOverMaxHolding(to);
        }
    }

    /// @notice Checks if trading is currently open
    /// @return bool Returns true if current timestamp is greater than or equal to tradingOpenTime
    function tradingOpen() public view returns (bool) {
        return (block.timestamp >= tradingOpenTime);
    }

    /// @notice Increases the maximum wallet holding limit to 10,000 tokens
    /// @dev Can only be called by the owner and only if current maxBalance is less than 10,000
    function ownerSetMaxWalletTo10k() external onlyOwner {
        // Can only increase maxBalance.
        if (maxBalance >= 10_000 ether) {
            revert OverMax(maxBalance, 10_000 ether);
        }
        uint256 oldMaxBalance = maxBalance;
        maxBalance = 10_000 ether;
        emit MaxBalanceUpdated(oldMaxBalance, maxBalance);
    }

    /// @notice Removes the maximum wallet holding limit
    /// @dev Can only be called by the owner, sets maxBalance to maximum uint256 value
    function ownerSetMaxWalletToMax() external onlyOwner {
        uint256 oldMaxBalance = maxBalance;
        maxBalance = type(uint256).max;
        emit MaxBalanceUpdated(oldMaxBalance, maxBalance);
    }

    /// @notice Reduces the sell tax to 10% (1000 basis points)
    /// @dev Can only be called by the owner and only if current tax is above 10%
    function ownerSetBurnTo1000Bps() external onlyOwner {
        // Can only decrease sellTaxBasis.
        if (sellTaxBasis <= 1_000) {
            revert UnderMin(sellTaxBasis, 1_000);
        }
        uint256 oldSellTaxBasis = sellTaxBasis;
        sellTaxBasis = 1_000;
        emit SellTaxBasisUpdated(oldSellTaxBasis, sellTaxBasis);
    }

    /// @notice Reduces the sell tax to 1% (100 basis points)
    /// @dev Can only be called by the owner and only if current tax is above 1%
    function ownerSetBurnTo100Bps() external onlyOwner {
        // Can only decrease sellTaxBasis.
        if (sellTaxBasis <= 100) {
            revert UnderMin(sellTaxBasis, 100);
        }
        uint256 oldSellTaxBasis = sellTaxBasis;
        sellTaxBasis = 100;
        emit SellTaxBasisUpdated(oldSellTaxBasis, sellTaxBasis);
    }

    /// @notice Reduces the sell tax to 0.25% (25 basis points)
    /// @dev Can only be called by the owner and only if current tax is above 0.25%
    function ownerSetBurnTo25Bps() external onlyOwner {
        // Can only decrease sellTaxBasis.
        if (sellTaxBasis <= 25) {
            revert UnderMin(sellTaxBasis, 25);
        }
        uint256 oldSellTaxBasis = sellTaxBasis;
        sellTaxBasis = 25;
        emit SellTaxBasisUpdated(oldSellTaxBasis, sellTaxBasis);
    }

    /// @notice Allows the owner to rescue any ERC20 tokens accidentally sent to the contract
    /// @dev Can only be called by the owner
    /// @param _token The ERC20 token contract to rescue
    function ownerRescueTokens(IERC20 _token) external onlyOwner {
        _token.transfer(msg.sender, _token.balanceOf(address(this)));
    }

    /// @notice Allows the owner to set the trading open time
    /// @dev Can be used to instantly open trading, or set a future time
    /// @dev Cannot be used to close trading
    /// @dev Can only be called by the owner
    /// @param to The timestamp when trading becomes enabled
    function ownerSetTradingOpenTime(uint256 to) external onlyOwner {
        // Can only set the trading open time if its not currently open.
        if (tradingOpen()) {
            revert TradingAlreadyOpen();
        }
        tradingOpenTime = to;
    }

    /// @notice Internal function to check if a wallet exceeds maximum holding limit
    /// @dev Reverts if the wallet is not exempt and balance exceeds maxBalance
    /// @param wallet The address to check the balance for
    function _revertIfStandardWalletAndOverMaxHolding(
        address wallet
    ) internal view {
        if (
            wallet != basePairV2 &&
            wallet != owner() &&
            balanceOf(wallet) > maxBalance
        ) {
            revert OverMax(balanceOf(wallet), maxBalance);
        }
    }
}
