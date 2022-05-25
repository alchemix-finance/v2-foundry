// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IllegalArgument, IllegalState, Unauthorized} from "./base/ErrorMessages.sol";
import {Multicall} from "./base/Multicall.sol";
import {MutexLock} from "./base/MutexLock.sol";

import {IERC20TokenReceiver} from "./interfaces/IERC20TokenReceiver.sol";
import {IWETH9} from "./interfaces/external/IWETH9.sol";
import {IConvexBooster} from "./interfaces/external/convex/IConvexBooster.sol";
import {IConvexRewards} from "./interfaces/external/convex/IConvexRewards.sol";
import {IConvexToken} from "./interfaces/external/convex/IConvexToken.sol";

import {
    IEthStableMetaPool,
    N_COINS as NUM_META_COINS
} from "./interfaces/external/curve/IEthStableMetaPool.sol";

import {SafeERC20} from "./libraries/SafeERC20.sol";

/// @notice A struct used to define initialization parameters. This is not included
///         in the contract to prevent naming collisions.
struct InitializationParams {
    address admin;
    address operator;
    address rewardReceiver;
    address transmuterBuffer;
    IWETH9 weth;
    IERC20 curveToken;
    IEthStableMetaPool metaPool;
    uint256 metaPoolSlippage;
    IConvexToken convexToken;
    IConvexBooster convexBooster;
    IConvexRewards convexRewards;
    uint256 convexPoolId;
}

/// @dev The amount of precision that slippage parameters have.
uint256 constant SLIPPAGE_PRECISION = 1e4;

/// @dev The amount of precision that curve pools use for price calculations.
uint256 constant CURVE_PRECISION = 1e18;

/// @notice Enumerations for meta pool assets.
///
/// @dev Do not change the order of these fields.
enum MetaPoolAsset {
    ETH, ALETH
}

/// @title  EthAssetManager
/// @author Alchemix Finance
contract EthAssetManager is Multicall, MutexLock, IERC20TokenReceiver {
    /// @notice Emitted when the admin is updated.
    ///
    /// @param admin The admin.
    event AdminUpdated(address admin);

    /// @notice Emitted when the pending admin is updated.
    ///
    /// @param pendingAdmin The pending admin.
    event PendingAdminUpdated(address pendingAdmin);

    /// @notice Emitted when the operator is updated.
    ///
    /// @param operator The operator.
    event OperatorUpdated(address operator);

    /// @notice Emitted when the reward receiver is updated.
    ///
    /// @param rewardReceiver The reward receiver.
    event RewardReceiverUpdated(address rewardReceiver);

    /// @notice Emitted when the transmuter buffer is updated.
    ///
    /// @param transmuterBuffer The transmuter buffer.
    event TransmuterBufferUpdated(address transmuterBuffer);

    /// @notice Emitted when the meta pool slippage is updated.
    ///
    /// @param metaPoolSlippage The meta pool slippage.
    event MetaPoolSlippageUpdated(uint256 metaPoolSlippage);

    /// @notice Emitted when meta pool tokens are minted.
    ///
    /// @param amounts               The amounts of each meta pool asset used to mint liquidity.
    /// @param mintedThreePoolTokens The amount of meta pool tokens minted.
    event MintMetaPoolTokens(uint256[NUM_META_COINS] amounts, uint256 mintedThreePoolTokens);

    /// @notice Emitted when meta tokens are minted.
    ///
    /// @param asset  The asset used to mint meta pool tokens.
    /// @param amount The amount of the asset used to mint meta pool tokens.
    /// @param minted The amount of meta pool tokens minted.
    event MintMetaPoolTokens(MetaPoolAsset asset, uint256 amount, uint256 minted);

    /// @notice Emitted when meta pool tokens are burned.
    ///
    /// @param asset     The meta pool asset that was received.
    /// @param amount    The amount of meta pool tokens that were burned.
    /// @param withdrawn The amount of the asset that was withdrawn.
    event BurnMetaPoolTokens(MetaPoolAsset asset, uint256 amount, uint256 withdrawn);

    /// @notice Emitted when meta pool tokens are deposited into convex.
    ///
    /// @param amount  The amount of meta pool tokens that were deposited.
    /// @param success If the operation was successful.
    event DepositMetaPoolTokens(uint256 amount, bool success);

    /// @notice Emitted when meta pool tokens are withdrawn from convex.
    ///
    /// @param amount  The amount of meta pool tokens that were withdrawn.
    /// @param success If the operation was successful.
    event WithdrawMetaPoolTokens(uint256 amount, bool success);

    /// @notice Emitted when convex rewards are claimed.
    ///
    /// @param success      If the operation was successful.
    /// @param amountCurve  The amount of curve tokens sent to the reward recipient.
    /// @param amountConvex The amount of convex tokens sent to the reward recipient.
    event ClaimRewards(bool success, uint256 amountCurve, uint256 amountConvex);

    /// @notice Emitted when ethereum is sent to the transmuter buffer.
    ///
    /// @param amount The amount of ethereum that was reclaimed.
    event ReclaimEth(uint256 amount);

    /// @notice Emitted when a token is swept to the admin.
    ///
    /// @param token  The token that was swept.
    /// @param amount The amount of the token that was swept.
    event SweepToken(address token, uint256 amount);

    /// @notice Emitted when ethereum is swept to the admin.
    ///
    /// @param amount The amount of the token that was swept.
    event SweepEth(uint256 amount);

    /// @notice The admin.
    address public admin;

    /// @notice The current pending admin.
    address public pendingAdmin;

    /// @notice The operator.
    address public operator;

    // @notice The reward receiver.
    address public rewardReceiver;

    /// @notice The transmuter buffer.
    address public transmuterBuffer;

    /// @notice The wrapped ethereum token.
    IWETH9 public weth;

    /// @notice The curve token.
    IERC20 public immutable curveToken;

    /// @notice The meta pool contract.
    IEthStableMetaPool public immutable metaPool;

    /// @notice The amount of slippage that will be tolerated when depositing and withdrawing assets
    ///         from the meta pool. In units of basis points.
    uint256 public metaPoolSlippage;

    /// @notice The convex token.
    IConvexToken public immutable convexToken;

    /// @notice The convex booster contract.
    IConvexBooster public immutable convexBooster;

    /// @notice The convex rewards contract.
    IConvexRewards public immutable convexRewards;

    /// @notice The convex pool identifier.
    uint256 public immutable convexPoolId;

    /// @dev A cache of the tokens that the meta pool supports.
    IERC20[NUM_META_COINS] private _metaPoolAssetCache;

    /// @dev A modifier which reverts if the message sender is not the admin.
    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert Unauthorized("Not admin");
        }
        _;
    }

    /// @dev A modifier which reverts if the message sender is not the operator.
    modifier onlyOperator() {
        if (msg.sender != operator) {
            revert Unauthorized("Not operator");
        }
        _;
    }

    constructor(InitializationParams memory params) {
        admin            = params.admin;
        operator         = params.operator;
        rewardReceiver   = params.rewardReceiver;
        transmuterBuffer = params.transmuterBuffer;
        weth             = params.weth;
        curveToken       = params.curveToken;
        metaPool         = params.metaPool;
        metaPoolSlippage = params.metaPoolSlippage;
        convexToken      = params.convexToken;
        convexBooster    = params.convexBooster;
        convexRewards    = params.convexRewards;
        convexPoolId     = params.convexPoolId;

        for (uint256 i = 0; i < NUM_META_COINS; i++) {
            _metaPoolAssetCache[i] = params.metaPool.coins(i);
            if (_metaPoolAssetCache[i] == IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
                _metaPoolAssetCache[i] = weth;
            }
        }

        emit AdminUpdated(admin);
        emit OperatorUpdated(operator);
        emit RewardReceiverUpdated(rewardReceiver);
        emit TransmuterBufferUpdated(transmuterBuffer);
        emit MetaPoolSlippageUpdated(metaPoolSlippage);
    }

    receive() external payable { }

    /// @notice Gets the amount of meta pool tokens that this contract has in reserves.
    ///
    /// @return The reserves.
    function metaPoolReserves() external view returns (uint256) {
        return metaPool.balanceOf(address(this));
    }

    /// @notice Gets the amount of a meta pool asset that this contract has in reserves.
    ///
    /// @param asset The meta pool asset.
    ///
    /// @return The reserves.
    function metaPoolAssetReserves(MetaPoolAsset asset) external view returns (uint256) {
        IERC20 token = getTokenForMetaPoolAsset(asset);
        if (asset == MetaPoolAsset.ETH) {
            return address(this).balance + token.balanceOf(address(this));
        }
        return token.balanceOf(address(this));
    }

    /// @notice Gets the amount of ethereum that one alETH is worth.
    ///
    /// @return The amount of the underlying token.
    function exchangeRate() public view returns (uint256) {
        IERC20 alETH = getTokenForMetaPoolAsset(MetaPoolAsset.ALETH);

        uint256[NUM_META_COINS] memory metaBalances = metaPool.get_balances();
        return metaPool.get_dy(
            int128(uint128(uint256(MetaPoolAsset.ALETH))),
            int128(uint128(uint256(MetaPoolAsset.ETH))),
            10**SafeERC20.expectDecimals(address(alETH)),
            metaBalances
        );
    }

    /// @notice Gets the amount of curve tokens and convex tokens that can be claimed.
    ///
    /// @return amountCurve  The amount of curve tokens available.
    /// @return amountConvex The amount of convex tokens available.
    function claimableRewards() public view returns (uint256 amountCurve, uint256 amountConvex) {
        amountCurve  = convexRewards.earned(address(this));
        amountConvex = _getEarnedConvex(amountCurve);
    }

    /// @notice Gets the ERC20 token associated with a meta pool asset.
    ///
    /// @param asset The asset to get the token for.
    ///
    /// @return The token.
    function getTokenForMetaPoolAsset(MetaPoolAsset asset) public view returns (IERC20) {
        uint256 index = uint256(asset);
        if (index >= NUM_META_COINS) {
            revert IllegalArgument("Asset index out of bounds");
        }
        return _metaPoolAssetCache[index];
    }

    /// @notice Begins the 2-step process of setting the administrator.
    ///
    /// The caller must be the admin. Setting the pending timelock to the zero address will stop
    /// the process of setting a new timelock.
    ///
    /// @param value The value to set the pending timelock to.
    function setPendingAdmin(address value) external onlyAdmin {
        pendingAdmin = value;
        emit PendingAdminUpdated(value);
    }

    /// @notice Completes the 2-step process of setting the administrator.
    ///
    /// The pending admin must be set and the caller must be the pending admin. After this function
    /// is successfully executed, the admin will be set to the pending admin and the pending admin
    /// will be reset.
    function acceptAdmin() external {
        if (pendingAdmin == address(0)) {
            revert IllegalState("Pending admin unset");
        }

        if (pendingAdmin != msg.sender) {
            revert Unauthorized("Not pending admin");
        }

        admin = pendingAdmin;
        pendingAdmin = address(0);

        emit AdminUpdated(admin);
        emit PendingAdminUpdated(address(0));
    }

    /// @notice Sets the operator.
    ///
    /// The caller must be the admin.
    ///
    /// @param value The value to set the admin to.
    function setOperator(address value) external onlyAdmin {
        operator = value;
        emit OperatorUpdated(value);
    }

    /// @notice Sets the reward receiver.
    ///
    /// @param value The value to set the reward receiver to.
    function setRewardReceiver(address value) external onlyAdmin {
        rewardReceiver = value;
        emit RewardReceiverUpdated(value);
    }

    /// @notice Sets the transmuter buffer.
    ///
    /// @param value The value to set the transmuter buffer to.
    function setTransmuterBuffer(address value) external onlyAdmin {
        transmuterBuffer = value;
        emit TransmuterBufferUpdated(value);
    }

    /// @notice Sets the slippage that will be tolerated when depositing and withdrawing meta pool
    ///         assets. The slippage has a resolution of 6 decimals.
    ///
    /// The operator is allowed to set the slippage because it is a volatile parameter that may need
    /// fine adjustment in a short time window.
    ///
    /// @param value The value to set the slippage to.
    function setMetaPoolSlippage(uint256 value) external onlyOperator {
        if (value > SLIPPAGE_PRECISION) {
            revert IllegalArgument("Slippage not in range");
        }
        metaPoolSlippage = value;
        emit MetaPoolSlippageUpdated(value);
    }

    /// @notice Mints meta pool tokens with a combination of assets.
    ///
    /// @param amounts The amounts of the assets to deposit.
    ///
    /// @return minted The number of meta pool tokens minted.
    function mintMetaPoolTokens(
        uint256[NUM_META_COINS] calldata amounts
    ) external lock onlyOperator returns (uint256 minted) {
        return _mintMetaPoolTokens(amounts);
    }

    /// @notice Mints meta pool tokens with an asset.
    ///
    /// @param asset  The asset to deposit into the meta pool.
    /// @param amount The amount of the asset to deposit.
    ///
    /// @return minted The number of meta pool tokens minted.
    function mintMetaPoolTokens(
        MetaPoolAsset asset,
        uint256 amount
    ) external lock onlyOperator returns (uint256 minted) {
        return _mintMetaPoolTokens(asset, amount);
    }

    /// @notice Burns meta pool tokens to withdraw an asset.
    ///
    /// @param asset  The asset to withdraw.
    /// @param amount The amount of meta pool tokens to burn.
    ///
    /// @return withdrawn The amount of the asset withdrawn from the pool.
    function burnMetaPoolTokens(
        MetaPoolAsset asset,
        uint256 amount
    ) external lock onlyOperator returns (uint256 withdrawn) {
        return _burnMetaPoolTokens(asset, amount);
    }

    /// @notice Deposits and stakes meta pool tokens into convex.
    ///
    /// @param amount The amount of meta pool tokens to deposit.
    ///
    /// @return success If the tokens were successfully deposited.
    function depositMetaPoolTokens(
        uint256 amount
    ) external lock onlyOperator returns (bool success) {
        return _depositMetaPoolTokens(amount);
    }

    /// @notice Withdraws and unwraps meta pool tokens from convex.
    ///
    /// @param amount The amount of meta pool tokens to withdraw.
    ///
    /// @return success If the tokens were successfully withdrawn.
    function withdrawMetaPoolTokens(
        uint256 amount
    ) external lock onlyOperator returns (bool success) {
        return _withdrawMetaPoolTokens(amount);
    }

    /// @notice Claims convex, curve, and auxiliary rewards.
    ///
    /// @return success If the claim was successful.
    function claimRewards() external lock onlyOperator returns (bool success) {
        success = convexRewards.getReward();

        uint256 curveBalance  = curveToken.balanceOf(address(this));
        uint256 convexBalance = convexToken.balanceOf(address(this));

        SafeERC20.safeTransfer(address(curveToken), rewardReceiver, curveBalance);
        SafeERC20.safeTransfer(address(convexToken), rewardReceiver, convexBalance);

        emit ClaimRewards(success, curveBalance, convexBalance);
    }

    /// @notice Flushes meta pool assets into convex by minting meta pool tokens using the assets,
    ///         and then depositing the meta pool tokens into convex.
    ///
    /// This function is provided for ease of use.
    ///
    /// @param amounts The amounts of the meta pool assets to flush.
    ///
    /// @return The amount of meta pool tokens deposited into convex.
    function flush(
        uint256[NUM_META_COINS] calldata amounts
    ) external lock onlyOperator returns (uint256) {
        uint256 mintedMetaPoolTokens = _mintMetaPoolTokens(amounts);

        if (!_depositMetaPoolTokens(mintedMetaPoolTokens)) {
            revert IllegalState("Deposit into convex failed");
        }

        return mintedMetaPoolTokens;
    }

    /// @notice Flushes a meta pool asset into convex by minting meta pool tokens using the asset,
    ///         and then depositing the meta pool tokens into convex.
    ///
    /// This function is provided for ease of use.
    ///
    /// @param asset  The meta pool asset to flush.
    /// @param amount The amount of the meta pool asset to flush.
    ///
    /// @return The amount of meta pool tokens deposited into convex.
    function flush(
        MetaPoolAsset asset,
        uint256 amount
    ) external lock onlyOperator returns (uint256) {
        uint256 mintedMetaPoolTokens = _mintMetaPoolTokens(asset, amount);

        if (!_depositMetaPoolTokens(mintedMetaPoolTokens)) {
            revert IllegalState("Deposit into convex failed");
        }

        return mintedMetaPoolTokens;
    }

    /// @notice Recalls ethereum into reserves by withdrawing meta pool tokens from convex and
    ///         burning the meta pool tokens for ethereum.
    ///
    /// This function is provided for ease of use.
    ///
    /// @param amount The amount of the meta pool tokens to withdraw from convex and burn.
    ///
    /// @return The amount of ethereum recalled.
    function recall(uint256 amount) external lock onlyOperator returns (uint256) {
        if (!_withdrawMetaPoolTokens(amount)) {
            revert IllegalState("Withdraw from convex failed");
        }
        return _burnMetaPoolTokens(MetaPoolAsset.ETH, amount);
    }

    /// @notice Reclaims a three pool asset to the transmuter buffer.
    ///
    /// @param amount The amount of ethereum to reclaim.
    function reclaimEth(uint256 amount) public lock onlyAdmin {
        uint256 balance;
        if (amount > (balance = weth.balanceOf(address(this)))) weth.deposit{value: amount - balance}();

        SafeERC20.safeTransfer(address(weth), transmuterBuffer, amount);

        IERC20TokenReceiver(transmuterBuffer).onERC20Received(address(weth), amount);

        emit ReclaimEth(amount);
    }

    /// @notice Sweeps a token out of the contract to the admin.
    ///
    /// @param token  The token to sweep.
    /// @param amount The amount of the token to sweep.
    function sweepToken(address token, uint256 amount) external lock onlyAdmin {
        SafeERC20.safeTransfer(address(token), msg.sender, amount);
        emit SweepToken(token, amount);
    }

    /// @notice Sweeps ethereum out of the contract to the admin.
    ///
    /// @param amount The amount of ethereum to sweep.
    ///
    /// @return result The result from the call to transfer ethereum.
    function sweepEth(
        uint256 amount
    ) external lock onlyAdmin returns (bytes memory result) {
        (bool success, bytes memory result) = admin.call{value: amount}(new bytes(0));
        if (!success) {
            revert IllegalState("Transfer failed");
        }

        emit SweepEth(amount);

        return result;
    }

    /// @inheritdoc IERC20TokenReceiver
    ///
    /// @dev This function is required in order to receive tokens from the conduit.
    function onERC20Received(address token, uint256 value) external { /* noop */ }

    /// @dev Gets the amount of convex that will be minted for an amount of curve tokens.
    ///
    /// @param amountCurve The amount of curve tokens.
    ///
    /// @return The amount of convex tokens.
    function _getEarnedConvex(uint256 amountCurve) internal view returns (uint256) {
        uint256 supply      = convexToken.totalSupply();
        uint256 cliff       = supply / convexToken.reductionPerCliff();
        uint256 totalCliffs = convexToken.totalCliffs();

        if (cliff >= totalCliffs) return 0;

        uint256 reduction = totalCliffs - cliff;
        uint256 earned    = amountCurve * reduction / totalCliffs;

        uint256 available = convexToken.maxSupply() - supply;
        return earned > available ? available : earned;
    }

    /// @dev Mints meta pool tokens with a combination of assets.
    ///
    /// @param amounts The amounts of the assets to deposit.
    ///
    /// @return minted The number of meta pool tokens minted.
    function _mintMetaPoolTokens(
        uint256[NUM_META_COINS] calldata amounts
    ) internal returns (uint256 minted) {
        IERC20[NUM_META_COINS] memory tokens = _metaPoolAssetCache;

        uint256 total = 0;
        for (uint256 i = 0; i < NUM_META_COINS; i++) {
            // Skip over approving WETH since we are directly swapping ETH.
            if (i == uint256(MetaPoolAsset.ETH)) continue;

            if (amounts[i] == 0) continue;

            total += amounts[i];

            // For assets like USDT, the approval must be first set to zero before updating it.
            SafeERC20.safeApprove(address(tokens[i]), address(metaPool), 0);
            SafeERC20.safeApprove(address(tokens[i]), address(metaPool), amounts[i]);
        }

        // Calculate the minimum amount of meta pool tokens that we are expecting out when
        // adding liquidity for all of the assets. This value is based off the optimistic
        // assumption that one of each token is approximately equal to one meta pool token.
        uint256 expectedOutput    = total * CURVE_PRECISION / metaPool.get_virtual_price();
        uint256 minimumMintAmount = expectedOutput * metaPoolSlippage / SLIPPAGE_PRECISION;

        uint256 value = amounts[uint256(MetaPoolAsset.ETH)];

        // Ensure that the contract has the amount of ethereum required.
        if (value > address(this).balance) weth.withdraw(value - address(this).balance);

        // Add the liquidity to the pool.
        minted = metaPool.add_liquidity{value: value}(amounts, minimumMintAmount);

        emit MintMetaPoolTokens(amounts, minted);
    }

    /// @dev Mints meta pool tokens with an asset.
    ///
    /// @param asset  The asset to deposit into the meta pool.
    /// @param amount The amount of the asset to deposit.
    ///
    /// @return minted The number of meta pool tokens minted.
    function _mintMetaPoolTokens(
        MetaPoolAsset asset,
        uint256 amount
    ) internal returns (uint256 minted) {
        uint256[NUM_META_COINS] memory amounts;
        amounts[uint256(asset)] = amount;

        // Calculate the minimum amount of meta pool tokens that we are expecting out when
        // adding liquidity for all of the assets. This value is based off the optimistic
        // assumption that one of each token is approximately equal to one meta pool token.
        uint256 minimumMintAmount = amount * metaPoolSlippage / SLIPPAGE_PRECISION;

        // Set an approval if not working with ethereum.
        if (asset != MetaPoolAsset.ETH) {
            IERC20 token = getTokenForMetaPoolAsset(asset);

            // For assets like USDT, the approval must be first set to zero before updating it.
            SafeERC20.safeApprove(address(token), address(metaPool), 0);
            SafeERC20.safeApprove(address(token), address(metaPool), amount);
        }

        uint256 value = asset == MetaPoolAsset.ETH
            ? amounts[uint256(MetaPoolAsset.ETH)]
            : 0;

        // Ensure that the contract has the amount of ethereum required.
        if (value > address(this).balance) weth.withdraw(value - address(this).balance);

        // Add the liquidity to the pool.
        minted = metaPool.add_liquidity{value: value}(amounts, minimumMintAmount);

        emit MintMetaPoolTokens(asset, amount, minted);
    }

    /// @dev Burns meta pool tokens to withdraw an asset.
    ///
    /// @param asset  The asset to withdraw.
    /// @param amount The amount of meta pool tokens to burn.
    ///
    /// @return withdrawn The amount of the asset withdrawn from the pool.
    function _burnMetaPoolTokens(
        MetaPoolAsset asset,
        uint256 amount
    ) internal returns (uint256 withdrawn) {
        uint256 index = uint256(asset);

        // Calculate the minimum amount of the meta pool asset that we are expecting out when
        // removing single sided liquidity. This value is based off the optimistic assumption that
        // one of each token is approximately equal to one meta pool lp token.
        uint256 expectedOutput   = amount * metaPool.get_virtual_price() / CURVE_PRECISION;
        uint256 minimumAmountOut = expectedOutput * metaPoolSlippage / SLIPPAGE_PRECISION;

        // Remove the liquidity from the pool.
        withdrawn = metaPool.remove_liquidity_one_coin(
            amount,
            int128(uint128(index)),
            minimumAmountOut
        );

        emit BurnMetaPoolTokens(asset, amount, withdrawn);
    }

    /// @dev Deposits and stakes meta pool tokens into convex.
    ///
    /// @param amount The amount of meta pool tokens to deposit.
    ///
    /// @return success If the tokens were successfully deposited.
    function _depositMetaPoolTokens(uint256 amount) internal returns (bool success) {
        SafeERC20.safeApprove(address(metaPool), address(convexBooster), 0);
        SafeERC20.safeApprove(address(metaPool), address(convexBooster), amount);

        success = convexBooster.deposit(convexPoolId, amount, true /* always stake into rewards */);

        emit DepositMetaPoolTokens(amount, success);
    }

    /// @dev Withdraws and unwraps meta pool tokens from convex.
    ///
    /// @param amount The amount of meta pool tokens to withdraw.
    ///
    /// @return success If the tokens were successfully withdrawn.
    function _withdrawMetaPoolTokens(uint256 amount) internal returns (bool success) {
        success = convexRewards.withdrawAndUnwrap(amount, false /* never claim */);
        emit WithdrawMetaPoolTokens(amount, success);
    }

    /// @dev Claims convex, curve, and auxiliary rewards.
    ///
    /// @return success If the claim was successful.
    function _claimRewards() internal returns (bool success) {
        success = convexRewards.getReward();

        uint256 curveBalance  = curveToken.balanceOf(address(this));
        uint256 convexBalance = convexToken.balanceOf(address(this));

        SafeERC20.safeTransfer(address(curveToken), rewardReceiver, curveBalance);
        SafeERC20.safeTransfer(address(convexToken), rewardReceiver, convexBalance);

        emit ClaimRewards(success, curveBalance, convexBalance);
    }

    /// @dev Gets the minimum of two integers.
    ///
    /// @param x The first integer.
    /// @param y The second integer.
    ///
    /// @return The minimum value.
    function min(uint256 x , uint256 y) private pure returns (uint256) {
        return x > y ? y : x;
    }

    /// @dev Gets the absolute value of the difference of two integers.
    ///
    /// @param x The first integer.
    /// @param y The second integer.
    ///
    /// @return The absolute value.
    function abs(uint256 x , uint256 y) private pure returns (uint256) {
        return x > y ? x - y : y - x;
    }
}
