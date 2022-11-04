// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {
    FraxEthAdapter,
    InitializationParams as AdapterInitializationParams
} from "../adapters/frax/FraxEthAdapter.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";
import {ICERC20} from "../interfaces/external/compound/ICERC20.sol";
import {IStakedFraxEth} from "../interfaces/external/frax/IStakedFraxEth.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";
import {LibFuse} from "../libraries/LibFuse.sol";

contract FraxEthAdapterTest is DSTestPlus {
    uint256 constant BPS = 10000;
    uint256 constant MAX_INT = 2**256 - 1;

    address constant admin = 0x8392F6669292fA56123F71949B52d883aE57e225;
    address constant alchemistETH = 0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c;
    address constant alETH = 0x0100546F2cD4C9D97f798fFC9755E47865FF7Ee6;
    address constant frxEth = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address constant owner = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address constant sfrxEth = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address constant wETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant whitelistETH = 0xA3dfCcbad1333DC69997Da28C961FF8B2879e653;

    FraxEthAdapter adapter;

    function setUp() external {
        adapter = new FraxEthAdapter(AdapterInitializationParams({
            token:           sfrxEth,
            underlyingToken: frxEth
        }));

        IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(adapter),
            maximumLoss: 1,
            maximumExpectedValue: 1000000 ether,
            creditUnlockBlocks: 7200
        });

        IAlchemistV2AdminActions.UnderlyingTokenConfig memory utc = IAlchemistV2AdminActions.UnderlyingTokenConfig({
			repayLimitMinimum: 1,
			repayLimitMaximum: 1000,
			repayLimitBlocks: 10,
			liquidationLimitMinimum: 1,
			liquidationLimitMaximum: 1000000000000000000,
			liquidationLimitBlocks: 7200
		});

        hevm.startPrank(owner);
        IWhitelist(whitelistETH).add(address(adapter));
        IWhitelist(whitelistETH).add(address(this));
        IAlchemistV2(alchemistETH).addUnderlyingToken(frxEth, utc);
        IAlchemistV2(alchemistETH).addYieldToken(sfrxEth, ytc);
        IAlchemistV2(alchemistETH).setYieldTokenEnabled(sfrxEth, true);
        IAlchemistV2(alchemistETH).setUnderlyingTokenEnabled(frxEth, true);
        hevm.stopPrank();
    }

    function testPrice() external {
        assertEq(adapter.price(), IStakedFraxEth(sfrxEth).convertToAssets(1e18));
    }

    function testRoundTrip() external {
        deal(frxEth, address(this), 1e18);

        SafeERC20.safeApprove(address(frxEth), address(adapter), 1e18);
        uint256 wrapped = adapter.wrap(1e18, address(this));

        uint256 underlyingValue = wrapped * adapter.price() / 10**SafeERC20.expectDecimals(sfrxEth);
        assertGt(underlyingValue, 1e18 * 9900 / BPS /* 1% slippage */);

        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(this));

        assertGt(unwrapped, 1e18 * 9900 / BPS /* 1% slippage */);
        assertEq(IERC20(sfrxEth).balanceOf(address(this)), 0);
        assertApproxEq(IERC20(sfrxEth).balanceOf(address(adapter)), 0, 10);
    }

    function testRoundTrip(uint256 amount) external {
        hevm.assume(
            amount >= 10**SafeERC20.expectDecimals(adapter.underlyingToken()) && 
            amount < 1000000000000000000000
        );

         deal(frxEth, address(this), amount);

        SafeERC20.safeApprove(address(frxEth), address(adapter), amount);
        uint256 wrapped = adapter.wrap(amount, address(this));

        uint256 underlyingValue = wrapped * adapter.price() / 10**SafeERC20.expectDecimals(sfrxEth);
        assertGt(underlyingValue, amount * 9900 / BPS /* 1% slippage */);

        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(this));

        assertGt(unwrapped, amount * 9900 / BPS /* 1% slippage */);
        assertEq(IERC20(sfrxEth).balanceOf(address(this)), 0);
        assertApproxEq(IERC20(sfrxEth).balanceOf(address(adapter)), 0, 100);
    }

    function testRoundTripIntegration() external {
        deal(frxEth, address(this), 1e18);

        SafeERC20.safeApprove(address(frxEth), address(alchemistETH), 1e18);
        uint256 wrapped = IAlchemistV2(alchemistETH).depositUnderlying(sfrxEth, 1e18, address(this), 0);

        uint256 underlyingValue = wrapped * adapter.price() / 10**SafeERC20.expectDecimals(sfrxEth);
        assertGt(underlyingValue, 1e18 * 9900 / BPS /* 1% slippage */);

        uint256 unwrapped = IAlchemistV2(alchemistETH).withdrawUnderlying(sfrxEth, wrapped, address(this), 0);

        assertGt(unwrapped, 1e18 * 9900 / BPS /* 1% slippage */);
        assertEq(IERC20(sfrxEth).balanceOf(address(this)), 0);
        assertApproxEq(IERC20(sfrxEth).balanceOf(address(adapter)), 0, 10);
    }

    function testHarvest() external {
        tip(sfrxEth, address(this), 1e18);

        // New position
        SafeERC20.safeApprove(sfrxEth, alchemistETH, 1e18);
        uint256 shares = IAlchemistV2(alchemistETH).deposit(sfrxEth, 1e18, address(this));
        (int256 debtBefore, ) = IAlchemistV2(alchemistETH).accounts(address(this));

        // Roll ahead then harvest
        hevm.roll(block.number + 100000);
        hevm.prank(owner);
        IAlchemistV2(alchemistETH).harvest(sfrxEth, 0);

        // Roll ahead one block then check credited amount
        hevm.roll(block.number + 1);
        (int256 debtAfter, ) = IAlchemistV2(alchemistETH).accounts(address(this));
        assertGt(debtBefore, debtAfter);
    }

    function testLiquidate() external {
        tip(sfrxEth, address(this), 1e18);

        SafeERC20.safeApprove(sfrxEth, alchemistETH, 1e18);
        uint256 shares = IAlchemistV2(alchemistETH).deposit(sfrxEth, 1e18, address(this));
        uint256 pps = IAlchemistV2(alchemistETH).getUnderlyingTokensPerShare(sfrxEth);
        uint256 mintAmt = shares * pps / 1e18 / 4;
        IAlchemistV2(alchemistETH).mint(mintAmt, address(this));

        (int256 debtBefore, ) = IAlchemistV2(alchemistETH).accounts(address(this));

        uint256 sharesLiquidated = IAlchemistV2(alchemistETH).liquidate(sfrxEth, shares / 4, mintAmt * 97 / 100);

        (int256 debtAfter, ) = IAlchemistV2(alchemistETH).accounts(address(this));

        (uint256 sharesLeft, ) =  IAlchemistV2(alchemistETH).positions(address(this), sfrxEth);

        assertApproxEq(0, uint256(debtAfter), mintAmt - mintAmt * 97 / 100);
        assertEq(shares - sharesLiquidated, sharesLeft);
    }

    function testLiquidateViaBurn() external {
        tip(sfrxEth, address(this), 1e18);

        hevm.deal(sfrxEth, 1e18);

        SafeERC20.safeApprove(sfrxEth, alchemistETH, 1e18);
        uint256 shares = IAlchemistV2(alchemistETH).deposit(sfrxEth, 1e18, address(this));
        uint256 pps = IAlchemistV2(alchemistETH).getUnderlyingTokensPerShare(sfrxEth);
        uint256 mintAmt = shares * pps / 1e18 / 4;
        IAlchemistV2(alchemistETH).mint(mintAmt, address(this));

        (int256 debtBefore, ) = IAlchemistV2(alchemistETH).accounts(address(this));

        uint256 sharesLiquidated = IAlchemistV2(alchemistETH).liquidate(sfrxEth, shares / 4, 0);

        (int256 debtAfter, ) = IAlchemistV2(alchemistETH).accounts(address(this));

        (uint256 sharesLeft, ) =  IAlchemistV2(alchemistETH).positions(address(this), sfrxEth);

        assertApproxEq(0, uint256(debtAfter), 10);
        assertEq(shares - sharesLiquidated, sharesLeft);
    }
}