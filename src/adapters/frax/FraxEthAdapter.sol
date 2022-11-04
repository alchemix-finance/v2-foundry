pragma solidity ^0.8.13;

import {IllegalState} from "../../base/Errors.sol";
import {IllegalArgument, Unauthorized} from "../../base/ErrorMessages.sol";


import {IFraxMinter} from "../../interfaces/external/frax/IFraxMinter.sol";
import {IFraxEth} from "../../interfaces/external/frax/IFraxEth.sol";
import {IStakedFraxEth} from "../../interfaces/external/frax/IStakedFraxEth.sol";
import {IStableSwap2Pool} from "../../interfaces/external/curve/IStableSwap2Pool.sol";
import {ITokenAdapter} from "../../interfaces/ITokenAdapter.sol";
import {IWETH9} from "../../interfaces/external/IWETH9.sol";

import {MutexLock} from "../../base/MutexLock.sol";

import "../../libraries/TokenUtils.sol";

struct InitializationParams {
    address alchemist;
    address curvePool;
    address minter;
    address token;
    address parentToken;
    address underlyingToken;
    uint128 curvePoolEthIndex;
    uint128 curvePoolfrxEthIndex;
}

/// @title  FraxEthAdapter
/// @author Alchemix Finance
contract FraxEthAdapter is ITokenAdapter, MutexLock {
    uint256 private constant MAXIMUM_SLIPPAGE = 10000;
    string public constant override version = "1.0.0";

    address public immutable alchemist;
    address public immutable curvePool;
    address public immutable minter;
    address public immutable override token;
    address public immutable parentToken;
    address public immutable override underlyingToken;
    uint128 public immutable curvePoolEthIndex;
    uint128 public immutable curvePoolfrxEthIndex;

    constructor(InitializationParams memory params) {
        alchemist = params.alchemist;
        curvePool = params.curvePool;
        curvePoolEthIndex = params.curvePoolEthIndex;
        curvePoolfrxEthIndex = params.curvePoolfrxEthIndex;
        minter = params.minter;
        token = params.token;
        parentToken = params.parentToken;
        underlyingToken = params.underlyingToken;
    }

    /// @dev Checks that the message sender is the alchemist that the adapter is bound to.
    modifier onlyAlchemist() {
        if (msg.sender != alchemist) {
            revert Unauthorized("Not alchemist");
        }
        _;
    }

    receive() external payable {
        if (msg.sender != underlyingToken && msg.sender != curvePool) {
            revert Unauthorized("Payments only permitted from WETH or curve pool");
        }
    }

    /// @inheritdoc ITokenAdapter
    function price() external view override returns (uint256) {
        return IStakedFraxEth(token).convertToAssets(1e18);
    }

    /// @inheritdoc ITokenAdapter
    function wrap(uint256 amount, address recipient) external lock onlyAlchemist returns (uint256) {
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);

        // Unwrap the WETH into ETH.
        IWETH9(underlyingToken).withdraw(amount);

        // Mint frxEth.
        uint256 startingFraxEthBalance = IERC20(parentToken).balanceOf(address(this));
        IFraxMinter(minter).submit{value: amount}();
        uint256 mintedFraxEth = IERC20(parentToken).balanceOf(address(this)) - startingFraxEthBalance;

        TokenUtils.safeApprove(parentToken, token, mintedFraxEth);
        return IStakedFraxEth(token).deposit(mintedFraxEth, recipient);
    }

    /// @inheritdoc ITokenAdapter
    function unwrap(uint256 amount, address recipient) external lock onlyAlchemist returns (uint256) {
        TokenUtils.safeTransferFrom(token, msg.sender, address(this), amount);

        // Withdraw frxEth from  sfrxEth.
        uint256 startingFraxEthBalance = IERC20(parentToken).balanceOf(address(this));
        IStakedFraxEth(token).withdraw(amount * this.price() / 10**TokenUtils.expectDecimals(token), address(this), address(this));
        uint256 withdrawnFraxEth = IERC20(parentToken).balanceOf(address(this)) - startingFraxEthBalance;

        // Swap frxEth for eth in curve.
        TokenUtils.safeApprove(parentToken, curvePool, withdrawnFraxEth);
        uint256 received = IStableSwap2Pool(curvePool).exchange(
            int128(uint128(curvePoolfrxEthIndex)),
            int128(uint128(curvePoolEthIndex)),
            withdrawnFraxEth,
            0                                // <- Slippage is handled upstream
        );

        // Wrap the ETH that we received from the exchange.
        IWETH9(underlyingToken).deposit{value: received}();

        // Transfer the tokens to the recipient.
        TokenUtils.safeTransfer(underlyingToken, recipient, received);

        return received;
    }
}