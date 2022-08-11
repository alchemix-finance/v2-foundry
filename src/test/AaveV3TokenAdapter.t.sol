// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {
    AaveV3Adapter,
    InitializationParams as AdapterInitializationParams
} from "../adapters/aaveV3/AaveV3Adapter.sol";

import {IAaveV3Pool} from "../interfaces/external/aave/IAaveV3Pool.sol";
import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {SafeERC20} from "../libraries/SafeERC20.sol";
import {TokenUtils} from "../libraries/TokenUtils.sol";
import {console} from "../../lib/forge-std/src/console.sol";

contract AaveV3TokenAdapterTest is DSTestPlus {
    uint256 constant BPS = 10000;
    address constant dai = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // Optimism DAI
    address constant daiPool = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant aOptDAI = 0x82E64f49Ed5EC1bC6e43DAD4FC8Af9bb3A2312EE;
    address constant aaveOracle = 0xD81eb3728a631871a7eBBaD631b5f424909f0c77;
    IAaveV3Pool lendingPool = IAaveV3Pool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
    AaveV3Adapter adapter;
    // address alchemistAlUSD = 0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd;
    // address alchemistAlETH = 0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c;
    // address alchemistAdmin = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    // address alchemistAlUSDWhitelist = 0x78537a6CeBa16f412E123a90472C6E0e9A8F1132;
    // address alchemistAlETHWhitelist = 0xA3dfCcbad1333DC69997Da28C961FF8B2879e653;

    function setUp() external {
        adapter = new AaveV3Adapter(AdapterInitializationParams({
            alchemist:          address(this),
            token:              aOptDAI,
            underlyingToken:    dai,
            pool:               daiPool,
            oracle:             aaveOracle
        }));
    }

    function testRoundTrip() external {
        uint256 depositAmount = 1e18;

        deal(dai, address(this), depositAmount);

        SafeERC20.safeApprove(dai, address(adapter), depositAmount);
        uint256 wrapped = adapter.wrap(depositAmount, address(this));
        assertGe(depositAmount, wrapped);
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));
        
        assertEq(IERC20(dai).balanceOf(address(0xbeef)), unwrapped);
        assertEq(IERC20(aOptDAI).balanceOf(address(this)), 0);
        assertEq(IERC20(aOptDAI).balanceOf(address(adapter)), 0);
    }

    function testRoundTripFuzz(uint256 amount) external {
        hevm.assume(
            amount >= 10**SafeERC20.expectDecimals(dai) && 
            amount < 1000000000e18
        );
        
        deal(dai, address(this), amount);

        SafeERC20.safeApprove(dai, address(adapter), amount);
        uint256 wrapped = adapter.wrap(amount, address(this));
        assertEq(amount, wrapped);
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));
        
        assertApproxEq(IERC20(dai).balanceOf(address(0xbeef)), unwrapped, 10000);
        assertEq(IERC20(aOptDAI).balanceOf(address(this)), 0);
        assertEq(IERC20(aOptDAI).balanceOf(address(adapter)), 0);
    }

    function testAppreciation() external {
        deal(dai, address(this), 1e18);

        SafeERC20.safeApprove(dai, address(adapter), 1e18);
        uint256 wrapped = adapter.wrap(1e18, address(this));
        
        hevm.roll(block.number + 1000);
        hevm.warp(block.timestamp + 100000);

        // type(uint256).max will cause aave to withdraw using all shares that have accumulated
        // Not sure how to approve this so for now will just measure balance
        uint256 accruedShares = IERC20(aOptDAI).balanceOf(address(this));
        SafeERC20.safeApprove(adapter.token(), address(adapter), accruedShares);
        uint256 unwrapped = adapter.unwrap(accruedShares, address(0xbeef));
        assertGt(unwrapped, 1e18);
    }
}