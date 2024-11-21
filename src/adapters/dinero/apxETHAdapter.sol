pragma solidity ^0.8.13;

import {ITokenAdapter} from "../../interfaces/ITokenAdapter.sol";
import {MutexLock} from "../../base/MutexLock.sol";
import "../../libraries/TokenUtils.sol";
import {Unauthorized} from "../../base/ErrorMessages.sol";

import {IWETH9} from "../../interfaces/external/IWETH9.sol";
import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IPirexContract {
    function depositEther(address receiver, bool isCompound) external payable returns (uint256);
}

interface IapxEthToken {
    function redeem(uint256 shares, address receiver) external returns (uint256 assets);
}

interface IStableSwap {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256);
}

contract PirexEthAdapter is ITokenAdapter, MutexLock {
    string public constant override version = "1.0.0";

    address public immutable alchemist;
    address public immutable override token; // apxETH token address
    address public immutable pxEthToken;     // pxETH token address
    address public immutable override underlyingToken; // WETH address
    IPirexContract public immutable pirexContract;
    IapxEthToken public immutable apxEthTokenContract;
    IStableSwap public immutable curvePool;
    int128 public immutable curvePoolPxEthIndex;
    int128 public immutable curvePoolEthIndex;

    constructor(
        address _alchemist,
        address _token, // apxETH token address
        address _pxEthToken, // pxETH token address
        address _underlyingToken, // WETH address
        address _pirexContract, // Pirex contract address for minting
        address _apxEthTokenContract, // apxETH token contract for redeeming
        address _curvePool,
        int128 _curvePoolPxEthIndex,
        int128 _curvePoolEthIndex
    ) {
        alchemist = _alchemist;
        token = _token; // apxETH token address
        pxEthToken = _pxEthToken; // pxETH token address
        underlyingToken = _underlyingToken; // WETH address
        pirexContract = IPirexContract(_pirexContract);
        apxEthTokenContract = IapxEthToken(_apxEthTokenContract);
        curvePool = IStableSwap(_curvePool);
        curvePoolPxEthIndex = _curvePoolPxEthIndex;
        curvePoolEthIndex = _curvePoolEthIndex;
    }

    /// @dev Restricts calls to the alchemist.
    modifier onlyAlchemist() {
        if (msg.sender != alchemist) {
            revert Unauthorized("Not alchemist");
        }
        _;
    }

    receive() external payable {
        // Accept ETH from WETH unwrapping or from swaps.
    }

    /// @inheritdoc ITokenAdapter
    function price() external view override returns (uint256) {
        // Implement price logic if required.
        // For this example, assume 1 apxETH = 1 ETH.
        return 1e18;
    }

    /// @inheritdoc ITokenAdapter
    function wrap(uint256 amount, address recipient) external lock onlyAlchemist returns (uint256) {
        // Transfer WETH from the sender to the adapter.
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);

        // Unwrap WETH to ETH.
        IWETH9(underlyingToken).withdraw(amount);

        // Deposit ETH into Pirex to receive apxETH.
        // The depositEther function uses msg.value for the amount.
        uint256 startingBalance = IERC20(token).balanceOf(address(this));
        pirexContract.deposit{value: amount}(address(this), true);
        uint256 mintedShares = IERC20(token).balanceOf(address(this)) - startingBalance;

        // Transfer apxETH to the recipient.
        TokenUtils.safeTransfer(token, recipient, mintedShares);

        return mintedShares;
    }

    /// @inheritdoc ITokenAdapter
    function unwrap(uint256 amount, address recipient) external lock onlyAlchemist returns (uint256) {
        // Transfer apxETH from the sender to the adapter.
        TokenUtils.safeTransferFrom(token, msg.sender, address(this), amount);

        // Redeem apxETH for pxETH.
        uint256 startingPxEthBalance = IERC20(pxEthToken).balanceOf(address(this));
        // We call redeem on the apxETH token contract
        TokenUtils.safeApprove(token, address(apxEthTokenContract), amount);
        apxEthTokenContract.redeem(amount, address(this));
        uint256 redeemedPxEth = IERC20(pxEthToken).balanceOf(address(this)) - startingPxEthBalance;

        // Swap pxETH for ETH on Curve.
        // Approve pxETH to the Curve pool.
        TokenUtils.safeApprove(pxEthToken, address(curvePool), redeemedPxEth);

        // Handle slippage in minWethOut if necessary.
        uint256 minWethOut = 0; // Replace with slippage calculation if needed.
        uint256 receivedWeth = curvePool.exchange(
            curvePoolPxEthIndex,
            curvePoolEthIndex,
            redeemedPxEth,
            minWethOut
        );

        // Transfer WETH to the recipient.
        TokenUtils.safeTransfer(underlyingToken, recipient, receivedEth);

        return receivedWeth;
    }
}
