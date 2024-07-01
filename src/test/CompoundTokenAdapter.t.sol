// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {stdCheats} from "../../lib/forge-std/src/stdlib.sol";

import {CompoundTokenAdapter} from "../adapters/compound/CompoundTokenAdapter.sol";
import {CompoundTokenAdapterLegacy} from "../adapters/compound/CompoundTokenAdapterLegacy.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";
import {ICERC20} from "../interfaces/compound/ICERC20.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";
import {TokenUtils} from "../libraries/TokenUtils.sol";
import {console} from "../../lib/forge-std/src/console.sol";

contract CompoundTokenAdapterTest is DSTestPlus, stdCheats {
    uint256 constant BPS = 10000;
    address constant dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant cdai = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address constant usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant cusdc = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    address constant usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant cusdt = 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9;
    address constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant ceth = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    address alchemistAlUSD = 0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd;
    address alchemistAlETH = 0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c;
    address alchemistAdmin = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address alchemistAlUSDWhitelist = 0x78537a6CeBa16f412E123a90472C6E0e9A8F1132;
    address alchemistAlETHWhitelist = 0xA3dfCcbad1333DC69997Da28C961FF8B2879e653;

    function setUp() external {
        hevm.startPrank(alchemistAdmin);
        IWhitelist(alchemistAlUSDWhitelist).add(address(this));
        IWhitelist(alchemistAlETHWhitelist).add(address(this));
        hevm.stopPrank();
    }

    function testAllTokens() external {
        hevm.label(cdai, "cDAI");
        hevm.label(dai, "DAI");
        hevm.label(cusdc, "cUSDC");
        hevm.label(usdc, "USDC");
        hevm.label(cusdt, "cUSDT");
        hevm.label(usdt, "USDT");
        hevm.label(ceth, "cETH");
        hevm.label(weth, "WETH");
        runTokenTest(alchemistAlUSD, cdai, dai, 1000 ether);
        runTokenTest(alchemistAlUSD, cusdc, usdc, 1000000000);
        runTokenTest(alchemistAlUSD, cusdt, usdt, 1000000000);
        // runTokenTest(alchemistAlETH, ceth, weth, 1000 ether);
    }

    function runTokenTest(address alchemist, address cToken, address underlyingToken, uint256 amount) internal {        
        if (cToken == cusdc) {
            CompoundTokenAdapterLegacy cTokenAdapter = new CompoundTokenAdapterLegacy(alchemistAlUSD, cToken);
            IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
                adapter: address(cTokenAdapter),
                maximumLoss: 1,
                maximumExpectedValue: 1000000 ether,
                creditUnlockBlocks: 7200
            });
            hevm.startPrank(alchemistAdmin);
            IAlchemistV2(alchemist).addYieldToken(cToken, ytc);
            IAlchemistV2(alchemist).setYieldTokenEnabled(cToken, true);
            hevm.stopPrank();
        } else {
            CompoundTokenAdapter cTokenAdapter = new CompoundTokenAdapter(alchemistAlUSD, cToken);
            IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
                adapter: address(cTokenAdapter),
                maximumLoss: 1,
                maximumExpectedValue: 1000000 ether,
                creditUnlockBlocks: 7200
            });
            hevm.startPrank(alchemistAdmin);
            IAlchemistV2(alchemist).addYieldToken(cToken, ytc);
            IAlchemistV2(alchemist).setYieldTokenEnabled(cToken, true);
            hevm.stopPrank();
        }

        tip(underlyingToken, address(this), amount);
        uint256 startPrice = IAlchemistV2(alchemist).getUnderlyingTokensPerShare(cToken);

        TokenUtils.safeApprove(underlyingToken, alchemist, amount);
        IAlchemistV2(alchemist).depositUnderlying(cToken, amount, address(this), 0);
        (uint256 startShares, ) = IAlchemistV2(alchemist).positions(address(this), cToken);
        uint256 expectedValue = startShares * startPrice / 1e8;
        assertApproxEq(amount, expectedValue, 10**10);

        uint256 startBal = IERC20(underlyingToken).balanceOf(address(this));
        assertEq(startBal, 0);

        // hevm.roll(block.number + 10);

        IAlchemistV2(alchemist).withdrawUnderlying(cToken, startShares, address(this), 0);
        (uint256 endShares, ) = IAlchemistV2(alchemist).positions(address(this), cToken);
        assertEq(endShares, 0);

        uint256 endBal = IERC20(underlyingToken).balanceOf(address(this));
        assertApproxEq(endBal, amount, 10**10);
    }

    function testRoundTrip() external {
        CompoundTokenAdapter adapter = new CompoundTokenAdapter(address(this), cdai);

        uint256 depositAmount = 1e18;

        tip(dai, address(this), depositAmount);

        SafeERC20.safeApprove(dai, address(adapter), depositAmount);
        uint256 wrapped = adapter.wrap(depositAmount, address(this));

        uint256 price = adapter.price();
        uint256 underlyingValue = wrapped * price / 10**(SafeERC20.expectDecimals(cdai));
        assertApproxEq(depositAmount, underlyingValue, 10**10);
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));

        assertEq(IERC20(dai).balanceOf(address(0xbeef)), unwrapped);
        assertEq(IERC20(cdai).balanceOf(address(this)), 0);
        assertEq(IERC20(cdai).balanceOf(address(adapter)), 0);
    }

    function testRoundTripUsdc() external {
        CompoundTokenAdapterLegacy adapter = new CompoundTokenAdapterLegacy(address(this), cusdc);

        uint256 depositAmount = 1e6;

        tip(usdc, address(this), depositAmount);

        SafeERC20.safeApprove(usdc, address(adapter), depositAmount);
        uint256 wrapped = adapter.wrap(depositAmount, address(this));

        uint256 price = adapter.price();
        uint256 underlyingValue = wrapped * price / 10**(SafeERC20.expectDecimals(cusdc));
        assertApproxEq(depositAmount, underlyingValue, 20);
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));
        
        assertEq(IERC20(usdc).balanceOf(address(0xbeef)), unwrapped);
        assertEq(IERC20(cusdc).balanceOf(address(this)), 0);
        assertEq(IERC20(cusdc).balanceOf(address(adapter)), 0);
    }

    function testRoundTripFuzz(uint256 amount) external {
        CompoundTokenAdapter adapter = new CompoundTokenAdapter(address(this), cdai);

        hevm.assume(
            amount >= 10**SafeERC20.expectDecimals(dai) && 
            amount < type(uint96).max
        );
        
        tip(dai, address(this), amount);

        SafeERC20.safeApprove(dai, address(adapter), amount);
        uint256 wrapped = adapter.wrap(amount, address(this));

        uint256 underlyingValue = wrapped * adapter.price() / 10**(SafeERC20.expectDecimals(cdai));
        console.logUint(underlyingValue);
        console.logUint(amount);
        assertApproxEq(amount, underlyingValue, amount * 10**10 / 10**18); // lose 9+ decimals of precision
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));
        
        assertApproxEq(IERC20(dai).balanceOf(address(0xbeef)), unwrapped, 1); // lose 9+ decimals of precision
        assertEq(IERC20(cdai).balanceOf(address(this)), 0);
        assertEq(IERC20(cdai).balanceOf(address(adapter)), 0);
    }

    function testAppreciation() external {
        CompoundTokenAdapter adapter = new CompoundTokenAdapter(address(this), cdai);

        tip(dai, address(this), 1e18);

        SafeERC20.safeApprove(dai, address(adapter), 1e18);
        uint256 wrapped = adapter.wrap(1e18, address(this));
        
        hevm.roll(block.number + 1000);
        hevm.warp(block.timestamp + 100000);

        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));
        assertGt(unwrapped, 1e18);
    }
}