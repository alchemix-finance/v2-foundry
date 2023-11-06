// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {console} from "../../lib/forge-std/src/console.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {PoolAssetManagerUser} from "./utils/users/PoolAssetManagerUser.sol";

import {
    PoolAssetManager,
    PoolAsset,
    SLIPPAGE_PRECISION,
    CURVE_PRECISION,
    InitializationParams as ManagerInitializationParams
} from "../PoolAssetManager.sol";

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
    IAlchemistV2 constant alchemist = IAlchemistV2(0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c);
    ITransmuterBuffer constant transmuterBuffer = ITransmuterBuffer(0xbc2FB245594a68c927C930FBE2d00680A8C90B9e);
    address constant transmuterBufferAdmin = address(0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9);
    IERC20 constant fxs = IERC20(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0);
    IERC20 constant crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IStableSwap2Pool constant twoPool = IStableSwap2Pool(0xB657B895B265C38c53FFF00166cF7F6A3C70587d);
    IConvexToken constant cvx = IConvexToken(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IConvexStakingWrapper constant stakingWrapper = IConvexStakingWrapper(0x8A59781B415288f9E633b948618726CB6E47e980);
    IConvexFraxBooster constant convexFraxBooster = IConvexFraxBooster(0x2B8b301B90Eb8801f1eEFe73285Eec117D2fFC95);
    IConvexFraxFarm constant convexFraxFarm = IConvexFraxFarm(0x56790e4A08eD17aa3b7b4B1b23A6a84D731Fd77e);

    TransmuterV2 transmuter;
    PoolAssetManager manager;
    IERC20 fraxEth;
    IERC20 alEth;
    IERC20 twoPoolToken;

    function setUp() external {
        manager = new PoolAssetManager(ManagerInitializationParams({
            admin:                  address(this),
            operator:               address(this),
            rewardReceiver:         address(0xbeef),
            transmuterBuffer:       address(transmuterBuffer),
            fraxShareToken:         fxs,
            curveToken:             crv,
            twoPool:                twoPool,
            twoPoolSlippage:        SLIPPAGE_PRECISION - 20, // 20 bps, 0.2%
            convexToken:            cvx,
            convexStakingWrapper:   stakingWrapper,
            convexFraxBooster:      convexFraxBooster,
            convexPoolId:           54
        }));

        fraxEth        = manager.getTokenForTwoPoolAsset(PoolAsset.FRXETH);
        alEth          = manager.getTokenForTwoPoolAsset(PoolAsset.ALETH);
        twoPoolToken   = IERC20(address(twoPool));

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
        bytes memory transmuterParams = abi.encodeWithSelector(TransmuterV2.initialize.selector, address(alEth), address(fraxEth), address(transmuterBuffer), address(whitelistFraxTransmuter));
		TransparentUpgradeableProxy fraxTransmuterProxy = new TransparentUpgradeableProxy(address(fraxTransmuterLogic), address(transmuterBufferAdmin), transmuterParams);
        transmuter = TransmuterV2(address(fraxTransmuterProxy));

        hevm.startPrank(address(transmuterBufferAdmin));
        alchemist.addUnderlyingToken(address(fraxEth), underlyingConfig);
        alchemist.setUnderlyingTokenEnabled(address(fraxEth), true);
        transmuterBuffer.registerAsset(address(fraxEth), address(transmuter));
        transmuterBuffer.setAmo(address(fraxEth), address(manager));
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
        PoolAssetManagerUser pendingAdmin = new PoolAssetManagerUser(manager);

        manager.setPendingAdmin(address(pendingAdmin));
        pendingAdmin.acceptAdmin();

        assertEq(manager.pendingAdmin(), address(0));
        assertEq(manager.admin(), address(pendingAdmin));
    }

    function testFailAcceptTimelockNotPendingAdmin() external {
        PoolAssetManagerUser pendingAdmin = new PoolAssetManagerUser(manager);

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

    function testMintTwoPoolTokensMultipleAssets() external {
        deal(address(fraxEth), address(manager), 1e18);
        deal(address(alEth), address(manager), 1e18);

        uint256[2] memory amounts;
        amounts[uint256(PoolAsset.FRXETH)]  = 1e18;
        amounts[uint256(PoolAsset.ALETH)] = 1e18;

        uint256 expectedOutput = 2e18 * CURVE_PRECISION / twoPool.get_virtual_price();
        uint256 minted         = manager.mintTwoPoolTokens(amounts);

        assertEq(fraxEth.balanceOf(address(manager)), 0);
        assertEq(alEth.balanceOf(address(manager)), 0);
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
        deal(address(fraxEth), address(manager), 1e18);

        uint256 expectedOutput = 1e18 * CURVE_PRECISION / twoPool.get_virtual_price();
        uint256 minted         = manager.mintTwoPoolTokens(PoolAsset.FRXETH, 1e18);

        assertEq(fraxEth.balanceOf(address(manager)), 0);
        assertEq(twoPoolToken.balanceOf(address(manager)), minted);
        assertGt(minted, expectedOutput * manager.twoPoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testMintTwoPoolTokensWithFraxEth() external {
        deal(address(fraxEth), address(manager), 1e18);

        uint256 expectedOutput = 1e18 * CURVE_PRECISION / twoPool.get_virtual_price();
        uint256 minted         = manager.mintTwoPoolTokens(PoolAsset.FRXETH, 1e18);

        assertEq(fraxEth.balanceOf(address(manager)), 0);
        assertEq(twoPoolToken.balanceOf(address(manager)), minted);
        assertGt(minted, expectedOutput * manager.twoPoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testMintTwoPoolTokensSingleAssetSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.mintTwoPoolTokens(PoolAsset.FRXETH, 0);
    }

    function testEmergencyRecall() external {
        deal(address(twoPool), address(manager), 100e18);

        deal(address(fraxEth), address(manager), 100e18);

        manager.mintTwoPoolTokens(PoolAsset.FRXETH, 100e18);

        (bool success, bytes32 id) = manager.depositTwoPoolTokens(100e18);
                
        hevm.warp(block.timestamp + 8 days);

        manager.emergencyRecall(1e18, id);
    }

    function testBurnTwoPoolTokensIntoFRAXETH() external {
        deal(address(fraxEth), address(manager), 100e18);

        manager.mintTwoPoolTokens(PoolAsset.FRXETH, 100e18);

        uint256 expectedOutput = 1e18 * twoPool.get_virtual_price() / CURVE_PRECISION;
        console.log(expectedOutput);
        uint256 withdrawn      = manager.burnTwoPoolTokens(PoolAsset.FRXETH, 1e18);

        assertEq(fraxEth.balanceOf(address(manager)), withdrawn);
        assertGt(withdrawn, expectedOutput * manager.twoPoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testBurnTwoPoolTokensIntoALETH() external {
        deal(address(twoPoolToken), address(manager), 1e18);

        uint256 expectedOutput = 1e18 * twoPool.get_virtual_price() / CURVE_PRECISION;
        console.log(expectedOutput);
        uint256 withdrawn      = manager.burnTwoPoolTokens(PoolAsset.ALETH, 1e18);

        assertEq(twoPoolToken.balanceOf(address(manager)), 0);
        assertEq(alEth.balanceOf(address(manager)), withdrawn);
        assertGt(withdrawn, expectedOutput * manager.twoPoolSlippage() / SLIPPAGE_PRECISION);
    }

    function testBurnTwoPoolTokensSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.burnTwoPoolTokens(PoolAsset.FRXETH, 0);
    }

    function testDepositMetaPoolTokens() external {
        deal(address(twoPool), address(manager), 1e18);

        (bool success, bytes32 id) = manager.depositTwoPoolTokens(1e18);
        assertEq(convexFraxFarm.lockedLiquidityOf(address(manager.convexFraxVault())), 1e18);
    }

    function testDepositMetaPoolTokensCustomLock() external {
        deal(address(twoPool), address(manager), 1e18);

        (bool success, bytes32 id) = manager.depositTwoPoolTokensCustomLock(1e18, 9 days);
        assertEq(convexFraxFarm.lockedLiquidityOf(address(manager.convexFraxVault())), 1e18);

        hevm.warp(block.timestamp + 7 days);
        
        hevm.expectRevert("Stake is still locked!");
        manager.withdrawTwoPoolTokens(1e18, id);
    }

    function testDepositMetaPoolTokensMultipleLock() external {
        deal(address(twoPool), address(manager), 2e18);

        (bool success, bytes32 id) = manager.depositTwoPoolTokensCustomLock(1e18, 9 days);

        assertEq(convexFraxFarm.lockedLiquidityOf(address(manager.convexFraxVault())), 1e18);

        hevm.warp(block.timestamp + 7 days);
        
        hevm.expectRevert("Stake is still locked!");
        manager.withdrawTwoPoolTokens(1e18, id);

        (bool success2, bytes32 id2) = manager.depositTwoPoolTokensCustomLock(1e18, 50 days);
        assertEq(convexFraxFarm.lockedLiquidityOf(address(manager.convexFraxVault())), 2e18);

        hevm.warp(block.timestamp + 3 days);

        manager.withdrawTwoPoolTokens(1e18, id);
        assertEq(convexFraxFarm.lockedLiquidityOf(address(manager.convexFraxVault())), 1e18);

        hevm.expectRevert("Stake is still locked!");
        manager.withdrawTwoPoolTokens(1e18, id2);

        hevm.warp(block.timestamp + 53 days);

        manager.withdrawTwoPoolTokens(1e18, id2);
        assertEq(convexFraxFarm.lockedLiquidityOf(address(manager.convexFraxVault())), 0);
    }

    function testDepositMetaPoolTokensSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.depositTwoPoolTokens(0);
    }

    function testWithdrawMetaPoolTokens() external {
        deal(address(twoPool), address(manager), 1e18);

        (bool success, bytes32 id) = manager.depositTwoPoolTokens(1e18);

        hevm.warp(block.timestamp + 8 days);

        assertTrue(manager.withdrawTwoPoolTokens(1e18, id));

        assertEq(convexFraxFarm.lockedLiquidityOf(address(manager.convexFraxVault())), 0);
        assertEq(IERC20(address(twoPool)).balanceOf(address(manager)), 1e18);
    }

    function testWithdrawMetaPoolTokensSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.withdrawTwoPoolTokens(0, bytes32(0));
    }

    function testClaimRewards() external {
        deal(address(twoPool), address(manager), 1e18);

        manager.depositTwoPoolTokens(1e18);

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
        deal(address(fraxEth), address(manager), 1e18);

        uint256[2] memory amounts;
        amounts[uint256(PoolAsset.FRXETH)] = 1e18;

        uint256 minted = manager.flush(amounts);

        assertEq(fraxEth.balanceOf(address(manager)), 0);
        assertEq(convexFraxFarm.lockedLiquidityOf(address(manager.convexFraxVault())), minted);
    }

    function testFlushMultipleAssetsSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.flush(PoolAsset.FRXETH, 1e18);
    }

    function testFlushSingleAsset() external {
        deal(address(fraxEth), address(manager), 1e18);

        manager.setTwoPoolSlippage(0);

        uint256 minted = manager.flush(PoolAsset.FRXETH, 1e18);

        assertEq(fraxEth.balanceOf(address(manager)), 0);
        assertEq(convexFraxFarm.lockedLiquidityOf(address(manager.convexFraxVault())), minted);
    }

    function testFlushSingleAssetSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.flush(PoolAsset.FRXETH, 1e18);
    }

    function testRecall() external {
        deal(address(twoPool), address(manager), 1e18);

        (bool success, bytes32 id) = manager.depositTwoPoolTokens(1e18);

        manager.setTwoPoolSlippage(0);

        hevm.warp(block.timestamp + 7 days);

        uint256 withdrawn = manager.recall(PoolAsset.FRXETH, 1e18, id);

        assertEq(fraxEth.balanceOf(address(manager)), withdrawn);
        assertEq(convexFraxFarm.lockedLiquidityOf(address(manager.convexFraxVault())), 0);
    }

    function testRecallSenderNotOperator() external {
        hevm.prank(address(0xdead));
        expectUnauthorizedError("Not operator");
        manager.recall(PoolAsset.FRXETH, 1e18, bytes32(0));
    }

    function testReclaimTwoPoolAsset() external {
        deal(address(fraxEth), address(manager), 1e18);

        hevm.prank(transmuterBufferAdmin);
        transmuterBuffer.setSource(address(manager), true);

        hevm.expectCall(
            manager.transmuterBuffer(),
            abi.encodeWithSelector(
                IERC20TokenReceiver.onERC20Received.selector,
                address(fraxEth),
                1e18
            )
        );

        manager.reclaimTwoPoolAsset(PoolAsset.FRXETH, 1e18);
    }

    function testFailReclaimTwoPoolAssetSenderNotAdmin() external {
        deal(address(fraxEth), address(manager), 1e18);

        hevm.prank(address(0xdead));
        manager.reclaimTwoPoolAsset(PoolAsset.FRXETH, 1e18);
    }

    function testSweep() external {
        deal(address(fraxEth), address(manager), 1e18);

        manager.sweep(address(fraxEth), 1e18);

        assertEq(fraxEth.balanceOf(address(manager)), 0e18);
        assertEq(fraxEth.balanceOf(manager.admin()), 1e18);
    }

    function testFailSweepSenderNotAdmin() external {
        deal(address(fraxEth), address(manager), 1e18);

        hevm.prank(address(0xdead));
        manager.sweep(address(fraxEth), 1e18);
    }
}

contract MockTransmuterBuffer is IERC20TokenReceiver {
    function onERC20Received(address token, uint256 amount) external { }
}