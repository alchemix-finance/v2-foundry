// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {stdCheats} from "../../lib/forge-std/src/stdlib.sol";
import "../../lib/forge-std/src/console.sol";

import {
    RETHAdapterV1,
    InitializationParams as AdapterInitializationParams
} from "../adapters/rocket/RETHAdapterV1.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";
import {IRETH} from "../interfaces/external/rocket/IRETH.sol";
import {IRocketStorage} from "../interfaces/external/rocket/IRocketStorage.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {RocketPool} from "../libraries/RocketPool.sol";
import {SafeERC20} from "../libraries/SafeERC20.sol";

contract RocketStakedEthereumAdapterV1Test is DSTestPlus, stdCheats {
    address constant admin = 0x8392F6669292fA56123F71949B52d883aE57e225;
    address constant alchemistETH = 0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c;
    address constant alETH = 0x0100546F2cD4C9D97f798fFC9755E47865FF7Ee6;
    address constant owner = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address constant wETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant whitelistETH = 0xA3dfCcbad1333DC69997Da28C961FF8B2879e653;
    uint256 constant BPS = 10000;
    uint256 constant MAX_INT = 2**256 - 1;

    IWETH9 constant weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IRocketStorage constant rocketStorage = IRocketStorage(0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46);

    IRETH rETH;
    RETHAdapterV1 adapter;

    function setUp() external {
        rETH = RocketPool.getRETH(rocketStorage);

        adapter = new RETHAdapterV1(AdapterInitializationParams({
            alchemist:       alchemistETH,
            token:           address(rETH),
            underlyingToken: address(weth)
        }));

        hevm.startPrank(owner);
        IWhitelist(whitelistETH).add(address(adapter));
        IWhitelist(whitelistETH).add(address(this));
        IAlchemistV2(alchemistETH).setMaximumExpectedValue(address(rETH), 10000000000000 ether);
        IAlchemistV2(alchemistETH).setTokenAdapter(address(rETH), address(adapter));
        hevm.stopPrank();
    }

    function testPrice() external {
        uint256 decimals = SafeERC20.expectDecimals(address(rETH));
        assertEq(adapter.price(), rETH.getEthValue(10**decimals));
    }

    function testWrap() external {
        tip(address(weth), address(this), 1e18);

        SafeERC20.safeApprove(address(weth), address(adapter), 1e18);

        expectUnsupportedOperationError("Wrapping is not supported");
        hevm.prank(alchemistETH);
        adapter.wrap(1e18, address(0xbeef));
    }

    function testWithdrawUnderlying() external {
        tip(address(rETH), address(this), 1e18);

        uint256 expectedEth = rETH.getEthValue(1e18);

        // Deposit into position
        SafeERC20.safeApprove(address(rETH), alchemistETH, 1e18);
        uint256 shares = IAlchemistV2(alchemistETH).deposit(address(rETH), 1e18, address(this));

        // Withdraw and unwrap
        uint256 unwrapped = IAlchemistV2(alchemistETH).withdrawUnderlying(address(rETH), shares, address(this), 0);

        assertEq(rETH.allowance(address(this), address(adapter)), 0);
        assertEq(weth.balanceOf(address(this)), unwrapped);
        assertApproxEq(weth.balanceOf(address(this)), expectedEth, expectedEth * 970 / 1000);
    }

    function testWithdrawUnderlyingViaBurn() external {
        tip(address(rETH), address(this), 1e18);

        uint256 expectedEth = rETH.getEthValue(1e18);
        hevm.deal(address(rETH), expectedEth);
        uint256 beforeCollateral = rETH.getTotalCollateral();
        assertEq(beforeCollateral, expectedEth);

        // Deposit into position
        SafeERC20.safeApprove(address(rETH), alchemistETH, 1e18);
        uint256 shares = IAlchemistV2(alchemistETH).deposit(address(rETH), 1e18, address(this));

        // Withdraw and unwrap
        uint256 unwrapped = IAlchemistV2(alchemistETH).withdrawUnderlying(address(rETH), shares, address(this), 0);

        uint256 afterCollateral = rETH.getTotalCollateral();
        assertApproxEq(afterCollateral, 0, 10);

        // assertEq(rETH.allowance(address(this), address(adapter)), 0);
        assertEq(weth.balanceOf(address(this)), unwrapped);
        assertApproxEq(weth.balanceOf(address(this)), expectedEth, expectedEth * 970 / 1000);
    }

    function testHarvest() external {
        tip(address(rETH), address(this), 1e18);

        uint256 expectedEth = rETH.getEthValue(1e18);

        // New position
        SafeERC20.safeApprove(address(rETH), alchemistETH, 1e18);
        uint256 shares = IAlchemistV2(alchemistETH).deposit(address(rETH), 1e18, address(this));
        (int256 debtBefore, ) = IAlchemistV2(alchemistETH).accounts(address(this));

        // Roll ahead then harvest
        hevm.roll(block.number + 100000);
        hevm.prank(owner);
        IAlchemistV2(alchemistETH).harvest(address(rETH), 0);

        // Roll ahead one block then check credited amount
        hevm.roll(block.number + 1);
        (int256 debtAfter, ) = IAlchemistV2(alchemistETH).accounts(address(this));
        assertGt(debtBefore, debtAfter);
    }

    function testLiquidate() external {
        tip(address(rETH), address(this), 1e18);

        uint256 expectedEth = rETH.getEthValue(1e18);

        SafeERC20.safeApprove(address(rETH), alchemistETH, 1e18);
        uint256 shares = IAlchemistV2(alchemistETH).deposit(address(rETH), 1e18, address(this));
        uint256 pps = IAlchemistV2(alchemistETH).getUnderlyingTokensPerShare(address(rETH));
        uint256 mintAmt = shares * pps / 1e18 / 4;
        IAlchemistV2(alchemistETH).mint(mintAmt, address(this));

        (int256 debtBefore, ) = IAlchemistV2(alchemistETH).accounts(address(this));

        uint256 sharesLiquidated = IAlchemistV2(alchemistETH).liquidate(address(rETH), shares / 4, mintAmt * 97 / 100);

        (int256 debtAfter, ) = IAlchemistV2(alchemistETH).accounts(address(this));

        (uint256 sharesLeft, ) =  IAlchemistV2(alchemistETH).positions(address(this), address(rETH));

        assertApproxEq(0, uint256(debtAfter), mintAmt - mintAmt * 97 / 100);
        assertEq(shares - sharesLiquidated, sharesLeft);
    }

    function testLiquidateViaBurn() external {
        tip(address(rETH), address(this), 1e18);

        uint256 expectedEth = rETH.getEthValue(1e18);
        hevm.deal(address(rETH), expectedEth);
        SafeERC20.safeApprove(address(rETH), alchemistETH, 1e18);
        uint256 shares = IAlchemistV2(alchemistETH).deposit(address(rETH), 1e18, address(this));
        uint256 pps = IAlchemistV2(alchemistETH).getUnderlyingTokensPerShare(address(rETH));
        uint256 mintAmt = shares * pps / 1e18 / 4;
        IAlchemistV2(alchemistETH).mint(mintAmt, address(this));

        (int256 debtBefore, ) = IAlchemistV2(alchemistETH).accounts(address(this));

        uint256 sharesLiquidated = IAlchemistV2(alchemistETH).liquidate(address(rETH), shares / 4, 0);

        (int256 debtAfter, ) = IAlchemistV2(alchemistETH).accounts(address(this));

        (uint256 sharesLeft, ) =  IAlchemistV2(alchemistETH).positions(address(this), address(rETH));

        assertApproxEq(0, uint256(debtAfter), 10);
        assertEq(shares - sharesLiquidated, sharesLeft);
    }
}