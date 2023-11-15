// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IllegalArgument, IllegalState, Unauthorized} from "../../base/ErrorMessages.sol";
import {MutexLock} from "../../base/MutexLock.sol";

import {SafeERC20} from "../../libraries/SafeERC20.sol";

import {IChainlinkOracle} from "../../interfaces/external/chainlink/IChainlinkOracle.sol";
import {ITokenAdapter} from "../../interfaces/ITokenAdapter.sol";
import {IWETH9} from "../../interfaces/external/IWETH9.sol";
import {IStableSwap2Pool} from "../../interfaces/external/curve/IStableSwap2Pool.sol";
import {IStETH} from "../../interfaces/external/lido/IStETH.sol";
import {IWstETH} from "../../interfaces/external/lido/IWstETH.sol";

struct InitializationParams {
    address alchemist;
    address token;
    address parentToken;
    address underlyingToken;
    address curvePool;
    address oracleStethEth;
    uint256 ethPoolIndex;
    uint256 stEthPoolIndex;
    address referral;
}

contract WstETHAdapter is ITokenAdapter, MutexLock {
    string public override version = "1.1.0";

    address public immutable alchemist;
    address public immutable override token;
    address public immutable parentToken;
    address public immutable override underlyingToken;
    address public immutable curvePool;
    address public immutable oracleStethEth;
    uint256 public immutable ethPoolIndex;
    uint256 public immutable stEthPoolIndex;
    address public immutable referral;

    constructor(InitializationParams memory params) {
        alchemist       = params.alchemist;
        token           = params.token;
        parentToken     = params.parentToken;
        underlyingToken = params.underlyingToken;
        curvePool       = params.curvePool;
        oracleStethEth  = params.oracleStethEth;
        ethPoolIndex    = params.ethPoolIndex;
        stEthPoolIndex  = params.stEthPoolIndex;
        referral        = params.referral;

        // Verify and make sure that the provided ETH matches the curve pool ETH.
        if (
            IStableSwap2Pool(params.curvePool).coins(params.ethPoolIndex) !=
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
        ) {
            revert IllegalArgument("Curve pool ETH token mismatch");
        }

        // Verify and make sure that the provided stETH matches the curve pool stETH.
        if (
            IStableSwap2Pool(params.curvePool).coins(params.stEthPoolIndex) !=
            params.parentToken
        ) {
            revert IllegalArgument("Curve pool stETH token mismatch");
        }
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
    function price() external view returns (uint256) {
        // Ensure that round is complete, otherwise price is stale.
        (
            uint80 roundID,
            int256 stethToEth,
            ,
            uint256 updateTime,
            uint80 answeredInRound
        ) = IChainlinkOracle(oracleStethEth).latestRoundData();
        
        require(
            stethToEth > 0, 
            "Chainlink Malfunction"
        );

        if( updateTime < block.timestamp - 86400 seconds ) {
            revert("Chainlink Malfunction");
        }

        // Note that an oracle attack could push the price of stETH over 1 ETH, which could lead to alETH minted at a LTV ratio > 50%. 
        // Additionally, if stETH price is pushed > 2 ETH, then unbacked alETH could be minted. 
        // We cap the steth oracel price at 1 for this reason.
        if (stethToEth > 1e18) stethToEth = 1e18;

        return IWstETH(token).getStETHByWstETH(10**SafeERC20.expectDecimals(token)) * uint256(stethToEth) / 1e18;
    }

    /// @inheritdoc ITokenAdapter
    function wrap(
        uint256 amount,
        address recipient
    ) external lock onlyAlchemist returns (uint256) {
        // Transfer the tokens from the message sender.
        SafeERC20.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);

        // Unwrap the WETH into ETH.
        IWETH9(underlyingToken).withdraw(amount);

        // Wrap the ETH into stETH.
        uint256 startingStEthBalance = IERC20(parentToken).balanceOf(address(this));

        IStETH(parentToken).submit{value: amount}(referral);

        uint256 mintedStEth = IERC20(parentToken).balanceOf(address(this)) - startingStEthBalance;

        // Wrap the stETH into wstETH.
        SafeERC20.safeApprove(parentToken, address(token), mintedStEth);
        uint256 mintedWstEth = IWstETH(token).wrap(mintedStEth);

        // Transfer the minted wstETH to the recipient.
        SafeERC20.safeTransfer(token, recipient, mintedWstEth);

        return mintedWstEth;
    }

    // @inheritdoc ITokenAdapter
    function unwrap(
        uint256 amount,
        address recipient
    ) external lock onlyAlchemist returns (uint256) {
        // Transfer the tokens from the message sender.
        SafeERC20.safeTransferFrom(token, msg.sender, address(this), amount);

        // Unwrap the wstETH into stETH.
        uint256 startingStEthBalance = IStETH(parentToken).balanceOf(address(this));
        IWstETH(token).unwrap(amount);
        uint256 endingStEthBalance = IStETH(parentToken).balanceOf(address(this));

        // Approve the curve pool to transfer the tokens.
        uint256 unwrappedStEth = endingStEthBalance - startingStEthBalance;
        SafeERC20.safeApprove(parentToken, curvePool, unwrappedStEth);

        // Exchange the stETH for ETH. We do not check the curve pool because it is an immutable
        // contract and we expect that its output is reliable.
        uint256 received = IStableSwap2Pool(curvePool).exchange(
            int128(uint128(stEthPoolIndex)), // Why are we here, just to suffer?
            int128(uint128(ethPoolIndex)),   //                       (╥﹏╥)
            unwrappedStEth,
            0                                // <- Slippage is handled upstream
        );

        // Wrap the ETH that we received from the exchange.
        IWETH9(underlyingToken).deposit{value: received}();

        // Transfer the tokens to the recipient.
        SafeERC20.safeTransfer(underlyingToken, recipient, received);

        return received;
    }
}