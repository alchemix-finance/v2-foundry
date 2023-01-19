// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {console} from "../../lib/forge-std/src/console.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {TwoPoolAssetManagerUser} from "./utils/users/TwoPoolAssetManagerUser.sol";

import {
    TwoPoolAssetManager,
    TwoPoolAsset,
    MetaPoolAsset,
    SLIPPAGE_PRECISION,
    CURVE_PRECISION,
    InitializationParams as ManagerInitializationParams
} from "../TwoPoolAssetManager.sol";

import {TransmuterV2} from "../TransmuterV2.sol";
import {Whitelist} from "../utils/Whitelist.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemicToken} from "../interfaces/IAlchemicToken.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {ITransmuterBuffer} from "../interfaces/transmuter/ITransmuterBuffer.sol";
import {IERC20TokenReceiver} from "../interfaces/IERC20TokenReceiver.sol";
import {IConvexFraxBooster} from "../interfaces/external/convex/IConvexFraxBooster.sol";
import {IConvexFraxFarm} from "../interfaces/external/convex/IConvexFraxFarm.sol";
import {IConvexFraxVault} from "../interfaces/external/convex/IConvexFraxVault.sol";
import {IConvexRewards} from "../interfaces/external/convex/IConvexRewards.sol";
import {IConvexStakingWrapper} from "../interfaces/external/convex/IConvexStakingWrapper.sol";
import {IConvexToken} from "../interfaces/external/convex/IConvexToken.sol";
import {IStableMetaPool} from "../interfaces/external/curve/IStableMetaPool.sol";
import {IStableSwap2Pool} from "../interfaces/external/curve/IStableSwap2Pool.sol";

contract TwoPoolAssetManagerTest is DSTestPlus {
    IAlchemistV2 constant alchemist = IAlchemistV2(0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd);
    ITransmuterBuffer constant transmuterBuffer = ITransmuterBuffer(0x1EEd2DbeB9fc23Ab483F447F38F289cA15f79Bac);
    address constant transmuterBufferAdmin = address(0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9);
    IERC20 constant fxs = IERC20(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0);
    IERC20 constant crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IStableSwap2Pool constant twoPool = IStableSwap2Pool(0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2);
    IStableMetaPool constant metaPool =  IStableMetaPool(0xB30dA2376F63De30b42dC055C93fa474F31330A5);
    IConvexToken constant cvx = IConvexToken(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IConvexStakingWrapper constant stakingWrapper = IConvexStakingWrapper(0xBE1C919cA137299715e9c929BC7126Af14f76091);
    IConvexFraxBooster constant convexFraxBooster = IConvexFraxBooster(0x569f5B842B5006eC17Be02B8b94510BA8e79FbCa);
    IConvexFraxFarm constant convexFraxFarm = IConvexFraxFarm(0x711d650Cd10dF656C2c28D375649689f137005fA);

    TransmuterV2 transmuter;
    TwoPoolAssetManager manager;
    IERC20 frax;
    IERC20 usdc;
    IERC20 alUSD;
    IERC20 twoPoolToken;

    function setUp() external {
        manager = new TwoPoolAssetManager(ManagerInitializationParams({
            admin:                  address(this),
            operator:               address(this),
            rewardReceiver:         address(0xbeef),
            transmuterBuffer:       address(transmuterBuffer),
            fraxShareToken:         fxs,
            curveToken:             crv,
            twoPool:                twoPool,
            metaPool:               metaPool,
            twoPoolSlippage:        SLIPPAGE_PRECISION - 20, // 20 bps, 0.2%
            metaPoolSlippage:       SLIPPAGE_PRECISION - 20, // 20 bps, 0.2%
            convexToken:            cvx,
            convexStakingWrapper:   stakingWrapper,
            convexFraxBooster:      convexFraxBooster,
            convexPoolId:           19
        }));

        frax           = manager.getTokenForTwoPoolAsset(TwoPoolAsset.FRAX);
        usdc           = manager.getTokenForTwoPoolAsset(TwoPoolAsset.USDC);
        alUSD          = manager.getTokenForMetaPoolAsset(MetaPoolAsset.ALUSD);
        twoPoolToken  = manager.getTokenForMetaPoolAsset(MetaPoolAsset.TWO_POOL);

        IAlchemistV2AdminActions.UnderlyingTokenConfig memory underlyingConfig = IAlchemistV2AdminActions.UnderlyingTokenConfig({
			repayLimitMinimum: 1,
			repayLimitMaximum: 1000,
			repayLimitBlocks: 10,
			liquidationLimitMinimum: 1,
			liquidationLimitMaximum: 1000,
			liquidationLimitBlocks: 7200
		});


        Whitelist whitelistFraxTransmuter = new Whitelist();
        
        TransmuterV2 fraxTransmuterLogic = new TransmuterV2();
        bytes memory transmuterParams = abi.encodeWithSelector(TransmuterV2.initialize.selector, address(alUSD), address(frax), address(transmuterBuffer), address(whitelistFraxTransmuter));
		TransparentUpgradeableProxy fraxTransmuterProxy = new TransparentUpgradeableProxy(address(fraxTransmuterLogic), address(transmuterBufferAdmin), transmuterParams);
        transmuter = TransmuterV2(address(fraxTransmuterProxy));

        hevm.startPrank(address(transmuterBufferAdmin));
        alchemist.addUnderlyingToken(address(frax), underlyingConfig);
        alchemist.setUnderlyingTokenEnabled(address(frax), true);
        transmuterBuffer.registerAsset(address(frax), address(transmuter));
        transmuterBuffer.setAmo(address(frax), address(manager));
        hevm.stopPrank();
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
        TwoPoolAssetManagerUser pendingAdmin = new TwoPoolAssetManagerUser(manager);

        manager.setPendingAdmin(address(pendingAdmin));
        pendingAdmin.acceptAdmin();

        assertEq(manager.pendingAdmin(), address(0));
        assertEq(manager.admin(), address(pendingAdmin));
    }

    function testFailAcceptTimelockNotPendingAdmin() external {
        TwoPoolAssetManagerUser pendingAdmin = new TwoPoolAssetManagerUser(manager);

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

    function testSetTwoPoolSlippage() external {
        manager.setTwoPoolSlippage(1e4);
        assertEq(manager.twoPoolSlippage(), 1e4);
    }

    function testSetTwoPoolSlippage(uint256 value) external {
        value = bound(value, 0, SLIPPAGE_PRECISION);
        manager.setTwoPoolSlippage(value);

        assertEq(manager.twoPoolSlippage(), value);
    }

    function testFailSetTwoPoolSlippageSenderNotAdmin() external {
        hevm.prank(address(0xdead));
        manager.setTwoPoolSlippage(1e4);
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

    function testMintTwoPoolTokensMultipleAssets() external {
        deal(address(frax), address(manager), 1e18);
        deal(address(usdc), address(manager), 1e6);

        uint256[2] memory amounts;
        amounts[uint256(TwoPoolAsset.FRAX)]  = 1e18;
        amounts[uint256(TwoPoolAsset.USDC)] = 1e6;

        uint256 expectedOutput = 2e18 * CURVE_PRECISION / twoPool.get_virtual_price();
        uint256 minted         = manager.mintTwoPoolTokens(amounts);

        assertEq(frax.balanceOf(address(manager)), 0);
        assertEq(usdc.balanceOf(address(manager)), 0);
        assertEq(twoPoolToken.balanceOf(address(manager)), minted);
        assertGt(minted, expectedOutput * manager.twoPoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testMintTwoPoolTokensMultipleAssetSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");

        uint256[2] memory amounts;
        manager.mintTwoPoolTokens(amounts);
    }

    function testMintTwoPoolTokensWithFRAX() external {
        deal(address(frax), address(manager), 1e18);

        uint256 expectedOutput = 1e18 * CURVE_PRECISION / twoPool.get_virtual_price();
        uint256 minted         = manager.mintTwoPoolTokens(TwoPoolAsset.FRAX, 1e18);

        assertEq(frax.balanceOf(address(manager)), 0);
        assertEq(twoPoolToken.balanceOf(address(manager)), minted);
        assertGt(minted, expectedOutput * manager.twoPoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testMintTwoPoolTokensWithUSDC() external {
        deal(address(usdc), address(manager), 1e6);

        uint256 expectedOutput = 1e18 * CURVE_PRECISION / twoPool.get_virtual_price();
        uint256 minted         = manager.mintTwoPoolTokens(TwoPoolAsset.USDC, 1e6);

        assertEq(usdc.balanceOf(address(manager)), 0);
        assertEq(twoPoolToken.balanceOf(address(manager)), minted);
        assertGt(minted, expectedOutput * manager.twoPoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testMintTwoPoolTokensSingleAssetSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.mintTwoPoolTokens(TwoPoolAsset.FRAX, 0);
    }

    function testBurnTwoPoolTokensIntoFRAX() external {
        deal(address(twoPoolToken), address(manager), 1e18);

        uint256 expectedOutput = 1e18 * twoPool.get_virtual_price() / CURVE_PRECISION;
        uint256 withdrawn      = manager.burnTwoPoolTokens(TwoPoolAsset.FRAX, 1e18);

        assertEq(twoPoolToken.balanceOf(address(manager)), 0);
        assertEq(frax.balanceOf(address(manager)), withdrawn);
        assertGt(withdrawn, expectedOutput * manager.twoPoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testBurnTwoPoolTokensIntoUSDC() external {
        deal(address(twoPoolToken), address(manager), 1e18);

        uint256 expectedOutput = 1e6 * twoPool.get_virtual_price() / CURVE_PRECISION;
        uint256 withdrawn      = manager.burnTwoPoolTokens(TwoPoolAsset.USDC, 1e18);

        assertEq(twoPoolToken.balanceOf(address(manager)), 0);
        assertEq(usdc.balanceOf(address(manager)), withdrawn);
        assertGt(withdrawn, expectedOutput * manager.twoPoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testBurnTwoPoolTokensSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.burnTwoPoolTokens(TwoPoolAsset.FRAX, 0);
    }

    function testMintMetaPoolTokensMultipleAssets() external {
        deal(address(alUSD), address(manager), 1e18);
        deal(address(twoPoolToken), address(manager), 1e18);

        uint256[2] memory amounts;
        amounts[uint256(MetaPoolAsset.ALUSD)]      = 1e18;
        amounts[uint256(MetaPoolAsset.TWO_POOL)] = 1e18;

        uint256 expectedOutput = 2e18 * CURVE_PRECISION / metaPool.get_virtual_price();
        uint256 minted         = manager.mintMetaPoolTokens(amounts);

        assertEq(twoPoolToken.balanceOf(address(manager)), 0);
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
        deal(address(twoPoolToken), address(manager), 1e18);

        uint256 expectedOutput = 1e18 * CURVE_PRECISION / metaPool.get_virtual_price();
        uint256 minted         = manager.mintMetaPoolTokens(MetaPoolAsset.TWO_POOL, 1e18);

        assertEq(twoPoolToken.balanceOf(address(manager)), 0);
        assertEq(metaPool.balanceOf(address(manager)), minted);
        assertGt(minted, expectedOutput * manager.metaPoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testMintMetaPoolTokensSingleAssetSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.mintMetaPoolTokens(MetaPoolAsset.TWO_POOL, 0);
    }

    function testBurnMetaPoolTokens() external {
        deal(address(metaPool), address(manager), 1e18);

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
        deal(address(metaPool), address(manager), 1e18);

        assertTrue(manager.depositMetaPoolTokens(1e18));
        assertEq(convexFraxFarm.lockedLiquidityOf(address(manager.convexFraxVault())), 1e18);
    }

    function testDepositMetaPoolTokensCustomLock() external {
        deal(address(metaPool), address(manager), 1e18);

        assertTrue(manager.depositMetaPoolTokensCustomLock(1e18, 9 days));
        assertEq(convexFraxFarm.lockedLiquidityOf(address(manager.convexFraxVault())), 1e18);

        hevm.warp(block.timestamp + 7 days);
        
        hevm.expectRevert("Stake is still locked!");
        manager.withdrawMetaPoolTokens(1e18);
    }

    function testDepositMetaPoolTokensSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.depositMetaPoolTokens(0);
    }

    function testWithdrawMetaPoolTokens() external {
        deal(address(metaPool), address(manager), 1e18);

        manager.depositMetaPoolTokens(1e18);

        hevm.warp(block.timestamp + 7 days);

        assertTrue(manager.withdrawMetaPoolTokens(1e18));

        assertEq(convexFraxFarm.lockedLiquidityOf(address(manager.convexFraxVault())), 0);
        assertEq(metaPool.balanceOf(address(manager)), 1e18);
    }

    function testWithdrawMetaPoolTokensSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.withdrawMetaPoolTokens(0);
    }

    function testClaimRewards() external {
        deal(address(metaPool), address(manager), 1e18);

        manager.depositMetaPoolTokens(1e18);

        hevm.warp(block.timestamp + 7 days);

        (uint256 earnedFxs, uint256 earnedCurve, uint256 earnedConvex) = manager.claimableRewards();

        assertTrue(manager.claimRewards());
        assertTrue(earnedFxs > 0);
        assertTrue(earnedCurve > 0);
        assertTrue(earnedConvex > 0);
        assertEq(crv.balanceOf(manager.rewardReceiver()), earnedCurve);
        assertEq(cvx.balanceOf(manager.rewardReceiver()), earnedConvex);
    }

    function testClaimRewardsSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.claimRewards();
    }

    function testFlushMultipleAssets() external {
        deal(address(frax), address(manager), 1e18);

        uint256[2] memory amounts;
        amounts[uint256(TwoPoolAsset.FRAX)] = 1e18;

        uint256 minted = manager.flush(amounts);

        assertEq(frax.balanceOf(address(manager)), 0);
        assertEq(metaPool.balanceOf(address(manager)), 0);
        assertEq(convexFraxFarm.lockedLiquidityOf(address(manager.convexFraxVault())), minted);
    }

    function testFlushMultipleAssetsSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.flush(TwoPoolAsset.FRAX, 1e18);
    }

    function testFlushSingleAsset() external {
        deal(address(frax), address(manager), 1e18);

        manager.setTwoPoolSlippage(0);
        manager.setMetaPoolSlippage(0);

        uint256 minted = manager.flush(TwoPoolAsset.FRAX, 1e18);

        assertEq(frax.balanceOf(address(manager)), 0);
        assertEq(metaPool.balanceOf(address(manager)), 0);
        assertEq(convexFraxFarm.lockedLiquidityOf(address(manager.convexFraxVault())), minted);
    }

    function testFlushSingleAssetSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.flush(TwoPoolAsset.FRAX, 1e18);
    }

    function testRecall() external {
        deal(address(metaPool), address(manager), 1e18);

        manager.depositMetaPoolTokens(1e18);

        manager.setTwoPoolSlippage(0);
        manager.setMetaPoolSlippage(0);

        hevm.warp(block.timestamp + 7 days);

        uint256 withdrawn = manager.recall(TwoPoolAsset.FRAX, 1e18);

        assertEq(frax.balanceOf(address(manager)), withdrawn);
        assertEq(metaPool.balanceOf(address(manager)), 0);
        assertEq(convexFraxFarm.lockedLiquidityOf(address(manager.convexFraxVault())), 0);
    }

    function testRecallSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.recall(TwoPoolAsset.FRAX, 1e18);
    }

    function testReclaimTwoPoolAsset() external {
        deal(address(frax), address(manager), 1e18);

        hevm.prank(transmuterBufferAdmin);
        transmuterBuffer.setSource(address(manager), true);

        hevm.expectCall(
            manager.transmuterBuffer(),
            abi.encodeWithSelector(
                IERC20TokenReceiver.onERC20Received.selector,
                address(frax),
                1e18
            )
        );

        manager.reclaimTwoPoolAsset(TwoPoolAsset.FRAX, 1e18);
    }

    function testFailReclaimTwoPoolAssetSenderNotAdmin() external {
        deal(address(frax), address(manager), 1e18);

        hevm.prank(address(0xdead));
        manager.reclaimTwoPoolAsset(TwoPoolAsset.FRAX, 1e18);
    }

    function testSweep() external {
        deal(address(frax), address(manager), 1e18);

        manager.sweep(address(frax), 1e18);

        assertEq(frax.balanceOf(address(manager)), 0e18);
        assertEq(frax.balanceOf(manager.admin()), 1e18);
    }

    function testFailSweepSenderNotAdmin() external {
        deal(address(frax), address(manager), 1e18);

        hevm.prank(address(0xdead));
        manager.sweep(address(frax), 1e18);
    }
}

contract MockTransmuterBuffer is IERC20TokenReceiver {
    function onERC20Received(address token, uint256 amount) external { }
}