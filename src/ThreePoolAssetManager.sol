// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import { IERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { IllegalArgument, IllegalState, Unauthorized } from "./base/ErrorMessages.sol";
import { Multicall } from "./base/Multicall.sol";
import { MutexLock } from "./base/MutexLock.sol";

import { IERC20TokenReceiver } from "./interfaces/IERC20TokenReceiver.sol";
import { IConvexBooster } from "./interfaces/external/convex/IConvexBooster.sol";
import { IConvexRewards } from "./interfaces/external/convex/IConvexRewards.sol";
import { IConvexToken } from "./interfaces/external/convex/IConvexToken.sol";

import { IStableMetaPool, N_COINS as NUM_META_COINS } from "./interfaces/external/curve/IStableMetaPool.sol";

import { IStableSwap3Pool, N_COINS as NUM_STABLE_COINS } from "./interfaces/external/curve/IStableSwap3Pool.sol";

import { SafeERC20 } from "./libraries/SafeERC20.sol";

/// @notice A struct used to define initialization parameters. This is not included
///         in the contract to prevent naming collisions.
struct InitializationParams {
	address admin;
	address operator;
	address rewardReceiver;
	address transmuterBuffer;
	IERC20 curveToken;
	IStableSwap3Pool threePool;
	IStableMetaPool metaPool;
	uint256 threePoolSlippage;
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

/// @notice Enumerations for 3pool assets.
///
/// @dev Do not change the order of these fields.
enum ThreePoolAsset {
	DAI,
	USDC,
	USDT
}

/// @notice Enumerations for meta pool assets.
///
/// @dev Do not change the order of these fields.
enum MetaPoolAsset {
	ALUSD,
	THREE_POOL
}

/// @title  ThreePoolAssetManager
/// @author Alchemix Finance
contract ThreePoolAssetManager is Multicall, MutexLock, IERC20TokenReceiver {
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

	/// @notice Emitted when the 3pool slippage is updated.
	///
	/// @param threePoolSlippage The 3pool slippage.
	event ThreePoolSlippageUpdated(uint256 threePoolSlippage);

	/// @notice Emitted when the meta pool slippage is updated.
	///
	/// @param metaPoolSlippage The meta pool slippage.
	event MetaPoolSlippageUpdated(uint256 metaPoolSlippage);

	/// @notice Emitted when 3pool tokens are minted.
	///
	/// @param amounts               The amounts of each 3pool asset used to mint liquidity.
	/// @param mintedThreePoolTokens The amount of 3pool tokens minted.
	event MintThreePoolTokens(uint256[NUM_STABLE_COINS] amounts, uint256 mintedThreePoolTokens);

	/// @notice Emitted when 3pool tokens are minted.
	///
	/// @param asset                 The 3pool asset used to mint 3pool tokens.
	/// @param amount                The amount of the asset used to mint 3pool tokens.
	/// @param mintedThreePoolTokens The amount of 3pool tokens minted.
	event MintThreePoolTokens(ThreePoolAsset asset, uint256 amount, uint256 mintedThreePoolTokens);

	/// @notice Emitted when 3pool tokens are burned.
	///
	/// @param asset     The 3pool asset that was received.
	/// @param amount    The amount of 3pool tokens that were burned.
	/// @param withdrawn The amount of the 3pool asset that was withdrawn.
	event BurnThreePoolTokens(ThreePoolAsset asset, uint256 amount, uint256 withdrawn);

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

	/// @notice Emitted when 3pool assets are sent to the transmuter buffer.
	///
	/// @param asset  The 3pool asset that was reclaimed.
	/// @param amount The amount of the asset that was reclaimed.
	event ReclaimThreePoolAsset(ThreePoolAsset asset, uint256 amount);

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

	/// @notice The curve token.
	IERC20 public immutable curveToken;

	/// @notice The 3pool contract.
	IStableSwap3Pool public immutable threePool;

	/// @notice The meta pool contract.
	IStableMetaPool public immutable metaPool;

	/// @notice The amount of slippage that will be tolerated when depositing and withdrawing assets
	///         from the stable swap pool. In units of basis points.
	uint256 public threePoolSlippage;

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

	/// @dev A cache of the tokens that the stable swap pool supports.
	IERC20[NUM_STABLE_COINS] private _threePoolAssetCache;

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
		admin = params.admin;
		operator = params.operator;
		rewardReceiver = params.rewardReceiver;
		transmuterBuffer = params.transmuterBuffer;
		curveToken = params.curveToken;
		threePool = params.threePool;
		metaPool = params.metaPool;
		threePoolSlippage = params.threePoolSlippage;
		metaPoolSlippage = params.metaPoolSlippage;
		convexToken = params.convexToken;
		convexBooster = params.convexBooster;
		convexRewards = params.convexRewards;
		convexPoolId = params.convexPoolId;

		for (uint256 i = 0; i < NUM_STABLE_COINS; i++) {
			_threePoolAssetCache[i] = params.threePool.coins(i);
		}

		for (uint256 i = 0; i < NUM_META_COINS; i++) {
			_metaPoolAssetCache[i] = params.metaPool.coins(i);
		}

		emit AdminUpdated(admin);
		emit OperatorUpdated(operator);
		emit RewardReceiverUpdated(rewardReceiver);
		emit TransmuterBufferUpdated(transmuterBuffer);
		emit ThreePoolSlippageUpdated(threePoolSlippage);
		emit MetaPoolSlippageUpdated(metaPoolSlippage);
	}

	/// @notice Gets the amount of meta pool tokens that this contract has in reserves.
	///
	/// @return The reserves.
	function metaPoolReserves() external view returns (uint256) {
		return metaPool.balanceOf(address(this));
	}

	/// @notice Gets the amount of a 3pool asset that this contract has in reserves.
	///
	/// @param asset The 3pool asset.
	///
	/// @return The reserves.
	function threePoolAssetReserves(ThreePoolAsset asset) external view returns (uint256) {
		IERC20 token = getTokenForThreePoolAsset(asset);
		return token.balanceOf(address(this));
	}

	/// @notice Gets the amount of a meta pool asset that this contract has in reserves.
	///
	/// @param asset The meta pool asset.
	///
	/// @return The reserves.
	function metaPoolAssetReserves(MetaPoolAsset asset) external view returns (uint256) {
		IERC20 token = getTokenForMetaPoolAsset(asset);
		return token.balanceOf(address(this));
	}

	/// @notice Gets the amount of a 3pool asset that one alUSD is worth.
	///
	/// @param asset The 3pool asset.
	///
	/// @return The amount of the underying.
	function exchangeRate(ThreePoolAsset asset) public view returns (uint256) {
		IERC20 alUSD = getTokenForMetaPoolAsset(MetaPoolAsset.ALUSD);

		uint256[NUM_META_COINS] memory metaBalances = metaPool.get_balances();
		uint256 amountThreePool = metaPool.get_dy(
			int128(uint128(uint256(MetaPoolAsset.ALUSD))),
			int128(uint128(uint256(MetaPoolAsset.THREE_POOL))),
			10**SafeERC20.expectDecimals(address(alUSD)),
			metaBalances
		);

		return threePool.calc_withdraw_one_coin(amountThreePool, int128(uint128(uint256(asset))));
	}

	/// @dev Struct used to declare local variables for the calculate rebalance function.
	struct CalculateRebalanceLocalVars {
		uint256 minimum;
		uint256 maximum;
		uint256 minimumDistance;
		uint256 minimizedBalance;
		uint256 startingBalance;
	}

	/// @notice Calculates how much alUSD or 3pool needs to be added or removed from the metapool
	///         to reach a target exchange rate for a specified 3pool asset.
	///
	/// @param rebalanceAsset      The meta pool asset to use to rebalance the pool.
	/// @param targetExchangeAsset The 3pool asset to balance the price relative to.
	/// @param targetExchangeRate  The target exchange rate.
	///
	/// @return delta The amount of alUSD or 3pool that needs to be added or removed from the pool.
	/// @return add   If the alUSD or 3pool needs to be removed or added.
	function calculateRebalance(
		MetaPoolAsset rebalanceAsset,
		ThreePoolAsset targetExchangeAsset,
		uint256 targetExchangeRate
	) public view returns (uint256 delta, bool add) {
		uint256 decimals;
		{
			IERC20 alUSD = getTokenForMetaPoolAsset(MetaPoolAsset.ALUSD);
			decimals = SafeERC20.expectDecimals(address(alUSD));
		}

		uint256[NUM_META_COINS] memory startingBalances = metaPool.get_balances();
		uint256[NUM_META_COINS] memory currentBalances = [startingBalances[0], startingBalances[1]];

		CalculateRebalanceLocalVars memory v;
		v.minimum = 0;
		v.maximum = type(uint96).max;
		v.minimumDistance = type(uint256).max;
		v.minimizedBalance = type(uint256).max;
		v.startingBalance = startingBalances[uint256(rebalanceAsset)];

		uint256 previousBalance;

		for (uint256 i = 0; i < 256; i++) {
			uint256 examineBalance;
			if ((examineBalance = (v.maximum + v.minimum) / 2) == previousBalance) break;

			currentBalances[uint256(rebalanceAsset)] = examineBalance;

			uint256 amountThreePool = metaPool.get_dy(
				int128(uint128(uint256(MetaPoolAsset.ALUSD))),
				int128(uint128(uint256(MetaPoolAsset.THREE_POOL))),
				10**decimals,
				currentBalances
			);

			uint256 exchangeRate = threePool.calc_withdraw_one_coin(
				amountThreePool,
				int128(uint128(uint256(targetExchangeAsset)))
			);

			uint256 distance = abs(exchangeRate, targetExchangeRate);

			if (distance < v.minimumDistance) {
				v.minimumDistance = distance;
				v.minimizedBalance = examineBalance;
			} else if (distance == v.minimumDistance) {
				uint256 examineDelta = abs(examineBalance, v.startingBalance);
				uint256 currentDelta = abs(v.minimizedBalance, v.startingBalance);
				v.minimizedBalance = currentDelta > examineDelta ? examineBalance : v.minimizedBalance;
			}

			if (exchangeRate > targetExchangeRate) {
				if (rebalanceAsset == MetaPoolAsset.ALUSD) {
					v.minimum = examineBalance;
				} else {
					v.maximum = examineBalance;
				}
			} else {
				if (rebalanceAsset == MetaPoolAsset.ALUSD) {
					v.maximum = examineBalance;
				} else {
					v.minimum = examineBalance;
				}
			}

			previousBalance = examineBalance;
		}

		return
			v.minimizedBalance > v.startingBalance
				? (v.minimizedBalance - v.startingBalance, true)
				: (v.startingBalance - v.minimizedBalance, false);
	}

	/// @notice Gets the amount of curve tokens and convex tokens that can be claimed.
	///
	/// @return amountCurve  The amount of curve tokens available.
	/// @return amountConvex The amount of convex tokens available.
	function claimableRewards() public view returns (uint256 amountCurve, uint256 amountConvex) {
		amountCurve = convexRewards.earned(address(this));
		amountConvex = _getEarnedConvex(amountCurve);
	}

	/// @notice Gets the ERC20 token associated with a 3pool asset.
	///
	/// @param asset The asset to get the token for.
	///
	/// @return The token.
	function getTokenForThreePoolAsset(ThreePoolAsset asset) public view returns (IERC20) {
		uint256 index = uint256(asset);
		if (index >= NUM_STABLE_COINS) {
			revert IllegalArgument("Asset index out of bounds");
		}
		return _threePoolAssetCache[index];
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

	/// @notice Sets the slippage that will be tolerated when depositing and withdrawing 3pool
	///         assets. The slippage has a resolution of 6 decimals.
	///
	/// The operator is allowed to set the slippage because it is a volatile parameter that may need
	/// fine adjustment in a short time window.
	///
	/// @param value The value to set the slippage to.
	function setThreePoolSlippage(uint256 value) external onlyOperator {
		if (value > SLIPPAGE_PRECISION) {
			revert IllegalArgument("Slippage not in range");
		}
		threePoolSlippage = value;
		emit ThreePoolSlippageUpdated(value);
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

	/// @notice Mints 3pool tokens with a combination of assets.
	///
	/// @param amounts The amounts of the assets to deposit.
	///
	/// @return minted The number of 3pool tokens minted.
	function mintThreePoolTokens(uint256[NUM_STABLE_COINS] calldata amounts)
		external
		lock
		onlyOperator
		returns (uint256 minted)
	{
		return _mintThreePoolTokens(amounts);
	}

	/// @notice Mints 3pool tokens with an asset.
	///
	/// @param asset  The asset to deposit into the 3pool.
	/// @param amount The amount of the asset to deposit.
	///
	/// @return minted The number of 3pool tokens minted.
	function mintThreePoolTokens(ThreePoolAsset asset, uint256 amount)
		external
		lock
		onlyOperator
		returns (uint256 minted)
	{
		return _mintThreePoolTokens(asset, amount);
	}

	/// @notice Burns 3pool tokens to withdraw an asset.
	///
	/// @param asset  The asset to withdraw.
	/// @param amount The amount of 3pool tokens to burn.
	///
	/// @return withdrawn The amount of the asset withdrawn from the pool.
	function burnThreePoolTokens(ThreePoolAsset asset, uint256 amount)
		external
		lock
		onlyOperator
		returns (uint256 withdrawn)
	{
		return _burnThreePoolTokens(asset, amount);
	}

	/// @notice Mints meta pool tokens with a combination of assets.
	///
	/// @param amounts The amounts of the assets to deposit.
	///
	/// @return minted The number of meta pool tokens minted.
	function mintMetaPoolTokens(uint256[NUM_META_COINS] calldata amounts)
		external
		lock
		onlyOperator
		returns (uint256 minted)
	{
		return _mintMetaPoolTokens(amounts);
	}

	/// @notice Mints meta pool tokens with an asset.
	///
	/// @param asset  The asset to deposit into the meta pool.
	/// @param amount The amount of the asset to deposit.
	///
	/// @return minted The number of meta pool tokens minted.
	function mintMetaPoolTokens(MetaPoolAsset asset, uint256 amount)
		external
		lock
		onlyOperator
		returns (uint256 minted)
	{
		return _mintMetaPoolTokens(asset, amount);
	}

	/// @notice Burns meta pool tokens to withdraw an asset.
	///
	/// @param asset  The asset to withdraw.
	/// @param amount The amount of meta pool tokens to burn.
	///
	/// @return withdrawn The amount of the asset withdrawn from the pool.
	function burnMetaPoolTokens(MetaPoolAsset asset, uint256 amount)
		external
		lock
		onlyOperator
		returns (uint256 withdrawn)
	{
		return _burnMetaPoolTokens(asset, amount);
	}

	/// @notice Deposits and stakes meta pool tokens into convex.
	///
	/// @param amount The amount of meta pool tokens to deposit.
	///
	/// @return success If the tokens were successfully deposited.
	function depositMetaPoolTokens(uint256 amount) external lock onlyOperator returns (bool success) {
		return _depositMetaPoolTokens(amount);
	}

	/// @notice Withdraws and unwraps meta pool tokens from convex.
	///
	/// @param amount The amount of meta pool tokens to withdraw.
	///
	/// @return success If the tokens were successfully withdrawn.
	function withdrawMetaPoolTokens(uint256 amount) external lock onlyOperator returns (bool success) {
		return _withdrawMetaPoolTokens(amount);
	}

	/// @notice Claims convex, curve, and auxiliary rewards.
	///
	/// @return success If the claim was successful.
	function claimRewards() external lock onlyOperator returns (bool success) {
		success = convexRewards.getReward();

		uint256 curveBalance = curveToken.balanceOf(address(this));
		uint256 convexBalance = convexToken.balanceOf(address(this));

		SafeERC20.safeTransfer(address(curveToken), rewardReceiver, curveBalance);
		SafeERC20.safeTransfer(address(convexToken), rewardReceiver, convexBalance);

		emit ClaimRewards(success, curveBalance, convexBalance);
	}

	/// @notice Flushes three pool assets into convex by minting 3pool tokens from the assets,
	///         minting meta pool tokens using the 3pool tokens, and then depositing the meta pool
	///         tokens into convex.
	///
	/// This function is provided for ease of use.
	///
	/// @param amounts The amounts of the 3pool assets to flush.
	///
	/// @return The amount of meta pool tokens deposited into convex.
	function flush(uint256[NUM_STABLE_COINS] calldata amounts) external lock onlyOperator returns (uint256) {
		uint256 mintedThreePoolTokens = _mintThreePoolTokens(amounts);

		uint256 mintedMetaPoolTokens = _mintMetaPoolTokens(MetaPoolAsset.THREE_POOL, mintedThreePoolTokens);

		if (!_depositMetaPoolTokens(mintedMetaPoolTokens)) {
			revert IllegalState("Deposit into convex failed");
		}

		return mintedMetaPoolTokens;
	}

	/// @notice Flushes a three pool asset into convex by minting 3pool tokens using the asset,
	///         minting meta pool tokens using the 3pool tokens, and then depositing the meta pool
	///         tokens into convex.
	///
	/// This function is provided for ease of use.
	///
	/// @param asset  The 3pool asset to flush.
	/// @param amount The amount of the 3pool asset to flush.
	///
	/// @return The amount of meta pool tokens deposited into convex.
	function flush(ThreePoolAsset asset, uint256 amount) external lock onlyOperator returns (uint256) {
		uint256 mintedThreePoolTokens = _mintThreePoolTokens(asset, amount);

		uint256 mintedMetaPoolTokens = _mintMetaPoolTokens(MetaPoolAsset.THREE_POOL, mintedThreePoolTokens);

		if (!_depositMetaPoolTokens(mintedMetaPoolTokens)) {
			revert IllegalState("Deposit into convex failed");
		}

		return mintedMetaPoolTokens;
	}

	/// @notice Recalls a three pool asset into reserves by withdrawing meta pool tokens from
	///         convex, burning the meta pool tokens for 3pool tokens, and then burning the 3pool
	///         tokens for an asset.
	///
	/// This function is provided for ease of use.
	///
	/// @param asset  The 3pool asset to recall.
	/// @param amount The amount of the meta pool tokens to withdraw from convex and burn.
	///
	/// @return The amount of the 3pool asset recalled.
	function recall(ThreePoolAsset asset, uint256 amount) external lock onlyOperator returns (uint256) {
		if (!_withdrawMetaPoolTokens(amount)) {
			revert IllegalState("Withdraw from convex failed");
		}
		uint256 withdrawnThreePoolTokens = _burnMetaPoolTokens(MetaPoolAsset.THREE_POOL, amount);
		return _burnThreePoolTokens(asset, withdrawnThreePoolTokens);
	}

	/// @notice Reclaims a three pool asset to the transmuter buffer.
	///
	/// @param asset  The 3pool asset to reclaim.
	/// @param amount The amount to reclaim.
	function reclaimThreePoolAsset(ThreePoolAsset asset, uint256 amount) public lock onlyAdmin {
		IERC20 token = getTokenForThreePoolAsset(asset);
		SafeERC20.safeTransfer(address(token), transmuterBuffer, amount);

		IERC20TokenReceiver(transmuterBuffer).onERC20Received(address(token), amount);

		emit ReclaimThreePoolAsset(asset, amount);
	}

	/// @notice Sweeps a token out of the contract to the admin.
	///
	/// @param token  The token to sweep.
	/// @param amount The amount of the token to sweep.
	function sweep(address token, uint256 amount) external lock onlyAdmin {
		SafeERC20.safeTransfer(address(token), msg.sender, amount);
	}

	/// @inheritdoc IERC20TokenReceiver
	///
	/// @dev This function is required in order to receive tokens from the conduit.
	function onERC20Received(address token, uint256 value) external {
		/* noop */
	}

	/// @dev Gets the amount of convex that will be minted for an amount of curve tokens.
	///
	/// @param amountCurve The amount of curve tokens.
	///
	/// @return The amount of convex tokens.
	function _getEarnedConvex(uint256 amountCurve) internal view returns (uint256) {
		uint256 supply = convexToken.totalSupply();
		uint256 cliff = supply / convexToken.reductionPerCliff();
		uint256 totalCliffs = convexToken.totalCliffs();

		if (cliff >= totalCliffs) return 0;

		uint256 reduction = totalCliffs - cliff;
		uint256 earned = (amountCurve * reduction) / totalCliffs;

		uint256 available = convexToken.maxSupply() - supply;
		return earned > available ? available : earned;
	}

	/// @dev Mints 3pool tokens with a combination of assets.
	///
	/// @param amounts The amounts of the assets to deposit.
	///
	/// @return minted The number of 3pool tokens minted.
	function _mintThreePoolTokens(uint256[NUM_STABLE_COINS] calldata amounts) internal returns (uint256 minted) {
		IERC20[NUM_STABLE_COINS] memory tokens = _threePoolAssetCache;

		IERC20 threePoolToken = getTokenForMetaPoolAsset(MetaPoolAsset.THREE_POOL);

		uint256 threePoolDecimals = SafeERC20.expectDecimals(address(threePoolToken));
		uint256 normalizedTotal = 0;

		for (uint256 i = 0; i < NUM_STABLE_COINS; i++) {
			if (amounts[i] == 0) continue;

			uint256 tokenDecimals = SafeERC20.expectDecimals(address(tokens[i]));
			uint256 missingDecimals = threePoolDecimals - tokenDecimals;

			normalizedTotal += amounts[i] * 10**missingDecimals;

			// For assets like USDT, the approval must be first set to zero before updating it.
			SafeERC20.safeApprove(address(tokens[i]), address(threePool), 0);
			SafeERC20.safeApprove(address(tokens[i]), address(threePool), amounts[i]);
		}

		// Calculate what the normalized value of the tokens is.
		uint256 expectedOutput = (normalizedTotal * CURVE_PRECISION) / threePool.get_virtual_price();

		// Calculate the minimum amount of 3pool lp tokens that we are expecting out when
		// adding liquidity for all of the assets. This value is based off the optimistic
		// assumption that one of each token is approximately equal to one 3pool lp token.
		uint256 minimumMintAmount = (expectedOutput * threePoolSlippage) / SLIPPAGE_PRECISION;

		// Record the amount of 3pool lp tokens that we start with before adding liquidity
		// so that we can determine how many we minted.
		uint256 startingBalance = threePoolToken.balanceOf(address(this));

		// Add the liquidity to the pool.
		threePool.add_liquidity(amounts, minimumMintAmount);

		// Calculate how many 3pool lp tokens were minted.
		minted = threePoolToken.balanceOf(address(this)) - startingBalance;

		emit MintThreePoolTokens(amounts, minted);
	}

	/// @dev Mints 3pool tokens with an asset.
	///
	/// @param asset  The asset to deposit into the 3pool.
	/// @param amount The amount of the asset to deposit.
	///
	/// @return minted The number of 3pool tokens minted.
	function _mintThreePoolTokens(ThreePoolAsset asset, uint256 amount) internal returns (uint256 minted) {
		IERC20 token = getTokenForThreePoolAsset(asset);
		IERC20 threePoolToken = getTokenForMetaPoolAsset(MetaPoolAsset.THREE_POOL);

		uint256 threePoolDecimals = SafeERC20.expectDecimals(address(threePoolToken));
		uint256 missingDecimals = threePoolDecimals - SafeERC20.expectDecimals(address(token));

		uint256[NUM_STABLE_COINS] memory amounts;
		amounts[uint256(asset)] = amount;

		// Calculate the minimum amount of 3pool lp tokens that we are expecting out when
		// adding single sided liquidity. This value is based off the optimistic assumption that
		// one of each token is approximately equal to one 3pool lp token.
		uint256 normalizedAmount = amount * 10**missingDecimals;
		uint256 expectedOutput = (normalizedAmount * CURVE_PRECISION) / threePool.get_virtual_price();
		uint256 minimumMintAmount = (expectedOutput * threePoolSlippage) / SLIPPAGE_PRECISION;

		// Record the amount of 3pool lp tokens that we start with before adding liquidity
		// so that we can determine how many we minted.
		uint256 startingBalance = threePoolToken.balanceOf(address(this));

		// For assets like USDT, the approval must be first set to zero before updating it.
		SafeERC20.safeApprove(address(token), address(threePool), 0);
		SafeERC20.safeApprove(address(token), address(threePool), amount);

		// Add the liquidity to the pool.
		threePool.add_liquidity(amounts, minimumMintAmount);

		// Calculate how many 3pool lp tokens were minted.
		minted = threePoolToken.balanceOf(address(this)) - startingBalance;

		emit MintThreePoolTokens(asset, amount, minted);
	}

	/// @dev Burns 3pool tokens to withdraw an asset.
	///
	/// @param asset  The asset to withdraw.
	/// @param amount The amount of 3pool tokens to burn.
	///
	/// @return withdrawn The amount of the asset withdrawn from the pool.
	function _burnThreePoolTokens(ThreePoolAsset asset, uint256 amount) internal returns (uint256 withdrawn) {
		IERC20 token = getTokenForThreePoolAsset(asset);
		IERC20 threePoolToken = getTokenForMetaPoolAsset(MetaPoolAsset.THREE_POOL);

		uint256 index = uint256(asset);

		uint256 threePoolDecimals = SafeERC20.expectDecimals(address(threePoolToken));
		uint256 missingDecimals = threePoolDecimals - SafeERC20.expectDecimals(address(token));

		// Calculate the minimum amount of underlying tokens that we are expecting out when
		// removing single sided liquidity. This value is based off the optimistic assumption that
		// one of each token is approximately equal to one 3pool lp token.
		uint256 normalizedAmount = (amount * threePoolSlippage) / SLIPPAGE_PRECISION;
		uint256 expectedOutput = (normalizedAmount * threePool.get_virtual_price()) / CURVE_PRECISION;
		uint256 minimumAmountOut = expectedOutput / 10**missingDecimals;

		// Record the amount of underlying tokens that we start with before removing liquidity
		// so that we can determine how many we withdrew from the pool.
		uint256 startingBalance = token.balanceOf(address(this));

		SafeERC20.safeApprove(address(threePoolToken), address(threePool), 0);
		SafeERC20.safeApprove(address(threePoolToken), address(threePool), amount);

		// Remove the liquidity from the pool.
		threePool.remove_liquidity_one_coin(amount, int128(uint128(index)), minimumAmountOut);

		// Calculate how many underlying tokens that were withdrawn.
		withdrawn = token.balanceOf(address(this)) - startingBalance;

		emit BurnThreePoolTokens(asset, amount, withdrawn);
	}

	/// @dev Mints meta pool tokens with a combination of assets.
	///
	/// @param amounts The amounts of the assets to deposit.
	///
	/// @return minted The number of meta pool tokens minted.
	function _mintMetaPoolTokens(uint256[NUM_META_COINS] calldata amounts) internal returns (uint256 minted) {
		IERC20[NUM_META_COINS] memory tokens = _metaPoolAssetCache;

		uint256 total = 0;
		for (uint256 i = 0; i < NUM_META_COINS; i++) {
			if (amounts[i] == 0) continue;

			total += amounts[i];

			// For assets like USDT, the approval must be first set to zero before updating it.
			SafeERC20.safeApprove(address(tokens[i]), address(metaPool), 0);
			SafeERC20.safeApprove(address(tokens[i]), address(metaPool), amounts[i]);
		}

		// Calculate the minimum amount of 3pool lp tokens that we are expecting out when
		// adding liquidity for all of the assets. This value is based off the optimistic
		// assumption that one of each token is approximately equal to one 3pool lp token.
		uint256 expectedOutput = (total * CURVE_PRECISION) / metaPool.get_virtual_price();
		uint256 minimumMintAmount = (expectedOutput * metaPoolSlippage) / SLIPPAGE_PRECISION;

		// Add the liquidity to the pool.
		minted = metaPool.add_liquidity(amounts, minimumMintAmount);

		emit MintMetaPoolTokens(amounts, minted);
	}

	/// @dev Mints meta pool tokens with an asset.
	///
	/// @param asset  The asset to deposit into the meta pool.
	/// @param amount The amount of the asset to deposit.
	///
	/// @return minted The number of meta pool tokens minted.
	function _mintMetaPoolTokens(MetaPoolAsset asset, uint256 amount) internal returns (uint256 minted) {
		IERC20 token = getTokenForMetaPoolAsset(asset);

		uint256[NUM_META_COINS] memory amounts;
		amounts[uint256(asset)] = amount;

		// Calculate the minimum amount of 3pool lp tokens that we are expecting out when
		// adding single sided liquidity. This value is based off the optimistic assumption that
		uint256 minimumMintAmount = (amount * metaPoolSlippage) / SLIPPAGE_PRECISION;

		// For assets like USDT, the approval must be first set to zero before updating it.
		SafeERC20.safeApprove(address(token), address(metaPool), 0);
		SafeERC20.safeApprove(address(token), address(metaPool), amount);

		// Add the liquidity to the pool.
		minted = metaPool.add_liquidity(amounts, minimumMintAmount);

		emit MintMetaPoolTokens(asset, amount, minted);
	}

	/// @dev Burns meta pool tokens to withdraw an asset.
	///
	/// @param asset  The asset to withdraw.
	/// @param amount The amount of meta pool tokens to burn.
	///
	/// @return withdrawn The amount of the asset withdrawn from the pool.
	function _burnMetaPoolTokens(MetaPoolAsset asset, uint256 amount) internal returns (uint256 withdrawn) {
		uint256 index = uint256(asset);

		// Calculate the minimum amount of the meta pool asset that we are expecting out when
		// removing single sided liquidity. This value is based off the optimistic assumption that
		// one of each token is approximately equal to one meta pool lp token.
		uint256 expectedOutput = (amount * metaPool.get_virtual_price()) / CURVE_PRECISION;
		uint256 minimumAmountOut = (expectedOutput * metaPoolSlippage) / SLIPPAGE_PRECISION;

		// Remove the liquidity from the pool.
		withdrawn = metaPool.remove_liquidity_one_coin(amount, int128(uint128(index)), minimumAmountOut);

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

		success = convexBooster.deposit(
			convexPoolId,
			amount,
			true /* always stake into rewards */
		);

		emit DepositMetaPoolTokens(amount, success);
	}

	/// @dev Withdraws and unwraps meta pool tokens from convex.
	///
	/// @param amount The amount of meta pool tokens to withdraw.
	///
	/// @return success If the tokens were successfully withdrawn.
	function _withdrawMetaPoolTokens(uint256 amount) internal returns (bool success) {
		success = convexRewards.withdrawAndUnwrap(
			amount,
			false /* never claim */
		);
		emit WithdrawMetaPoolTokens(amount, success);
	}

	/// @dev Claims convex, curve, and auxiliary rewards.
	///
	/// @return success If the claim was successful.
	function _claimRewards() internal returns (bool success) {
		success = convexRewards.getReward();

		uint256 curveBalance = curveToken.balanceOf(address(this));
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
	function min(uint256 x, uint256 y) private pure returns (uint256) {
		return x > y ? y : x;
	}

	/// @dev Gets the absolute value of the difference of two integers.
	///
	/// @param x The first integer.
	/// @param y The second integer.
	///
	/// @return The absolute value.
	function abs(uint256 x, uint256 y) private pure returns (uint256) {
		return x > y ? x - y : y - x;
	}
}
