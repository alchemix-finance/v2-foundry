// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {stdCheats} from "../../lib/forge-std/src/stdlib.sol";

import {
    AAVETokenAdapter,
    InitializationParams as AdapterInitializationParams
} from "../adapters/aave/AAVETokenAdapter.sol";

import {StaticAToken} from "../external/aave/StaticAToken.sol";
import {ILendingPool} from "../interfaces/external/aave/ILendingPool.sol";
import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";
import {TokenUtils} from "../libraries/TokenUtils.sol";
import {console} from "../../lib/forge-std/src/console.sol";

contract AAVETokenAdapterTest is DSTestPlus, stdCheats {
    uint256 constant BPS = 10000;
    address constant dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // ETH mainnet DAI
    ILendingPool lendingPool = ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    address aDai = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
    string wrappedTokenName = "staticAaveDai";
    string wrappedTokenSymbol = "saDAI";
    StaticAToken staticAToken;
    AAVETokenAdapter adapter;
    address alchemistAlUSD = 0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd;
    address alchemistAlETH = 0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c;
    address alchemistAdmin = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address alchemistAlUSDWhitelist = 0x78537a6CeBa16f412E123a90472C6E0e9A8F1132;
    address alchemistAlETHWhitelist = 0xA3dfCcbad1333DC69997Da28C961FF8B2879e653;

    function setUp() external {
        staticAToken = new StaticAToken(
            lendingPool,
            aDai,
            wrappedTokenName,
            wrappedTokenSymbol
        );
        adapter = new AAVETokenAdapter(AdapterInitializationParams({
            alchemist:       address(this),
            token:           address(staticAToken),
            underlyingToken: address(dai)
        }));
        hevm.startPrank(alchemistAdmin);
        IWhitelist(alchemistAlUSDWhitelist).add(address(this));
        IWhitelist(alchemistAlETHWhitelist).add(address(this));
        hevm.stopPrank();

        hevm.label(0x028171bCA77440897B824Ca71D1c56caC55b68A3, "aDAI");
        hevm.label(0x6B175474E89094C44Da98b954EedeAC495271d0F, "DAI");
        hevm.label(0xBcca60bB61934080951369a648Fb03DF4F96263C, "aUSDC");
        hevm.label(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, "USDC");
        hevm.label(0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811, "aUSDT");
        hevm.label(0xdAC17F958D2ee523a2206206994597C13D831ec7, "USDT");
        hevm.label(0x030bA81f1c18d280636F32af80b9AAd02Cf0854e, "aWETH");
        hevm.label(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, "WETH");
    }

    function testTokenDai() external {
        runTokenTest(alchemistAlUSD, 0x028171bCA77440897B824Ca71D1c56caC55b68A3, 0x6B175474E89094C44Da98b954EedeAC495271d0F, "Static Aave DAI", "saDAI", 1000 ether);
    }

    function testTokenUsdc() external {
        runTokenTest(alchemistAlUSD, 0xBcca60bB61934080951369a648Fb03DF4F96263C, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, "Static Aave USDC", "saUSDC", 1000000000);
    }

    function testTokenUsdt() external {
        runTokenTest(alchemistAlUSD, 0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811, 0xdAC17F958D2ee523a2206206994597C13D831ec7, "Static Aave USDT", "saUSDT", 1000000000);
    }

    function testTokenWeth() external {
        runTokenTest(alchemistAlETH, 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, "Static Aave WETH", "saWETH", 1000 ether);
    }

    function runTokenTest(address alchemist, address aToken, address underlyingToken, string memory name, string memory symbol, uint256 amount) internal {
        StaticAToken newStaticAToken = new StaticAToken(
            lendingPool,
            aToken,
            name,
            symbol
        );
        AAVETokenAdapter newAdapter = new AAVETokenAdapter(AdapterInitializationParams({
            alchemist:       alchemist,
            token:           address(newStaticAToken),
            underlyingToken: underlyingToken
        }));
        IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(newAdapter),
            maximumLoss: 1,
            maximumExpectedValue: 1000000 ether,
            creditUnlockBlocks: 7200
        });
        hevm.startPrank(alchemistAdmin);
        IAlchemistV2(alchemist).addYieldToken(address(newStaticAToken), ytc);
        IAlchemistV2(alchemist).setYieldTokenEnabled(address(newStaticAToken), true);
        hevm.stopPrank();

        tip(underlyingToken, address(this), amount);
        uint256 startPrice = IAlchemistV2(alchemist).getUnderlyingTokensPerShare(address(newStaticAToken));
        TokenUtils.safeApprove(underlyingToken, alchemist, amount);
        IAlchemistV2(alchemist).depositUnderlying(address(newStaticAToken), amount, address(this), 0);
        (uint256 startShares, ) = IAlchemistV2(alchemist).positions(address(this), address(newStaticAToken));
        uint256 expectedValue = startShares * startPrice / (10 ** newStaticAToken.decimals());
        assertApproxEq(amount, expectedValue, 1000);

        uint256 startBal = IERC20(underlyingToken).balanceOf(address(this));
        assertEq(startBal, 0);

        IAlchemistV2(alchemist).withdrawUnderlying(address(newStaticAToken), startShares, address(this), 0);
        (uint256 endShares, ) = IAlchemistV2(alchemist).positions(address(this), address(newStaticAToken));
        assertEq(endShares, 0);

        uint256 endBal = IERC20(underlyingToken).balanceOf(address(this));
        assertApproxEq(endBal, amount, 1);
    }

    function testRoundTrip() external {
        uint256 depositAmount = 1e18;

        tip(dai, address(this), depositAmount);

        SafeERC20.safeApprove(dai, address(adapter), depositAmount);
        uint256 wrapped = adapter.wrap(depositAmount, address(this));

        uint256 underlyingValue = wrapped * adapter.price() / 10**SafeERC20.expectDecimals(address(staticAToken));
        assertGe(depositAmount, underlyingValue);
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));
        
        assertEq(IERC20(dai).balanceOf(address(0xbeef)), unwrapped);
        assertEq(staticAToken.balanceOf(address(this)), 0);
        assertEq(staticAToken.balanceOf(address(adapter)), 0);
    }

    function testRoundTripFuzz(uint256 amount) external {
        hevm.assume(
            amount >= 10**SafeERC20.expectDecimals(dai) && 
            amount < type(uint96).max
        );
        
        tip(dai, address(this), amount);

        SafeERC20.safeApprove(dai, address(adapter), amount);
        uint256 wrapped = adapter.wrap(amount, address(this));

        uint256 underlyingValue = wrapped * adapter.price() / 10**SafeERC20.expectDecimals(address(staticAToken));
        assertApproxEq(amount, underlyingValue, amount * 10000 / 1e18);
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));
        
        assertApproxEq(IERC20(dai).balanceOf(address(0xbeef)), unwrapped, 10000);
        assertEq(staticAToken.balanceOf(address(this)), 0);
        assertEq(staticAToken.balanceOf(address(adapter)), 0);
    }

    function testAppreciation() external {
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