// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {
    IllegalArgument,
    IllegalState,
    Unauthorized,
    UnsupportedOperation
} from "../../base/ErrorMessages.sol";

import {MutexLock} from "../../base/MutexLock.sol";

import {SafeERC20} from "../../libraries/SafeERC20.sol";
import {RocketPool} from "../../libraries/RocketPool.sol";

import {IAsset} from "../../interfaces/external/balancer/IAsset.sol";
import {IChainlinkOracle} from "../../interfaces/external/chainlink/IChainlinkOracle.sol";
import {ITokenAdapter} from "../../interfaces/ITokenAdapter.sol";
import {IWETH9} from "../../interfaces/external/IWETH9.sol";
import {IRocketStorage} from "../../interfaces/external/rocket/IRocketStorage.sol";
import {IVault} from "../../interfaces/external/balancer/IVault.sol";

struct InitializationParams {
    address alchemist;
    address token;
    address underlyingToken;
}

contract RETHAdapterV1 is ITokenAdapter, MutexLock {
    using RocketPool for IRocketStorage;

    address constant chainlinkOracle = 0x536218f9E9Eb48863970252233c8F271f554C2d0;
    address constant balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    bytes32 constant balancerPoolId = 0x1e19cf2d73a72ef1332c882f20534b6519be0276000200000000000000000112;
    uint256 constant deadline = 2000000000;

    string public override version = "1.2.0";

    address public immutable alchemist;
    address public immutable override token;
    address public immutable override underlyingToken;

    constructor(InitializationParams memory params) {
        alchemist       = params.alchemist;
        token           = params.token;
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
        if (msg.sender != underlyingToken && msg.sender != token) {
            revert Unauthorized("Payments only permitted from WETH or rETH");
        }
    }

    /// @inheritdoc ITokenAdapter
    function price() external view returns (uint256) {
        // Ensure that round is complete, otherwise price is stale.
        (
            uint80 roundID,
            int256 rethToEth,
            ,
            uint256 updateTime,
            uint80 answeredInRound
        ) = IChainlinkOracle(chainlinkOracle).latestRoundData();
        require(
            answeredInRound >= roundID,
            "Chainlink Price Stale"
        );

        require(rethToEth > 0, "Chainlink Malfunction");
        require(updateTime != 0, "Incomplete round");

        return uint256(rethToEth);
    }

    /// @inheritdoc ITokenAdapter
    function wrap(
        uint256 amount,
        address recipient
    ) external onlyAlchemist returns (uint256) {
        amount; recipient; // Silence, compiler!

        // NOTE: Wrapping is currently unsupported because the Rocket Pool requires that all
        //       addresses that mint rETH to wait approximately 24 hours before transferring
        //       tokens. In the future when the minting restriction is removed, an adapter
        //       that supports this operation will be written.
        //
        //       We had considered exchanging ETH for rETH here, however, the liquidity on the
        //       majority of the pools is too limited. Also, the landscape of those pools are very
        //       likely to change in the coming months. We recommend that users exchange for
        //       rETH on a pool of their liking or mint rETH and then deposit it at a later time.
        revert UnsupportedOperation("Wrapping is not supported");
    }

    // @inheritdoc ITokenAdapter
    function unwrap(
        uint256 amount,
        address recipient
    ) external lock onlyAlchemist returns (uint256) {
        // Transfer the rETH from the message sender.
        SafeERC20.safeTransferFrom(token, msg.sender, address(this), amount);

        // Swap for WETH on balancer
        IVault.SingleSwap memory singleSwap =
            IVault.SingleSwap({
                poolId: balancerPoolId,
                kind: IVault.SwapKind.GIVEN_IN,
                assetIn: IAsset(token),
                assetOut: IAsset(underlyingToken),
                amount: amount,
                userData: bytes("")
            });

        IVault.FundManagement memory funds = 
            IVault.FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(this)),
                toInternalBalance: false
            });

        SafeERC20.safeApprove(token, balancerVault, amount);
        uint256 receivedWeth = IVault(balancerVault).swap(singleSwap, funds, 0, deadline);

        // Transfer the tokens to the recipient.
        SafeERC20.safeTransfer(underlyingToken, recipient, receivedWeth);

        return receivedWeth;
    }
}