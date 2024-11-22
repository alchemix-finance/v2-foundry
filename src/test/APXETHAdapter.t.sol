// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import "../../lib/forge-std/src/console.sol";

import {
    PirexEthAdapter
} from "../adapters/pirex/PirexEthAdapter.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";
import {IPirexContract} from "../interfaces/external/pirex/IPirexContract.sol";
import {IapxEthToken} from "../interfaces/external/pirex/IapxEthToken.sol";
import {IStableSwap} from "../interfaces/external/curve/IStableSwap.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

contract PirexEthAdapterTest is DSTestPlus {
    // Addresses (Replace with actual addresses or mock addresses for testing)
    address constant admin = 0xAdminAddress; // Replace with actual admin address
    address constant alchemistETH = 0xAlchemistAddress; // AlchemistV2 contract address
    address constant alETH = 0xAlETHAddress; // alETH token address
    address constant owner = 0xOwnerAddress; // Owner address
    address constant wETH = 0xWETHAddress; // WETH token address
    address constant whitelistETH = 0xWhitelistAddress; // Whitelist contract address

    IWETH9 constant weth = IWETH9(wETH);
    IERC20 apxETH = IERC20(0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6); // apxETH token address
    IERC20 pxETH = IERC20(0x04C154b66CB340F3Ae24111CC767e0184Ed00Cc6); // pxETH token address
    IPirexContract pirexContract = IPirexContract(0xD664b74274DfEB538d9baC494F3a4760828B02b0); // Pirex contract address
    IapxEthToken apxEthTokenContract = IapxEthToken(0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6); // apxETH token contract (same as apxETH)
    IStableSwap curvePool = IStableSwap(0xCurvePoolAddress); // Curve pool address

    PirexEthAdapter adapter;

    function setUp() external {
        // Initialize the adapter
        adapter = new PirexEthAdapter(
            alchemistETH,
            address(apxETH),
            address(pxETH),
            address(weth),
            address(pirexContract),
            address(apxEthTokenContract),
            address(curvePool),
            /* curvePoolPxEthIndex */ 0,
            /* curvePoolEthIndex */ 1
        );

        // Set up the Alchemist and Whitelist configurations
        hevm.startPrank(owner);
        IWhitelist(whitelistETH).add(address(adapter));
        IWhitelist(whitelistETH).add(address(this));
        IAlchemistV2(alchemistETH).setMaximumExpectedValue(address(apxETH), 10000000000000 ether);
        IAlchemistV2(alchemistETH).setTokenAdapter(address(apxETH), address(adapter));
        hevm.stopPrank();
    }

    function testPrice() external {
        uint256 decimals = SafeERC20.expectDecimals(address(apxETH));
        uint256 expectedPrice = adapter.price();
        assertEq(expectedPrice, 1e18); // Assuming price is 1e18 as per adapter
    }

    function testWrap() external {
        // Arrange
        uint256 amountToWrap = 1e18;
        deal(address(weth), address(this), amountToWrap);
        SafeERC20.safeApprove(address(weth), address(adapter), amountToWrap);

        // Act
        hevm.prank(alchemistETH);
        uint256 mintedShares = adapter.wrap(amountToWrap, address(this));

        // Assert
        uint256 apxEthBalance = apxETH.balanceOf(address(this));
        assertEq(apxEthBalance, mintedShares);
        // Optionally, check that the mintedShares are within expected range
    }

    function testUnwrap() external {
        // Arrange
        uint256 amountToUnwrap = 1e18;
        // Mint apxETH to this contract
        deal(address(apxETH), address(this), amountToUnwrap);
        SafeERC20.safeApprove(address(apxETH), address(adapter), amountToUnwrap);

        // Mock the Curve pool exchange if necessary
        // For testing purposes, assume exchange rate is 1 pxETH = 1 WETH

        // Act
        hevm.prank(alchemistETH);
        uint256 receivedWeth = adapter.unwrap(amountToUnwrap, address(this));

        // Assert
        uint256 wethBalance = weth.balanceOf(address(this));
        assertEq(wethBalance, receivedWeth);
        // Optionally, check that the receivedWeth is within expected range
    }

    function testDepositAndWithdraw() external {
        // Arrange
        uint256 depositAmount = 1e18;
        deal(address(weth), address(this), depositAmount);
        SafeERC20.safeApprove(address(weth), alchemistETH, depositAmount);

        // Act
        uint256 shares = IAlchemistV2(alchemistETH).deposit(address(apxETH), depositAmount, address(this));

        // Withdraw and unwrap
        uint256 unwrappedAmount = IAlchemistV2(alchemistETH).withdrawUnderlying(address(apxETH), shares, address(this), 0);

        // Assert
        uint256 wethBalance = weth.balanceOf(address(this));
        assertEq(wethBalance, unwrappedAmount);
        // Verify that the unwrapped amount matches expectations
    }

    function testHarvest() external {
        // Arrange
        uint256 depositAmount = 1e18;
        deal(address(weth), address(this), depositAmount);
        SafeERC20.safeApprove(address(weth), alchemistETH, depositAmount);

        // Deposit into the Alchemist
        uint256 shares = IAlchemistV2(alchemistETH).deposit(address(apxETH), depositAmount, address(this));

        // Simulate time passing for yield to accrue
        hevm.warp(block.timestamp + 1 weeks);

        // Act
        // Harvest the yield
        hevm.prank(owner);
        IAlchemistV2(alchemistETH).harvest(address(apxETH), 0);

        // Assert
        // Check that yield was harvested and credited
        (int256 debtBefore, ) = IAlchemistV2(alchemistETH).accounts(address(this));

        // Simulate another week passing
        hevm.warp(block.timestamp + 1 weeks);

        // Harvest again
        hevm.prank(owner);
        IAlchemistV2(alchemistETH).harvest(address(apxETH), 0);

        (int256 debtAfter, ) = IAlchemistV2(alchemistETH).accounts(address(this));

        assertGt(debtBefore, debtAfter);
    }

    function testLiquidate() external {
        // Arrange
        uint256 depositAmount = 10e18;
        deal(address(weth), address(this), depositAmount);
        SafeERC20.safeApprove(address(weth), alchemistETH, depositAmount);

        // Deposit into the Alchemist
        uint256 shares = IAlchemistV2(alchemistETH).deposit(address(apxETH), depositAmount, address(this));

        // Borrow some alETH against the deposited collateral
        uint256 pps = IAlchemistV2(alchemistETH).getUnderlyingTokensPerShare(address(apxETH));
        uint256 borrowAmount = (shares * pps) / 1e18 / 2; // Borrow up to 50% LTV
        IAlchemistV2(alchemistETH).mint(borrowAmount, address(this));

        // Simulate price drop or increased debt to trigger undercollateralization
        // For testing purposes, we'll directly adjust the debt
        hevm.prank(owner);
        IAlchemistV2(alchemistETH).setAccountDebt(address(this), int256(borrowAmount * 2));

        // Act
        // Liquidate part of the collateral to repay debt
        uint256 collateralToLiquidate = shares / 2;
        uint256 minDebtRepayment = borrowAmount / 2;
        uint256 sharesLiquidated = IAlchemistV2(alchemistETH).liquidate(address(apxETH), collateralToLiquidate, minDebtRepayment);

        // Assert
        // Check that the debt has been reduced
        (int256 debtAfter, ) = IAlchemistV2(alchemistETH).accounts(address(this));
        assertApproxEq(debtAfter, int256(borrowAmount * 2 - minDebtRepayment), 1);

        // Check that the shares have been reduced
        (uint256 sharesLeft, ) = IAlchemistV2(alchemistETH).positions(address(this), address(apxETH));
        assertEq(sharesLeft, shares - sharesLiquidated);
    }
}
