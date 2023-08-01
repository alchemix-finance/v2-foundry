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
import {ITransmuterBuffer} from "../interfaces/transmuter/ITransmuterBuffer.sol";
import {ICERC20} from "../interfaces/external/compound/ICERC20.sol";
import {IStakedFraxEth} from "../interfaces/external/frax/IStakedFraxEth.sol";
import {IFraxMinter} from "../interfaces/external/frax/IFraxMinter.sol";


import {SafeERC20} from "../libraries/SafeERC20.sol";
import {LibFuse} from "../libraries/LibFuse.sol";

contract FraxEthAdapterTest is DSTestPlus {
    uint256 constant BPS = 10000;
    uint256 constant MAX_INT = 2**256 - 1;

    address constant admin = 0x8392F6669292fA56123F71949B52d883aE57e225;
    address constant alchemistETH = 0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c;
    address constant alETH = 0x0100546F2cD4C9D97f798fFC9755E47865FF7Ee6;
    address constant curvePool = 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;
    address constant frxEth = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address constant minter = 0xbAFA44EFE7901E04E39Dad13167D089C559c1138;
    address constant owner = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address constant sfrxEth = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address constant transmuterBuffer = 0xbc2FB245594a68c927C930FBE2d00680A8C90B9e;
    address constant wETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant whitelistETH = 0xA3dfCcbad1333DC69997Da28C961FF8B2879e653;

    FraxEthAdapter adapter;

    function setUp() external {
        adapter = new FraxEthAdapter(AdapterInitializationParams({
            alchemist:              alchemistETH,
            curvePool:              curvePool,
            curvePoolEthIndex:      0,
            curvePoolfrxEthIndex:   1,
            minter:                 minter,
            token:                  sfrxEth,
            parentToken:            frxEth,
            underlyingToken:        wETH
        }));

        IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(adapter),
            maximumLoss: 1,
            maximumExpectedValue: 1000000 ether,
            creditUnlockBlocks: 7200
        });

        hevm.startPrank(owner);
        IWhitelist(whitelistETH).add(address(adapter));
        IWhitelist(whitelistETH).add(address(this));
        IAlchemistV2(alchemistETH).addYieldToken(sfrxEth, ytc);
        IAlchemistV2(alchemistETH).setYieldTokenEnabled(sfrxEth, true);
        ITransmuterBuffer(transmuterBuffer).setFlowRate(frxEth, 300000000000000);
        hevm.stopPrank();
    }

    function testPrice() external {
        assertEq(adapter.price(), IStakedFraxEth(sfrxEth).convertToAssets(1e18));
    }

    function testRoundTrip() external {
        deal(wETH, address(this), 1e18);

        SafeERC20.safeApprove(address(wETH), address(alchemistETH), 1e18);
        uint256 wrapped = IAlchemistV2(alchemistETH).depositUnderlying(sfrxEth, 1e18, address(this), 0);

        uint256 underlyingValue = wrapped * adapter.price() / 10**SafeERC20.expectDecimals(sfrxEth);
        assertGt(underlyingValue, 1e18 * 9900 / BPS /* 1% slippage */);

        uint256 unwrapped = IAlchemistV2(alchemistETH).withdrawUnderlying(sfrxEth, wrapped, address(this), 0);

        assertGt(unwrapped, 1e18 * 9900 / BPS /* 1% slippage */);
        assertEq(IERC20(sfrxEth).balanceOf(address(this)), 0);
        assertApproxEq(IERC20(sfrxEth).balanceOf(address(adapter)), 0, 10);
    }
    function testHarvest() external {
        deal(wETH, address(this), 1e18);
        deal(wETH, address(0xbeef), 1e18);

        SafeERC20.safeApprove(address(wETH), address(alchemistETH), 1e18);
        IAlchemistV2(alchemistETH).depositUnderlying(sfrxEth, 1e18, address(this), 0);
        (int256 debtBefore, ) = IAlchemistV2(alchemistETH).accounts(address(this));

        // Roll ahead then harvest
        hevm.roll(block.number + 100000);
        hevm.warp(block.timestamp + 100000000);
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
}