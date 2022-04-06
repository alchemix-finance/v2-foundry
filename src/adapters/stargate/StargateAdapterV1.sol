// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";

import {
    IllegalArgument,
    IllegalState,
    Unauthorized
} from "../../base/Errors.sol";

import {Mutex} from "../../base/Mutex.sol";

import {SafeERC20} from "../../libraries/SafeERC20.sol";

import {ITokenAdapter} from "../../interfaces/ITokenAdapter.sol";
import {IStableSwapGeneric} from "../../interfaces/external/curve/IStableSwapGeneric.sol";
import {ILPStaking} from "../../interfaces/external/stargate/ILPStaking.sol";
import {IStargateRouter} from "../../interfaces/external/stargate/IStargateRouter.sol";

struct InitializationParams {
    address alchemist;
    address token;
    address underlyingToken;
    address stargateRouter;
    uint256 stargatePoolId;
    address stargatePool;
}

contract StargateAdapterV1 is ITokenAdapter, Mutex, ERC20 {
    string public override version = "1.0.0";

    address public immutable alchemist;
    address public immutable override underlyingToken;
    address public immutable override stargateToken;
    address public immutable override stargateRouter;
    uint256 public immutable override stargateLiquidityPoolId;
    address public immutable override stargatePool;
    address public immutable override stargateStaking;
    uint256 public immutable override stargateStakingPoolId;
    CurvePoolParams[] swapPath;

    constructor(InitializationParams memory params) ERC20("x", "y") {
        alchemist               = params.alchemist;
        underlyingToken         = params.underlyingToken;
        stargateRouter          = params.stargateRouter;
        stargateLiquidityPoolId = params.stargatePoolId;
        stargatePool            = params.stargatePool;
    }

    modifier onlyAdmin() {
        _;
    }

    modifier onlyKeeper() {
        _;
    }

    /// @dev Checks that the message sender is the alchemist that the adapter is bound to.
    modifier onlyAlchemist() {
        if (msg.sender != alchemist) {
            revert Unauthorized("Not alchemist");
        }
        _;
    }

    /// @inheritdoc ITokenAdapter
    function token() external view returns (address) { return address(this); }

    /// @inheritdoc ITokenAdapter
    function price() external view returns (uint256) {
        return _totalAssets() * 10**decimals() / totalSupply;
    }

    /// @inheritdoc ITokenAdapter
    function wrap(
        uint256 amount,
        address recipient
    ) external onlyAlchemist returns (uint256) {
        // Calculate how many shares to mint to the recipient. We do this preemptively before the
        // transfer so that the calculations are correct.
        uint256 shares = totalSupply != 0
            ? amount * _totalAssets() / totalSupply
            : amount;

        // Mint the shares to the recipient.
        _mint(recipient, shares);

        // Transfer the underlying token from the message sender.
        SafeERC20.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);

        return shares;
    }

    // @inheritdoc ITokenAdapter
    function unwrap(
        uint256 amount,
        address recipient
    ) external lock onlyAlchemist returns (uint256) {
        // Calculate how much the shares are worth.
        uint256 value = totalSupply != 0
            ? amount * totalSupply / _totalAssets()
            : amount;

        // Check if we need to liquidate liquidity tokens.
        uint256 underlyingTokenReserves = IERC20(underlyingToken).balanceOf(address(this));
        if (underlyingTokenReserves < value) {
            // Calculate how many liquidity tokens that need to be liquidated.
            uint256 liquidateAmount = _liquidityTokensToUnderlying(value - underlyingTokenReserves);

            // Pull liquidity tokens from the staking contract if needed.
            uint256 liquidityTokenReserves = IERC20(stargatePool).balanceOf(address(this));
            if (liquidityTokenReserves < liquidateAmount) {
                ILPStaking(stargateStaking).withdraw(
                    stargateStakingPoolId,
                    liquidityTokenReserves - liquidateAmount
                );
            }

            // Redeem the liquidity tokens for the underlying token.
            IStargateRouter(stargatePool).instantRedeemLocal(
                stargateLiquidityPoolId,
                liquidateAmount
            );
        }

        // Transfer the tokens to the recipient.
        SafeERC20.safeTransfer(underlyingToken, recipient, value);

        return value;
    }

    /// @notice Flushes the underlying token to the staking contract.
    ///
    /// @param amount The amount of the underlying token to wrap and then flush to the staking
    ///               contract.
    /// @param all    A flag indicating that all of the liquidity token reserves should be flushed
    ///               to the staking contract.
    function flush(uint256 amount, bool all) external lock onlyKeeper {
        // Wrap the underlying token into the liquidity token. Reset approval to zero for
        // compatability with tokens like USDT.
        SafeERC20.safeApprove(underlyingToken, address(stargateRouter), 0);
        SafeERC20.safeApprove(underlyingToken, address(stargateRouter), amount);

        uint256 startingBalance = IERC20(stargatePool).balanceOf(address(this));
        IStargateRouter(stargateRouter).addLiquidity(
            stargateLiquidityPoolId,
            amount,
            address(this)
        );

        uint256 endingBalance = IERC20(stargatePool).balanceOf(address(this));

        uint256 mintedAmount = endingBalance - startingBalance;
        uint256 flushAmount  = all ? IERC20(stargatePool).balanceOf(address(this)) : mintedAmount;

        // Stake the minted tokens and any tokens that are currently held in reserves.
        ILPStaking(stargateStaking).deposit(
            stargateStakingPoolId,
            flushAmount
        );
    }

    /// @notice Exchanges stargate tokens for the underlying asset.
    ///
    /// @param amount           The amount of the stargate token to harvest.
    /// @param minimumAmountOut The minimum amount out of the underlying token that is expected
    ///                         to be received out.
    function harvest(uint256 amount, uint256 minimumAmountOut) external lock onlyKeeper {
        // Check and see if we have enough stargate tokens to harvest.
        uint256 startingBalance = IERC20(stargateToken).balanceOf(address(this));
        if (startingBalance < amount) {
            // A noop deposit will claim stargate tokens.
            ILPStaking(stargateStaking).deposit(stargateStakingPoolId, 0);
        }

        // Check to see if we have a sufficient amount of stargate tokens to exchange.
        uint256 currentBalance = IERC20(stargateToken).balanceOf(address(this));
        if (currentBalance < amount) revert IllegalState("Insufficient balance");

        // Exchange stargate tokens for underlying tokens.
        CurvePoolParams[] memory path = swapPath;
        for (uint256 i = 0; i < path.length; i++) {
            CurvePoolParams memory params = path[i];

            uint256 startingBalance = IERC20(params.outputAsset).balanceOf(address(this));

            IStableSwapGeneric(params.curvePool).exchange(
                int128(uint128(params.inputIndex)),
                int128(uint128(params.outputIndex)),
                currentBalance,
                i == path.length - 1 ? minimumAmountOut : 0 // Only care about slippage at the end
            );

            currentBalance = IERC20(params.outputAsset).balanceOf(address(this)) - startingBalance;
        }
    }

    /// @dev TODO
    ///
    /// @return total TODO
    function _totalAssets() internal view returns (uint256 total) {
        (uint256 totalStaked, ) = ILPStaking(stargateStaking).userInfo(
            stargateStakingPoolId,
            address(this)
        );

        uint256 liquidityTokenReserves  = IERC20(stargatePool).balanceOf(address(this));
        uint256 underlyingTokenReserves = IERC20(underlyingToken).balanceOf(address(this));

        total += _liquidityTokensToUnderlying(totalStaked);
        total += _liquidityTokensToUnderlying(liquidityTokenReserves);
        total += underlyingTokenReserves;
    }

    /// @dev TODO
    ///
    /// @param amount TODO
    ///
    /// @return TODO
    function _liquidityTokensToUnderlying(uint256 amount) internal view returns (uint256) {
        return 0;
    }

    /// @dev TODO
    ///
    /// @param amount TODO
    ///
    /// @return TODO
    function _underlyingTokensToLiquidity(uint256 amount) internal view returns (uint256) {
        return 0;
    }
}