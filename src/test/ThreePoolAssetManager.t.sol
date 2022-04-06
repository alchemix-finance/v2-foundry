// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {stdCheats} from "forge-std/stdlib.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {ThreePoolAssetManagerUser} from "./utils/users/ThreePoolAssetManagerUser.sol";

import {
    ThreePoolAssetManager,
    ThreePoolAsset,
    MetaPoolAsset,
    SLIPPAGE_PRECISION,
    CURVE_PRECISION,
    InitializationParams as ManagerInitializationParams
} from "../ThreePoolAssetManager.sol";

import {IERC20TokenReceiver} from "../interfaces/IERC20TokenReceiver.sol";
import {IConvexBooster} from "../interfaces/external/convex/IConvexBooster.sol";
import {IConvexRewards} from "../interfaces/external/convex/IConvexRewards.sol";
import {IConvexToken} from "../interfaces/external/convex/IConvexToken.sol";
import {IStableMetaPool} from "../interfaces/external/curve/IStableMetaPool.sol";
import {IStableSwap3Pool} from "../interfaces/external/curve/IStableSwap3Pool.sol";

contract ThreePoolAssetManagerTest is DSTestPlus, stdCheats {
    IERC20 constant crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IStableSwap3Pool constant threePool = IStableSwap3Pool(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
    IStableMetaPool constant metaPool =  IStableMetaPool(0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c);
    IConvexToken constant cvx = IConvexToken(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IConvexBooster constant convexBooster = IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    IConvexRewards constant convexRewards = IConvexRewards(0x02E2151D4F351881017ABdF2DD2b51150841d5B3);

    ThreePoolAssetManager manager;
    IERC20 dai;
    IERC20 usdc;
    IERC20 usdt;
    IERC20 alUSD;
    IERC20 threePoolToken;

    function setUp() external {
        MockTransmuterBuffer transmuterBuffer = new MockTransmuterBuffer();

        manager = new ThreePoolAssetManager(ManagerInitializationParams({
            admin:             address(this),
            operator:          address(this),
            rewardReceiver:    address(0xbeef),
            transmuterBuffer:  address(transmuterBuffer),
            curveToken:        crv,
            threePool:         threePool,
            metaPool:          metaPool,
            threePoolSlippage: SLIPPAGE_PRECISION - 30, // 30 bps, 0.3%
            metaPoolSlippage:  SLIPPAGE_PRECISION - 30, // 30 bps, 0.3%
            convexToken:       cvx,
            convexBooster:     convexBooster,
            convexRewards:     convexRewards,
            convexPoolId:      36
        }));

        dai            = manager.getTokenForThreePoolAsset(ThreePoolAsset.DAI);
        usdc           = manager.getTokenForThreePoolAsset(ThreePoolAsset.USDC);
        usdt           = manager.getTokenForThreePoolAsset(ThreePoolAsset.USDT);
        alUSD          = manager.getTokenForMetaPoolAsset(MetaPoolAsset.ALUSD);
        threePoolToken = manager.getTokenForMetaPoolAsset(MetaPoolAsset.THREE_POOL);
    }

    function testCalculateRebalanceAlUSD() external {
        tip(address(alUSD), address(manager), type(uint96).max);
        tip(address(metaPool), address(manager), type(uint96).max);

        (uint256 delta, bool add) = manager.calculateRebalance(
            MetaPoolAsset.ALUSD,
            ThreePoolAsset.DAI,
            1.0e18
        );

        if (add) {
            manager.mintMetaPoolTokens(MetaPoolAsset.ALUSD, delta);
        } else {
            uint256[2] memory amounts;
            amounts[uint256(MetaPoolAsset.ALUSD)] = delta;

            uint256 burnAmount = metaPool.calc_token_amount(amounts, false);
            manager.burnMetaPoolTokens(MetaPoolAsset.ALUSD, burnAmount);
        }

        assertApproxEq(1.0e18, manager.exchangeRate(ThreePoolAsset.DAI), 0.0001e18);
    }

    function testCalculateRebalance3Pool() external {
        tip(address(threePoolToken), address(manager), type(uint96).max);
        tip(address(metaPool), address(manager), type(uint96).max);

        (uint256 delta, bool add) = manager.calculateRebalance(
            MetaPoolAsset.THREE_POOL,
            ThreePoolAsset.DAI,
            1.0e18
        );

        if (add) {
            manager.mintMetaPoolTokens(MetaPoolAsset.THREE_POOL, delta);
        } else {
            uint256[2] memory amounts;
            amounts[uint256(MetaPoolAsset.THREE_POOL)] = delta;

            uint256 burnAmount = metaPool.calc_token_amount(amounts, false);
            manager.burnMetaPoolTokens(MetaPoolAsset.THREE_POOL, burnAmount);
        }

        assertApproxEq(1.0e18, manager.exchangeRate(ThreePoolAsset.DAI), 0.0001e18);
    }

    function testSetPendingAdmin() external {
        manager.setPendingAdmin(address(0xdead));
        assertEq(manager.pendingAdmin(), address(0xdead));
    }

    function testFailSetPendingAdminSenderNotAdmin() external {
        hevm.prank(address(0xdead));
        manager.setPendingAdmin(address(0xbeef));
    }

    function testAcceptAdmin() external {
        ThreePoolAssetManagerUser pendingAdmin = new ThreePoolAssetManagerUser(manager);

        manager.setPendingAdmin(address(pendingAdmin));
        pendingAdmin.acceptAdmin();

        assertEq(manager.pendingAdmin(), address(0));
        assertEq(manager.admin(), address(pendingAdmin));
    }

    function testFailAcceptTimelockNotPendingAdmin() external {
        ThreePoolAssetManagerUser pendingAdmin = new ThreePoolAssetManagerUser(manager);

        manager.setPendingAdmin(address(pendingAdmin));

        hevm.prank(address(0xdead));
        manager.acceptAdmin();
    }

    function testFailAcceptAdminPendingAdminUnset() external {
        manager.acceptAdmin();
    }

    function testSetRewardReceiver() external {
        manager.setRewardReceiver(address(0xdead));
        assertEq(manager.rewardReceiver(), address(0xdead));
    }

    function testFailSetRewardReceiverSenderNotAdmin() external {
        hevm.prank(address(0xdead));
        manager.setRewardReceiver(address(0xbeef));
    }

    function testSetTransmuterBuffer() external {
        manager.setTransmuterBuffer(address(0xdead));
        assertEq(manager.transmuterBuffer(), address(0xdead));
    }

    function testFailSetTransmuterBufferSenderNotAdmin() external {
        hevm.prank(address(0xdead));
        manager.setTransmuterBuffer(address(0xbeef));
    }

    function testSetThreePoolSlippage() external {
        manager.setThreePoolSlippage(1e4);
        assertEq(manager.threePoolSlippage(), 1e4);
    }

    function testSetThreePoolSlippage(uint256 value) external {
        value = bound(value, 0, SLIPPAGE_PRECISION);
        manager.setThreePoolSlippage(value);

        assertEq(manager.threePoolSlippage(), value);
    }

    function testFailSetThreePoolSlippageSenderNotAdmin() external {
        hevm.prank(address(0xdead));
        manager.setThreePoolSlippage(1e4);
    }

    function testSetMetaPoolSlippage() external {
        manager.setMetaPoolSlippage(1e4);
        assertEq(manager.metaPoolSlippage(), 1e4);
    }

    function testSetMetaPoolSlippage(uint256 value) external {
        value = bound(value, 0, SLIPPAGE_PRECISION);
        manager.setMetaPoolSlippage(value);

        assertEq(manager.metaPoolSlippage(), value);
    }

    function testFailSetMetaPoolSlippageSenderNotAdmin() external {
        hevm.prank(address(0xdead));
        manager.setMetaPoolSlippage(1e4);
    }

    function testMintThreePoolTokensMultipleAssets() external {
        tip(address(dai), address(manager), 1e18);

        uint256[3] memory amounts;
        amounts[uint256(ThreePoolAsset.DAI)] = 1e18;

        uint256 expectedOutput = 1e18 * CURVE_PRECISION / threePool.get_virtual_price();
        uint256 minted         = manager.mintThreePoolTokens(amounts);

        assertEq(dai.balanceOf(address(manager)), 0);
        assertEq(threePoolToken.balanceOf(address(manager)), minted);
        assertGt(minted, expectedOutput * manager.threePoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testMintThreePoolTokensMultipleAssetSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");

        uint256[3] memory amounts;
        manager.mintThreePoolTokens(amounts);
    }

    function testMintThreePoolTokensSingleAsset() external {
        tip(address(dai), address(manager), 1e18);

        uint256 expectedOutput = 1e18 * CURVE_PRECISION / threePool.get_virtual_price();
        uint256 minted         = manager.mintThreePoolTokens(ThreePoolAsset.DAI, 1e18);

        assertEq(dai.balanceOf(address(manager)), 0);
        assertEq(threePoolToken.balanceOf(address(manager)), minted);
        assertGt(minted, expectedOutput * manager.threePoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testMintThreePoolTokensSingleAssetSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.mintThreePoolTokens(ThreePoolAsset.DAI, 0);
    }

    function testBurnThreePoolTokens() external {
        tip(address(threePoolToken), address(manager), 1e18);

        uint256 expectedOutput = 1e18 * threePool.get_virtual_price() / CURVE_PRECISION;
        uint256 withdrawn      = manager.burnThreePoolTokens(ThreePoolAsset.DAI, 1e18);

        assertEq(threePoolToken.balanceOf(address(manager)), 0);
        assertEq(dai.balanceOf(address(manager)), withdrawn);
        assertGt(withdrawn, expectedOutput * manager.threePoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testBurnThreePoolTokensSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.burnThreePoolTokens(ThreePoolAsset.DAI, 0);
    }

    function testMintMetaPoolTokensMultipleAssets() external {
        tip(address(threePoolToken), address(manager), 1e18);

        uint256[2] memory amounts;
        amounts[uint256(MetaPoolAsset.THREE_POOL)] = 1e18;

        uint256 expectedOutput = 1e18 * CURVE_PRECISION / metaPool.get_virtual_price();
        uint256 minted         = manager.mintMetaPoolTokens(amounts);

        assertEq(threePoolToken.balanceOf(address(manager)), 0);
        assertEq(metaPool.balanceOf(address(manager)), minted);
        assertGt(minted, expectedOutput * manager.metaPoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testMintMetaPoolTokensMultipleAssetsSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");

        uint256[2] memory amounts;
        manager.mintMetaPoolTokens(amounts);
    }

    function testMintMetaPoolTokensSingleAsset() external {
        tip(address(threePoolToken), address(manager), 1e18);

        uint256 expectedOutput = 1e18 * CURVE_PRECISION / metaPool.get_virtual_price();
        uint256 minted         = manager.mintMetaPoolTokens(MetaPoolAsset.THREE_POOL, 1e18);

        assertEq(threePoolToken.balanceOf(address(manager)), 0);
        assertEq(metaPool.balanceOf(address(manager)), minted);
        assertGt(minted, expectedOutput * manager.metaPoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testMintMetaPoolTokensSingleAssetSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.mintMetaPoolTokens(MetaPoolAsset.THREE_POOL, 0);
    }

    function testBurnMetaPoolTokens() external {
        tip(address(metaPool), address(manager), 1e18);

        uint256 expectedOutput = 1e18 * metaPool.get_virtual_price() / CURVE_PRECISION;
        uint256 withdrawn      = manager.burnMetaPoolTokens(MetaPoolAsset.ALUSD, 1e18);

        assertEq(metaPool.balanceOf(address(manager)), 0);
        assertEq(alUSD.balanceOf(address(manager)), withdrawn);
        assertGt(withdrawn, expectedOutput * manager.metaPoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testBurnMetaPoolTokensSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.burnMetaPoolTokens(MetaPoolAsset.ALUSD, 0);
    }

    function testDepositMetaPoolTokens() external {
        tip(address(metaPool), address(manager), 1e18);

        assertTrue(manager.depositMetaPoolTokens(1e18));
        assertEq(convexRewards.balanceOf(address(manager)), 1e18);
    }

    function testDepositMetaPoolTokensSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.depositMetaPoolTokens(0);
    }

    function testWithdrawMetaPoolTokens() external {
        tip(address(metaPool), address(manager), 1e18);

        manager.depositMetaPoolTokens(1e18);

        assertTrue(manager.withdrawMetaPoolTokens(1e18));

        assertEq(convexRewards.balanceOf(address(manager)), 0);
        assertEq(metaPool.balanceOf(address(manager)), 1e18);
    }

    function testWithdrawMetaPoolTokensSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.withdrawMetaPoolTokens(0);
    }

    function testClaimRewards() external {
        tip(address(metaPool), address(manager), 1e18);

        manager.depositMetaPoolTokens(1e18);

        hevm.warp(block.timestamp + 86400);

        (uint256 earnedCurve, uint256 earnedConvex) = manager.claimableRewards();

        assertTrue(manager.claimRewards());
        assertEq(crv.balanceOf(manager.rewardReceiver()), earnedCurve);
        assertEq(cvx.balanceOf(manager.rewardReceiver()), earnedConvex);
    }

    function testClaimRewardsSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.claimRewards();
    }

    function testFlushMultipleAssets() external {
        tip(address(dai), address(manager), 1e18);

        uint256[3] memory amounts;
        amounts[uint256(ThreePoolAsset.DAI)] = 1e18;

        uint256 minted = manager.flush(amounts);

        assertEq(dai.balanceOf(address(manager)), 0);
        assertEq(metaPool.balanceOf(address(manager)), 0);
        assertEq(convexRewards.balanceOf(address(manager)), minted);
    }

    function testFlushMultipleAssetsSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.flush(ThreePoolAsset.DAI, 1e18);
    }

    function testFlushSingleAsset() external {
        tip(address(dai), address(manager), 1e18);

        manager.setThreePoolSlippage(0);
        manager.setMetaPoolSlippage(0);

        uint256 minted = manager.flush(ThreePoolAsset.DAI, 1e18);

        assertEq(dai.balanceOf(address(manager)), 0);
        assertEq(metaPool.balanceOf(address(manager)), 0);
        assertEq(convexRewards.balanceOf(address(manager)), minted);
    }

    function testFlushSingleAssetSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.flush(ThreePoolAsset.DAI, 1e18);
    }

    function testRecall() external {
        tip(address(metaPool), address(manager), 1e18);

        manager.depositMetaPoolTokens(1e18);

        manager.setThreePoolSlippage(0);
        manager.setMetaPoolSlippage(0);

        uint256 withdrawn = manager.recall(ThreePoolAsset.DAI, 1e18);

        assertEq(dai.balanceOf(address(manager)), withdrawn);
        assertEq(metaPool.balanceOf(address(manager)), 0);
        assertEq(convexRewards.balanceOf(address(manager)), 0);
    }

    function testRecallSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.recall(ThreePoolAsset.DAI, 1e18);
    }

    function testReclaimThreePoolAsset() external {
        tip(address(dai), address(manager), 1e18);

        hevm.expectCall(
            manager.transmuterBuffer(),
            abi.encodeWithSelector(
                IERC20TokenReceiver.onERC20Received.selector,
                address(dai),
                1e18
            )
        );

        manager.reclaimThreePoolAsset(ThreePoolAsset.DAI, 1e18);

        assertEq(dai.balanceOf(address(manager)), 0);
        assertEq(dai.balanceOf(manager.transmuterBuffer()), 1e18);
    }

    function testFailReclaimThreePoolAssetSenderNotAdmin() external {
        tip(address(dai), address(manager), 1e18);

        hevm.prank(address(0xdead));
        manager.reclaimThreePoolAsset(ThreePoolAsset.DAI, 1e18);
    }

    function testSweep() external {
        tip(address(dai), address(manager), 1e18);

        manager.sweep(address(dai), 1e18);

        assertEq(dai.balanceOf(address(manager)), 0e18);
        assertEq(dai.balanceOf(manager.admin()), 1e18);
    }

    function testFailSweepSenderNotAdmin() external {
        tip(address(dai), address(manager), 1e18);

        hevm.prank(address(0xdead));
        manager.sweep(address(dai), 1e18);
    }
}

contract MockTransmuterBuffer is IERC20TokenReceiver {
    function onERC20Received(address token, uint256 amount) external { }
}