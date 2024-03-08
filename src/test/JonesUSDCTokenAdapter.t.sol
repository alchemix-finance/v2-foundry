// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import "../../lib/forge-std/src/console.sol";

import {JonesUSDCAdapter} from "../adapters/jonesDao/JonesUSDCAdapter.sol";

import {IJonesWhitelist} from "../interfaces/external/jones/IJonesWhitelist.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

contract JonesUSDCAdapterTest is DSTestPlus {
    address constant admin = 0x886FF7a2d46dcc2276e2fD631957969441130847;
    address constant alchemistUSD = 0xb46eE2E4165F629b4aBCE04B7Eb4237f951AC66F;
    address constant alUSD = 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A;
    address constant owner = 0x886FF7a2d46dcc2276e2fD631957969441130847;
    address constant whitelistUSD = 0xda94B6536E9958d63229Dc9bE4fa654Ad52921dB;
    address constant jUSDC = 0xe66998533a1992ecE9eA99cDf47686F4fc8458E0;
    address constant usdce = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant jonesWhitelist = 0x2ACc798DA9487fdD7F4F653e04D8E8411cd73e88;
    uint256 constant BPS = 10000;
    uint256 constant MAX_INT = 2**256 - 1;

    JonesUSDCAdapter adapter;

    function setUp() external {
        adapter = new JonesUSDCAdapter(0x42EfE3E686808ccA051A49BCDE34C5CbA2EBEfc1, 0xEE5828181aFD52655457C2793833EbD7ccFE86Ac);

        hevm.startPrank(owner);
        IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(adapter),
            maximumLoss: 1,
            maximumExpectedValue: 1000000 ether,
            creditUnlockBlocks: 7200
        });

        IAlchemistV2AdminActions.UnderlyingTokenConfig memory underlyingConfig = IAlchemistV2AdminActions.UnderlyingTokenConfig({
			repayLimitMinimum: 1,
			repayLimitMaximum: 1000,
			repayLimitBlocks: 10,
			liquidationLimitMinimum: 1,
			liquidationLimitMaximum: 1000,
			liquidationLimitBlocks: 7200
		});

        IAlchemistV2(alchemistUSD).addUnderlyingToken(usdce, underlyingConfig);
        IAlchemistV2(alchemistUSD).setUnderlyingTokenEnabled(usdce, true);

        IAlchemistV2(alchemistUSD).addYieldToken(jUSDC, ytc);
        IAlchemistV2(alchemistUSD).setYieldTokenEnabled(jUSDC, true);
        IWhitelist(whitelistUSD).add(address(adapter));
        IWhitelist(whitelistUSD).add(address(this));
        IAlchemistV2(alchemistUSD).setMaximumExpectedValue(address(jUSDC), 10000000000000 ether);
        IAlchemistV2(alchemistUSD).setTokenAdapter(address(jUSDC), address(adapter));
        hevm.stopPrank();

        hevm.prank(0xc8ce0aC725f914dBf1D743D51B6e222b79F479f1);
        IJonesWhitelist(jonesWhitelist).addToWhitelistContracts(address(adapter));

    }

    function testPrice() external {

    }

    function testRoundTripUnderlying() external {
        deal(address(usdce), address(this), 10e6);

        // Deposit into position
        SafeERC20.safeApprove(address(usdce), alchemistUSD, 10e6);
        uint256 shares = IAlchemistV2(alchemistUSD).depositUnderlying(address(jUSDC), 10e6, address(this), 0);

        

        // Withdraw and unwrap
        uint256 unwrapped = IAlchemistV2(alchemistUSD).withdrawUnderlying(address(jUSDC), shares, address(this), 0);
    }

    // function testWithdrawUnderlying() external {
    //     deal(address(rETH), address(this), 10e6);

    //     uint256 expectedEth = rETH.getEthValue(1e18);

    //     // Deposit into position
    //     SafeERC20.safeApprove(address(rETH), alchemistETH, 1e18);
    //     uint256 shares = IAlchemistV2(alchemistETH).deposit(address(rETH), 1e18, address(this));

    //     // Withdraw and unwrap
    //     uint256 unwrapped = IAlchemistV2(alchemistETH).withdrawUnderlying(address(rETH), shares, address(this), 0);

    //     assertEq(rETH.allowance(address(this), address(adapter)), 0);
    //     assertEq(weth.balanceOf(address(this)), unwrapped);
    //     assertApproxEq(weth.balanceOf(address(this)), expectedEth, expectedEth * 970 / 1000);
    // }

    // function testWithdrawUnderlyingViaBurn() external {
    //     deal(address(rETH), address(this), 1e18);

    //     uint256 expectedEth = rETH.getEthValue(1e18);
    //     hevm.deal(address(rETH), expectedEth);
    //     uint256 beforeCollateral = rETH.getTotalCollateral();
    //     assertEq(beforeCollateral, expectedEth);

    //     // Deposit into position
    //     SafeERC20.safeApprove(address(rETH), alchemistETH, 1e18);
    //     uint256 shares = IAlchemistV2(alchemistETH).deposit(address(rETH), 1e18, address(this));

    //     // Withdraw and unwrap
    //     uint256 unwrapped = IAlchemistV2(alchemistETH).withdrawUnderlying(address(rETH), shares, address(this), 0);

    //     uint256 afterCollateral = rETH.getTotalCollateral();
    //     assertApproxEq(afterCollateral, 0, 10);

    //     // assertEq(rETH.allowance(address(this), address(adapter)), 0);
    //     assertEq(weth.balanceOf(address(this)), unwrapped);
    //     assertApproxEq(weth.balanceOf(address(this)), expectedEth, expectedEth * 970 / 1000);
    // }

    // function testHarvest() external {
    //     deal(address(rETH), address(this), 1e18);

    //     uint256 expectedEth = rETH.getEthValue(1e18);

    //     // New position
    //     SafeERC20.safeApprove(address(rETH), alchemistETH, 1e18);
    //     uint256 shares = IAlchemistV2(alchemistETH).deposit(address(rETH), 1e18, address(this));
    //     (int256 debtBefore, ) = IAlchemistV2(alchemistETH).accounts(address(this));

    //     // Roll ahead then harvest
    //     hevm.roll(block.number + 100000);
    //     hevm.prank(owner);
    //     IAlchemistV2(alchemistETH).harvest(address(rETH), 0);

    //     // Roll ahead one block then check credited amount
    //     hevm.roll(block.number + 1);
    //     (int256 debtAfter, ) = IAlchemistV2(alchemistETH).accounts(address(this));
    //     assertGt(debtBefore, debtAfter);
    // }

    // function testLiquidate() external {
    //     deal(address(rETH), address(this), 1e18);

    //     uint256 expectedEth = rETH.getEthValue(1e18);

    //     SafeERC20.safeApprove(address(rETH), alchemistETH, 1e18);
    //     uint256 shares = IAlchemistV2(alchemistETH).deposit(address(rETH), 1e18, address(this));
    //     uint256 pps = IAlchemistV2(alchemistETH).getUnderlyingTokensPerShare(address(rETH));
    //     uint256 mintAmt = shares * pps / 1e18 / 4;
    //     IAlchemistV2(alchemistETH).mint(mintAmt, address(this));

    //     (int256 debtBefore, ) = IAlchemistV2(alchemistETH).accounts(address(this));

    //     uint256 sharesLiquidated = IAlchemistV2(alchemistETH).liquidate(address(rETH), shares / 4, mintAmt * 97 / 100);

    //     (int256 debtAfter, ) = IAlchemistV2(alchemistETH).accounts(address(this));

    //     (uint256 sharesLeft, ) =  IAlchemistV2(alchemistETH).positions(address(this), address(rETH));

    //     assertApproxEq(0, uint256(debtAfter), mintAmt - mintAmt * 97 / 100);
    //     assertEq(shares - sharesLiquidated, sharesLeft);
    // }

    // function testLiquidateViaBurn() external {
    //     deal(address(rETH), address(this), 1e18);

    //     uint256 expectedEth = rETH.getEthValue(1e18);
    //     hevm.deal(address(rETH), expectedEth);
    //     SafeERC20.safeApprove(address(rETH), alchemistETH, 1e18);
    //     uint256 shares = IAlchemistV2(alchemistETH).deposit(address(rETH), 1e18, address(this));
    //     uint256 pps = IAlchemistV2(alchemistETH).getUnderlyingTokensPerShare(address(rETH));
    //     uint256 mintAmt = shares * pps / 1e18 / 4;
    //     IAlchemistV2(alchemistETH).mint(mintAmt, address(this));

    //     (int256 debtBefore, ) = IAlchemistV2(alchemistETH).accounts(address(this));

    //     uint256 sharesLiquidated = IAlchemistV2(alchemistETH).liquidate(address(rETH), shares / 4, 0);

    //     (int256 debtAfter, ) = IAlchemistV2(alchemistETH).accounts(address(this));

    //     (uint256 sharesLeft, ) =  IAlchemistV2(alchemistETH).positions(address(this), address(rETH));

    //     assertApproxEq(0, uint256(debtAfter), 10);
    //     assertEq(shares - sharesLiquidated, sharesLeft);
    // }
}