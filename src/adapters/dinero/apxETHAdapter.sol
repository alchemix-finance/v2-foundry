pragma solidity ^0.8.13;

import { ITokenAdapter } from "../../interfaces/ITokenAdapter.sol";
import { MutexLock } from "../../base/MutexLock.sol";
import "../../libraries/TokenUtils.sol";
import { Unauthorized } from "../../base/ErrorMessages.sol";
import { IWETH9 } from "../../interfaces/external/IWETH9.sol";
import { IERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { IStableSwapNGPool } from "../../interfaces/external/curve/IStableSwapNGPool.sol";
import { IPirexContract } from "../../interfaces/external/pirex/IPirexContract.sol";


contract apxETHAdapter is ITokenAdapter {
	uint256 private constant MAXIMUM_SLIPPAGE = 10000;
	string public constant override version = "1.0.0";

	address public immutable alchemist;
	address public immutable override token; // apxETH token address
	address public immutable pxEthToken; // pxETH token address
	address public immutable override underlyingToken; // WETH address
	IStableSwapNGPool public immutable stableSwapNGPool;
	address public immutable apxETHDepositContract;
	
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
		// Transfer the underlying token from the sender to the adapter
		TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
		// Unwrap WETH to ETH because IPirexContract requires ETH
		IWETH9(underlyingToken).withdraw(amount);
		// Deposit ETH into the apxETH deposit contract
		IPirexContract(apxETHDepositContract).deposit{ value: amount }(address(this), true);
		// Record the yield tokens because IPirexContract only returns amount of pxETH minted but not apxETH shares
		uint256 yieldTokens = TokenUtils.safeBalanceOf(token, address(this));
		// Transfer the yield tokens to the recipient
		TokenUtils.safeTransfer(token, recipient, yieldTokens);
		return yieldTokens;
	}

	function unwrap(uint256 amount, address recipient) external onlyAlchemist returns (uint256 receivedWeth) {
		// Transfer the shares from the Alchemist to the Adapter
		TokenUtils.safeTransferFrom(token, msg.sender, address(this), amount);
		// Approve the token to be transferred to the redeem function
		TokenUtils.safeApprove(token, address(token), amount);
		// Redeem the shares to get pxETH
		uint256 redeem = IERC4626(token).redeem(amount, address(this), address(this));
		// Record the amount of pxETH received
		uint256 redeemedPxEth = IERC20(pxEthToken).balanceOf(address(this));
		// Approve the pxETH to be transferred to the stableSwapNGPool
		TokenUtils.safeApprove(pxEthToken, address(stableSwapNGPool), redeemedPxEth);
		// definition of the swap to be executed
		stableSwapNGPool.exchange(1, 0, redeemedPxEth, 0, address(this));
		// Record the amount of WETH received
		receivedWeth = IERC20(underlyingToken).balanceOf(address(this));
		// Transfer the WETH to the recipient
		TokenUtils.safeTransfer(underlyingToken, recipient, receivedWeth);
		return receivedWeth;
	}
}
