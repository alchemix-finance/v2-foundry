// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {
    WstETHAdapterV1,
    InitializationParams as AdapterInitializationParams
} from "../adapters/lido/WstETHAdapterV1.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IChainlinkOracle} from "../interfaces/external/chainlink/IChainlinkOracle.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";
import {IStableSwap2Pool} from "../interfaces/external/curve/IStableSwap2Pool.sol";
import {IStETH} from "../interfaces/external/lido/IStETH.sol";
import {IWstETH} from "../interfaces/external/lido/IWstETH.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

contract WstETHAdapterV1Test is DSTestPlus {
    uint256 constant BPS = 10000;
    address constant admin = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address constant whitelistETHAddress = 0xA3dfCcbad1333DC69997Da28C961FF8B2879e653;

    IAlchemistV2 constant alchemist = IAlchemistV2(0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c);
    IChainlinkOracle constant oracleStethUsd = IChainlinkOracle(0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8);
    IChainlinkOracle constant oracleEthUsd = IChainlinkOracle(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    IStETH constant stETH = IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWstETH constant wstETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IWETH9 constant weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IStableSwap2Pool constant curvePool = IStableSwap2Pool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    WstETHAdapterV1 adapter;

    function setUp() external {
        adapter = new WstETHAdapterV1(AdapterInitializationParams({
            alchemist:       address(alchemist),
            token:           address(wstETH),
            parentToken:     address(stETH),
            underlyingToken: address(weth),
            curvePool:       address(curvePool),
            oracleStethUsd:  address(oracleStethUsd),
            oracleEthUsd:    address(oracleEthUsd),
            ethPoolIndex:    0,
            stEthPoolIndex:  1,
            referral:        address(0)
        }));

        hevm.startPrank(admin);
        alchemist.setTokenAdapter(address(wstETH), address(adapter));
        IWhitelist(whitelistETHAddress).add(address(this));
        alchemist.setMaximumExpectedValue(address(wstETH), 1000000000e18);
        hevm.stopPrank();
    }

    function testRoundTrip() external {
        deal(address(weth), address(this), 1e18);
        
        uint256 startingBalance = wstETH.balanceOf(address(alchemist));

        SafeERC20.safeApprove(address(weth), address(alchemist), 1e18);
        uint256 shares = alchemist.depositUnderlying(address(wstETH), 1e18, address(this), 0);

        // Test that price function returns value within 0.1% of actual
        uint256 underlyingValue = shares * adapter.price() / 10**SafeERC20.expectDecimals(address(wstETH));
        assertGt(underlyingValue, 1e18 * 9990 / BPS);
        
        uint256 unwrapped = alchemist.withdrawUnderlying(address(wstETH), shares, address(this), shares * 9990 / 10000);

        uint256 endBalance = wstETH.balanceOf(address(alchemist));
        
        assertEq(weth.balanceOf(address(this)), unwrapped);
        assertEq(wstETH.balanceOf(address(this)), 0);
        assertEq(wstETH.balanceOf(address(adapter)), 0);
        assertApproxEq(endBalance - startingBalance, 0, 10);
    }
}