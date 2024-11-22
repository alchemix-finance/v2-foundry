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

interface IVault {
    enum SwapKind { GIVEN_IN, GIVEN_OUT }

    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        address assetIn;
        address assetOut;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

    function swap(
        SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external payable returns (uint256 amountCalculated);
}

contract PirexEthAdapter is ITokenAdapter, MutexLock {
    string public constant override version = "1.0.0";

    address public immutable alchemist;
    address public immutable override token; // apxETH token address
    address public immutable pxEthToken;     // pxETH token address
    address public immutable override underlyingToken; // WETH address
    IPirexContract public immutable pirexContract;
    IapxEthToken public immutable apxEthTokenContract;
    IVault public immutable balancerVault;
    bytes32 public immutable balancerPoolId;

    constructor(
        address _alchemist,
        address _token,
        address _pxEthToken,
        address _underlyingToken,
        address _pirexContract,
        address _apxEthTokenContract,
        address _balancerVault,
        bytes32 _balancerPoolId
    ) {
        alchemist = _alchemist;
        token = _token;
        pxEthToken = _pxEthToken;
        underlyingToken = _underlyingToken;
        pirexContract = IPirexContract(_pirexContract);
        apxEthTokenContract = IapxEthToken(_apxEthTokenContract);
        balancerVault = IVault(_balancerVault);
        balancerPoolId = _balancerPoolId;
    }

    modifier onlyAlchemist() {
        if (msg.sender != alchemist) {
            revert Unauthorized("Not alchemist");
        }
        _;
    }

    receive() external payable {}

    function price() external view override returns (uint256) {
        // Implement actual price logic if required.
        return 1e18;
    }

    function wrap(uint256 amount, address recipient) external lock onlyAlchemist returns (uint256) {
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
        IWETH9(underlyingToken).withdraw(amount);

        uint256 startingBalance = IERC20(token).balanceOf(address(this));
        pirexContract.depositEther{value: amount}(address(this), true);
        uint256 mintedShares = IERC20(token).balanceOf(address(this)) - startingBalance;

        TokenUtils.safeTransfer(token, recipient, mintedShares);
        return mintedShares;
    }

    function unwrap(uint256 amount, address recipient) external lock onlyAlchemist returns (uint256) {
        TokenUtils.safeTransferFrom(token, msg.sender, address(this), amount);

        uint256 startingPxEthBalance = IERC20(pxEthToken).balanceOf(address(this));
        TokenUtils.safeApprove(token, address(apxEthTokenContract), amount);
        apxEthTokenContract.redeem(amount, address(this));
        uint256 redeemedPxEth = IERC20(pxEthToken).balanceOf(address(this)) - startingPxEthBalance;

        TokenUtils.safeApprove(pxEthToken, address(balancerVault), redeemedPxEth);

        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: balancerPoolId,
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: pxEthToken,
            assetOut: underlyingToken,
            amount: redeemedPxEth,
            userData: ""
        });

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        uint256 limit = 0; // Adjust based on acceptable slippage
        uint256 deadline = block.timestamp + 300;

        uint256 receivedWeth = balancerVault.swap(singleSwap, funds, limit, deadline);

        TokenUtils.safeTransfer(underlyingToken, recipient, receivedWeth);

        return receivedWeth;
    }
}
