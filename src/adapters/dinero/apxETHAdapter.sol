pragma solidity ^0.8.13;

import { ITokenAdapter } from "../../interfaces/ITokenAdapter.sol";
import { MutexLock } from "../../base/MutexLock.sol";
import "../../libraries/TokenUtils.sol";
import { Unauthorized } from "../../base/ErrorMessages.sol";
import { IWETH9 } from "../../interfaces/external/IWETH9.sol";
import { IERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { IStableSwapNGPool } from "../../interfaces/external/curve/IStableSwapNGPool.sol";
import "forge-std/console.sol";

interface IPirexContract {
	function deposit(address receiver, bool isCompound) external payable returns (uint256, uint256);
}

interface IVault {
	enum SwapKind {
		GIVEN_IN,
		GIVEN_OUT
	}

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
	address public immutable override token; // apxETH token address
	address public immutable pxEthToken; // pxETH token address
	address public immutable override underlyingToken; // WETH address
	IStableSwapNGPool public immutable stableSwapNGPool;
	address public immutable apxETHDepositContract;
	address public admin;
	constructor(
		address _alchemist,
		address _token,
		address _underlyingToken,
		address _stableSwapNGPool,
		address _pxEthToken,
		address _apxETHDepositContract
	) {
		alchemist = _alchemist;
		token = _token;
		underlyingToken = _underlyingToken;
		stableSwapNGPool = IStableSwapNGPool(_stableSwapNGPool);
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
		// TokenUtils.safeApprove(underlyingToken, address(wETH), amount);
		IWETH9(underlyingToken).withdraw(amount);
		IPirexContract(apxETHDepositContract).deposit{ value: amount }(address(this), true);
        uint256 yieldTokens = TokenUtils.safeBalanceOf(token, address(this));
        TokenUtils.safeTransfer(token, recipient, yieldTokens);
		return yieldTokens;
	}

	function unwrap(uint256 amount, address recipient) external onlyAlchemist returns (uint256 receivedWeth) {
		TokenUtils.safeTransferFrom(token, msg.sender, address(this), amount);
		uint256 startingPxEthBalance = IERC20(pxEthToken).balanceOf(address(this));

		TokenUtils.safeApprove(token, address(token), amount);
		uint256 redeem = IERC4626(token).redeem(amount, address(this), address(this));
        console.log("redeem", redeem);
		uint256 redeemedPxEth = IERC20(pxEthToken).balanceOf(address(this)) - startingPxEthBalance;

		TokenUtils.safeApprove(pxEthToken, address(stableSwapNGPool), redeemedPxEth);
		// definition of the swap to be executed
		stableSwapNGPool.exchange(1, 0, redeemedPxEth, 0, address(this));
		receivedWeth = IERC20(underlyingToken).balanceOf(address(this));
		TokenUtils.safeTransfer(underlyingToken, recipient, receivedWeth);
	}
}
