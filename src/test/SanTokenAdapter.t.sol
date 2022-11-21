// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {
    SanTokenAdapter,
    InitializationParams as AdapterInitializationParams
} from "../adapters/stakedao/SanTokenAdapter.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";
import "../interfaces/external/stakedao/ISanVault.sol";
import "../interfaces/external/stakedao/ISanGaugeToken.sol";

import {ITransmuterBuffer} from "../interfaces/transmuter/ITransmuterBuffer.sol";
import {ICERC20} from "../interfaces/external/compound/ICERC20.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";

contract SanTokenAdapterTest is DSTestPlus {
    uint256 constant BPS = 10000;
    uint256 constant MAX_INT = 2**256 - 1;

    address constant admin = 0x8392F6669292fA56123F71949B52d883aE57e225;
    address constant alchemistUSD = 0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd;
    address constant alUSD = 0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9;
    address constant angleToken = 0x31429d1856aD1377A8A0079410B297e1a9e214c2;
    address constant angleStableMaster = 0x5adDc89785D75C86aB939E9e15bfBBb7Fc086A87;
    address constant curvePool = 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;
    address constant owner = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address constant poolManagerUSDC = 0xe9f183FC656656f1F17af1F2b0dF79b8fF9ad8eD;
    address constant sanUSDC = 0x9C215206Da4bf108aE5aEEf9dA7caD3352A36Dad;
    address constant sdSanUSDC = 0x8881c497f6F5f2CEcD0742c37c6840bcf5234535;
    address constant sdUsdcYieldToken = 0xAC9978DB68E11EbB9Ffdb65F31053A69522B6320;
    address constant stakeDaoToken = 0x73968b9a57c6E53d41345FD57a6E6ae27d6CDB2F;
    address constant transmuterBuffer = 0xbc2FB245594a68c927C930FBE2d00680A8C90B9e;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant whitelistUSD = 0x78537a6CeBa16f412E123a90472C6E0e9A8F1132;

    SanTokenAdapter adapter;

    function setUp() external {
        adapter = new SanTokenAdapter(AdapterInitializationParams({
            alchemist:              alchemistUSD,
            angleToken:             angleToken,
            angleStableMaster:      angleStableMaster,
            parentToken:            sanUSDC,
            poolManager:            poolManagerUSDC,
            stakeDaoToken:          stakeDaoToken,
            sanVault:               sdSanUSDC,
            token:                  sdUsdcYieldToken,
            underlyingToken:        USDC
        }));

        IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(adapter),
            maximumLoss: 1,
            maximumExpectedValue: 1000000 ether,
            creditUnlockBlocks: 7200
        });

        hevm.startPrank(owner);
        IWhitelist(whitelistUSD).add(address(adapter));
        IWhitelist(whitelistUSD).add(address(this));
        IAlchemistV2(alchemistUSD).addYieldToken(sdUsdcYieldToken, ytc);
        IAlchemistV2(alchemistUSD).setYieldTokenEnabled(sdUsdcYieldToken, true);
        hevm.stopPrank();
    }

    function testPrice() external {    
        // Not sure what to test price against other than just copying the logic
        // assertEq(adapter.price(), 0);
    }

    function testRoundTrip() external {
        deal(USDC, address(this), 100e18);

        SafeERC20.safeApprove(address(USDC), address(alchemistUSD), 100e18);
        uint256 wrapped = IAlchemistV2(alchemistUSD).depositUnderlying(sdUsdcYieldToken, 100e18, address(this), 0);

        uint256 underlyingValue = wrapped * adapter.price() / 10**SafeERC20.expectDecimals(sdUsdcYieldToken);
        assertGt(underlyingValue, 1e18 * 9990 / BPS /* 0.1% slippage */);

        uint256 unwrapped = IAlchemistV2(alchemistUSD).withdrawUnderlying(sdUsdcYieldToken, wrapped, address(this), 0);

        assertGt(unwrapped, 1e18 * 9990 / BPS /* 0.1% slippage */);
        assertEq(IERC20(sdUsdcYieldToken).balanceOf(address(this)), 0);
        assertApproxEq(IERC20(sdUsdcYieldToken).balanceOf(address(adapter)), 0, 10);
    }

    function testRewardDistribution() external {
        
    }
}