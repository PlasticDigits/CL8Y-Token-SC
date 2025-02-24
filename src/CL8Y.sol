// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IAmmFactory.sol";
import "./interfaces/IAmmRouter02.sol";
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


*/ contract CL8Y is
    ERC20,
    ERC20Burnable,
    ERC20Permit,
    Ownable
{
    mapping(address account => bool isExempt) public isExempt;

    uint256 maxBalance = 1_000 ether;
    uint256 sellTaxBasis = 3_000; // 30.00%

    address immutable basePairV2;
    uint256 immutable tradingOpenTime;

    error OverMax(uint256 amount, uint256 max);
    error UnderMin(uint256 amount, uint256 max);
    error TradingNotOpen();

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

        isExempt[address(bstrTaxMan)] = true;
        isExempt[address(bstrTaxMan.taxWalletSecondary())] = true;
        isExempt[owner()] = true;
        isExempt[msg.sender] = true;

        basePairV2 = _factory.createPair(address(this), _baseLiquidityToken);

        _mint(owner(), 3_000_000 ether);
        maxBalance = totalSupply() / 100;
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        if (
            to != basePairV2 || //not a sell
            value == 0 ||
            isExempt[from] ||
            isExempt[to]
        ) {
            if (!tradingOpen() && (!isExempt[from] || !isExempt[to])) {
                revert TradingNotOpen();
            }
            //Default behavior for mints, burns, exempt, transfers
            super._update(from, to, value);
        } else {
            //sell
            uint256 tax = (value * sellTaxBasis) / 10_000;
            super._update(from, address(bstrTaxMan), tax);
            super._update(from, to, value - tax);
        }

        _revertIfStandardWalletAndOverMaxHolding(from);
        _revertIfStandardWalletAndOverMaxHolding(to);
    }

    function tradingOpen() public view returns (bool) {
        return (block.timestamp >= tradingOpenTime);
    }

    function OWNER_setMaxWalletTo10k() external onlyOwner {
        // Can only increase maxBalance.
        if (maxBalance >= 10_000 ether) {
            revert OverMax(maxBalance, 10_000 ether);
        }
        maxBalance = 10_000 ether;
    }

    function OWNER_setMaxWalletToMax() external onlyOwner {
        maxBalance = type(uint256).max;
    }

    function OWNER_setBurnTo1_000BPS() external onlyOwner {
        // Can only decrease sellTaxBasis.
        if (sellTaxBasis <= 1_000) {
            revert UnderMin(sellTaxBasis, 1_000);
        }
        sellTaxBasis = 1_000;
    }

    function OWNER_setBurnTo100BPS() external onlyOwner {
        // Can only decrease sellTaxBasis.
        if (sellTaxBasis <= 100) {
            revert UnderMin(sellTaxBasis, 100);
        }
        sellTaxBasis = 100;
    }

    function OWNER_setBurnTo25BPS() external onlyOwner {
        // Can only decrease sellTaxBasis.
        if (sellTaxBasis <= 25) {
            revert UnderMin(sellTaxBasis, 25);
        }
        sellTaxBasis = 25;
    }

    function OWNER_rescueTokens(IERC20 _token) external onlyOwner {
        _token.transfer(msg.sender, _token.balanceOf(address(this)));
    }

    function _revertIfStandardWalletAndOverMaxHolding(
        address wallet
    ) internal view {
        if (
            wallet != basePairV2 &&
            !isExempt[wallet] &&
            balanceOf(wallet) > maxBalance
        ) {
            revert OverMax(balanceOf(wallet), maxBalance);
        }
    }
}
