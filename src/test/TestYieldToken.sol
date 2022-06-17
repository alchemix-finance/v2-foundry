pragma solidity ^0.8.11;

import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import "../libraries/TokenUtils.sol";
import "../interfaces/test/ITestYieldToken.sol";
import "./TestERC20.sol";

/// @title  TestYieldToken
/// @author Alchemix Finance
contract TestYieldToken is ITestYieldToken, ERC20 {
	address private constant BLACKHOLE = address(0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB);
	uint256 private constant BPS = 10000;

	address public override underlyingToken;
	uint8 private _decimals;
	uint256 public slippage;

	constructor(address _underlyingToken) ERC20("Yield Token", "Yield Token") {
		underlyingToken = _underlyingToken;
		_decimals = TokenUtils.expectDecimals(_underlyingToken);
		slippage = 0;
	}

	function decimals() public view override returns (uint8) {
		return _decimals;
	}

	function price() external view override returns (uint256) {
		return _shareValue(10**_decimals);
	}

	function setSlippage(uint256 _slippage) external {
		slippage = _slippage;
	}

	function mint(uint256 amount, address recipient) external override returns (uint256) {
		assert(amount > 0);

		uint256 shares = _issueSharesForAmount(recipient, amount);

		TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);

		return shares;
	}

	function redeem(uint256 shares, address recipient) external override returns (uint256) {
		assert(shares > 0);

		uint256 value = _shareValue(shares);
		value = (value * (BPS - slippage)) / BPS;
		_burn(msg.sender, shares);
		TokenUtils.safeTransfer(underlyingToken, recipient, value);

		return value;
	}

	function slurp(uint256 amount) external override {
		TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
	}

	function siphon(uint256 amount) external override {
		TokenUtils.safeTransfer(underlyingToken, BLACKHOLE, amount);
	}

	function _issueSharesForAmount(address to, uint256 amount) internal returns (uint256) {
		uint256 shares = 0;
		if (totalSupply() > 0) {
			shares = (amount * totalSupply()) / TokenUtils.safeBalanceOf(underlyingToken, address(this));
		} else {
			shares = amount;
		}
		shares = (shares * (BPS - slippage)) / BPS;
		_mint(to, shares);
		return shares;
	}

	function _shareValue(uint256 shares) internal view returns (uint256) {
		if (totalSupply() == 0) {
			return shares;
		}
		return (shares * TokenUtils.safeBalanceOf(underlyingToken, address(this))) / totalSupply();
	}
}
