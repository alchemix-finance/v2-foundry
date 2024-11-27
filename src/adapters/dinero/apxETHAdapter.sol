pragma solidity ^0.8.13;

import {ITokenAdapter} from "../../interfaces/ITokenAdapter.sol";
import {MutexLock} from "../../base/MutexLock.sol";
import "../../libraries/TokenUtils.sol";
import {Unauthorized} from "../../base/ErrorMessages.sol";
import {IWETH9} from "../../interfaces/external/IWETH9.sol";
import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

interface IPirexContract {
    function deposit(address receiver, bool isCompound) external payable returns (uint256);
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

contract apxETHAdapter is ITokenAdapter {
    uint256 private constant MAXIMUM_SLIPPAGE = 10000;

    string public constant override version = "1.0.0";

    address public immutable alchemist;
    address public immutable override token;           // apxETH token address
    address public immutable pxEthToken;              // pxETH token address
    address public immutable override underlyingToken; // WETH address
    IVault public immutable balancerVault;
    bytes32 public immutable balancerPoolId;
    address public immutable apxETHDepositContract;
    address public admin;
    constructor(
        address _alchemist,
        address _token,
        address _underlyingToken,
        address _balancerVault,
        bytes32 _balancerPoolId,
        address _pxEthToken,
        address _apxETHDepositContract
    ) {
        alchemist = _alchemist;
        token = _token;
        underlyingToken = _underlyingToken;
        balancerVault = IVault(_balancerVault);
        balancerPoolId = _balancerPoolId;
        pxEthToken = _pxEthToken;
        apxETHDepositContract = _apxETHDepositContract;
        admin = msg.sender;
    }

    modifier onlyAlchemist() {
        if (msg.sender != alchemist) {
            revert Unauthorized("Not alchemist");
        }
        _;
    }

    receive() external payable {}

    function price() external view override returns (uint256) {
        return IERC4626(token).convertToAssets(1e18);
    }

    function wrap(uint256 amount, address recipient) external onlyAlchemist returns (uint256) {
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
        IWETH9(underlyingToken).withdraw(amount);
        return IPirexContract(apxETHDepositContract).deposit{value: amount}(recipient, true);
    }

    function unwrap(uint256 amount, address recipient) external onlyAlchemist returns (uint256 receivedWeth) {
        TokenUtils.safeTransferFrom(token, msg.sender, address(this), amount);

        uint256 startingPxEthBalance = IERC20(pxEthToken).balanceOf(address(this));
        IERC4626(token).redeem(amount, address(this), address(this));
        uint256 redeemedPxEth = IERC20(pxEthToken).balanceOf(address(this)) - startingPxEthBalance;

        TokenUtils.safeApprove(pxEthToken, address(balancerVault), redeemedPxEth);
        // definition of the swap to be executed
        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: balancerPoolId,
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: pxEthToken,
            assetOut: underlyingToken,
            amount: redeemedPxEth,
            userData: ""
        });
        // definition of where funds are going to/from
        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });
        // 1% slippage
        uint256 limit = (receivedWeth * 99) / 100;
        // 5 minutes
        uint256 deadline = block.timestamp + 300;
        // swap
        receivedWeth = balancerVault.swap(singleSwap, funds, limit, deadline);
        // transfer
        TokenUtils.safeTransfer(underlyingToken, recipient, receivedWeth);

    }
}
