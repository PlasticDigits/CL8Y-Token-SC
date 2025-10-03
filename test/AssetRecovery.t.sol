// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {AssetRecovery} from "../src/AssetRecovery.sol";
import {IGuardExecutor} from "../src/interfaces/IGuardExecutor.sol";
import {IBlacklist} from "../src/interfaces/IBlacklist.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockGuardExecutor is IGuardExecutor {
    address public lastTarget;
    bytes public lastData;
    uint256 public lastValue;

    function execute(
        address target,
        bytes calldata data
    ) external payable returns (bytes memory) {
        lastTarget = target;
        lastData = data;
        lastValue = msg.value;

        (bool success, bytes memory result) = target.call{value: msg.value}(
            data
        );
        require(success, "MockGuard: call failed");
        return result;
    }
}

contract MockBlacklist is IBlacklist {
    mapping(address account => bool status) internal _blacklisted;

    function isBlacklisted(address account) external view returns (bool) {
        return _blacklisted[account];
    }

    function setIsBlacklistedToTrue(address[] calldata accounts) external {
        for (uint256 i; i < accounts.length; i++) {
            _blacklisted[accounts[i]] = true;
        }
    }

    function setIsBlacklistedToFalse(address[] calldata accounts) external {
        for (uint256 i; i < accounts.length; i++) {
            _blacklisted[accounts[i]] = false;
        }
    }

    function setBlacklisted(address account, bool status) external {
        _blacklisted[account] = status;
    }
}

contract AssetRecoveryTest is Test {
    AssetRecovery assetRecovery;
    MockGuardExecutor guard;
    MockBlacklist blacklist;
    MockERC20 token;
    AccessManager accessManager;

    address owner = address(0x1);
    address maliciousWallet = address(0x2);
    address recipient = address(0x3);
    address secureVault = address(0x4);
    address unauthorized = address(0x5);

    uint256 constant STARTING_BALANCE = 1_000 ether;
    uint256 constant SEIZE_AMOUNT = 200 ether;

    function setUp() public {
        vm.startPrank(owner);

        accessManager = new AccessManager(owner);
        guard = new MockGuardExecutor();
        blacklist = new MockBlacklist();
        token = new MockERC20();

        assetRecovery = new AssetRecovery(
            address(accessManager),
            guard,
            IERC20(address(token)),
            blacklist
        );

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = AssetRecovery.seize.selector;
        selectors[1] = AssetRecovery.seizeAll.selector;
        selectors[2] = AssetRecovery.release.selector;
        selectors[3] = AssetRecovery.recover.selector;
        accessManager.setTargetFunctionRole(
            address(assetRecovery),
            selectors,
            accessManager.ADMIN_ROLE()
        );
        accessManager.grantRole(accessManager.ADMIN_ROLE(), owner, 0);

        vm.stopPrank();

        token.mint(maliciousWallet, STARTING_BALANCE);

        vm.prank(maliciousWallet);
        token.approve(address(guard), type(uint256).max);
    }

    function _blacklist(address account) internal {
        blacklist.setBlacklisted(account, true);
    }

    function _seize() internal {
        _blacklist(maliciousWallet);
        vm.prank(owner);
        assetRecovery.seize(maliciousWallet, SEIZE_AMOUNT);
    }

    function testSeizeTransfersFundsAndTracksUsage() public {
        _blacklist(maliciousWallet);

        vm.expectEmit(address(assetRecovery));
        emit AssetRecovery.Seized(maliciousWallet, SEIZE_AMOUNT);

        vm.prank(owner);
        assetRecovery.seize(maliciousWallet, SEIZE_AMOUNT);

        assertEq(
            token.balanceOf(maliciousWallet),
            STARTING_BALANCE - SEIZE_AMOUNT
        );
        assertEq(token.balanceOf(address(assetRecovery)), SEIZE_AMOUNT);
        assertEq(guard.lastTarget(), address(token));
        bytes memory lastCallData = guard.lastData();
        assertGt(lastCallData.length, 0);

        AssetRecovery.WalletRecord memory walletRecord = assetRecovery.record(
            maliciousWallet
        );
        assertEq(walletRecord.totalReceived, SEIZE_AMOUNT);
        assertEq(walletRecord.totalReleased, 0);
        assertEq(walletRecord.totalRecovered, 0);
        assertEq(assetRecovery.holdings(maliciousWallet), SEIZE_AMOUNT);
    }

    function testSeizeRevertsWhenWalletNotBlacklisted() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AssetRecovery.WalletNotBlacklisted.selector,
                maliciousWallet
            )
        );
        assetRecovery.seize(maliciousWallet, SEIZE_AMOUNT);
    }

    function testSeizeRevertsForUnauthorized() public {
        _blacklist(maliciousWallet);

        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessManaged.AccessManagedUnauthorized.selector,
                unauthorized
            )
        );
        assetRecovery.seize(maliciousWallet, SEIZE_AMOUNT);
    }

    function testReleaseReturnsTokensAndUpdatesRecord() public {
        _seize();

        uint256 releaseAmount = 80 ether;

        vm.expectEmit(address(assetRecovery));
        emit AssetRecovery.Released(maliciousWallet, releaseAmount);

        vm.prank(owner);
        assetRecovery.release(maliciousWallet, releaseAmount);

        assertEq(
            token.balanceOf(maliciousWallet),
            STARTING_BALANCE - SEIZE_AMOUNT + releaseAmount
        );
        assertEq(
            token.balanceOf(address(assetRecovery)),
            SEIZE_AMOUNT - releaseAmount
        );

        AssetRecovery.WalletRecord memory walletRecord = assetRecovery.record(
            maliciousWallet
        );
        assertEq(walletRecord.totalReceived, SEIZE_AMOUNT);
        assertEq(walletRecord.totalReleased, releaseAmount);
        assertEq(walletRecord.totalRecovered, 0);
        assertEq(
            assetRecovery.holdings(maliciousWallet),
            SEIZE_AMOUNT - releaseAmount
        );
    }

    function testReleaseRevertsWhenAmountExceedsHoldings() public {
        _seize();

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AssetRecovery.AmountExceedsHoldings.selector,
                SEIZE_AMOUNT * 2,
                SEIZE_AMOUNT
            )
        );
        assetRecovery.release(maliciousWallet, SEIZE_AMOUNT * 2);
    }

    function testRecoverTransfersToRecipient() public {
        _seize();

        uint256 recoverAmount = 120 ether;

        vm.expectEmit(address(assetRecovery));
        emit AssetRecovery.Recovered(
            maliciousWallet,
            secureVault,
            recoverAmount
        );

        vm.prank(owner);
        assetRecovery.recover(maliciousWallet, secureVault, recoverAmount);

        assertEq(
            token.balanceOf(address(assetRecovery)),
            SEIZE_AMOUNT - recoverAmount
        );
        assertEq(token.balanceOf(secureVault), recoverAmount);

        AssetRecovery.WalletRecord memory walletRecord = assetRecovery.record(
            maliciousWallet
        );
        assertEq(walletRecord.totalReceived, SEIZE_AMOUNT);
        assertEq(walletRecord.totalReleased, 0);
        assertEq(walletRecord.totalRecovered, recoverAmount);
        assertEq(
            assetRecovery.holdings(maliciousWallet),
            SEIZE_AMOUNT - recoverAmount
        );
    }

    function testRecoverRevertsForZeroRecipient() public {
        _seize();

        vm.prank(owner);
        vm.expectRevert(AssetRecovery.ZeroAddress.selector);
        assetRecovery.recover(maliciousWallet, address(0), 1 ether);
    }

    function testHoldingsReflectsCombinedReleaseAndRecover() public {
        _seize();

        vm.prank(owner);
        assetRecovery.release(maliciousWallet, 50 ether);

        vm.prank(owner);
        assetRecovery.recover(maliciousWallet, secureVault, 70 ether);

        assertEq(
            assetRecovery.holdings(maliciousWallet),
            SEIZE_AMOUNT - 120 ether
        );

        AssetRecovery.WalletRecord memory walletRecord = assetRecovery.record(
            maliciousWallet
        );
        assertEq(walletRecord.totalReceived, SEIZE_AMOUNT);
        assertEq(walletRecord.totalReleased, 50 ether);
        assertEq(walletRecord.totalRecovered, 70 ether);
    }

    function testSeizeAllUsesEntireBalance() public {
        _blacklist(maliciousWallet);

        vm.expectEmit(address(assetRecovery));
        emit AssetRecovery.Seized(maliciousWallet, STARTING_BALANCE);

        vm.prank(owner);
        assetRecovery.seizeAll(maliciousWallet);

        assertEq(token.balanceOf(maliciousWallet), 0);
        assertEq(token.balanceOf(address(assetRecovery)), STARTING_BALANCE);

        AssetRecovery.WalletRecord memory walletRecord = assetRecovery.record(
            maliciousWallet
        );
        assertEq(walletRecord.totalReceived, STARTING_BALANCE);
        assertEq(assetRecovery.holdings(maliciousWallet), STARTING_BALANCE);
    }
}
