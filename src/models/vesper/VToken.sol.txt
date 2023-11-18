pragma solidity ^0.8.11;

contract VesperToken {
	IERC20 _underlyingToken;

	uint256 _totalSupply;
	mapping(address => uint256) _balances;

	uint256 public constant MAX_BPS = 10_000;
	
	constructor(address underlyingToken) {
		_underlyingToken = IERC20(underlyingToken);
	}

	function decimals() returns (uint8) {
		return 18;
	}

	function totalSupply() returns (uint256) {
		return _totalSupply;
	}
	
	function balanceOf(address account) returns (uint256) {
		return _balances[account];
	}
	
	function pricePerShare() external view returns (uint256) {
		// totalValue() kept abstract in this model
		if (totalSupply() == 0 || totalValue() == 0) {
			return 10 ** _underlyingToken.decimals();
		}

		return totalValue() * 1e18 / totalSupply();
	}

	function deposit(uint256 amount) external {
		// _updateRewards() kept abstract, assumed to not impact model behavior
		_updateRewards(msg.sender);

		uint256 shares = _calculateMintage(amount);
		
		SafeERC20.safeTransferFrom(
			_underlyingToken, msg.sender, address(this), amount
		);
		
		_mint(msg.sender, shares);
	}

	function withdraw(uint256 shares) {
		require(shares > 0);
		
		// _updateRewards() kept abstract, assumed to not impact model behavior
		_updateRewards(msg.sender);

		(uint256 amountWithdrawn, bool isPartial) = _beforeBurning(shares);

		if (isPartial) {
			uint256 proportionalShares = _calculateShares(amountWithdrawn);

			if (proportionalShares < shares) {
				shares = proportionalShares;
			}
		}

		_burn(msg.sender, shares);
		SafeERC20.safeTransfer(_underlyingToken, msg.sender, amountWithdrawn);
	}

	function _beforeBurning(uint256 share)
		returns (uint256 actualWithdrawn, bool isPartial)
	{
		uint256 amount = share * pricePerShare() / 1e18;
		uint256 tokensHere = _underlyingToken.balanceOf(address(this));
		actualWithdrawn = amount;

		if (amount > tokensHere) {
			// _withdrawCollateral() kept abstract in the model,
			// assumed to only impact underlying token balance
			_withdrawCollateral(amount - tokensHere);
			tokensHere = _underlyingToken.balanceOf(address(this));

			if (amount > tokensHere) {
				actualWithdrawn = tokensHere;
				isPartial = true;
			}
		}

		require(actualWithdrawn > 0);
	}

	function _calculateMintage(uint256 amount) public view returns (uint256) {
		require(amount > 0);
		// externalDepositFee() kept abstract in the model
		uint256 externalDepositFee = amount * externalDepositFee() / MAX_BPS;
		return _calculateShares(amount - externalDepositFee);
	}

	function _calculateShares(uint256 amount) returns (uint256) {
		uint256 share = amount * 1e18 / pricePerShare();
		return amount > share * pricePerShare() / 1e18 ? share + 1 : share;
	}
	
	function _mint(address account, uint256 amount) internal {
		require(account != address(0));

		_beforeTokenTransfer(address(0), account, amount);

		_totalSupply += amount;
		_balances[account] += amount;
	}

	function _burn(address account, uint256 amount) {
		require(account != address(0));

		_beforeTokenTransfer(account, address(0), amount);

		uint256 accountBalance = _balances[account];
		require(accountBalance >= amount);
		_balances[account] = accountBalance - amount;
		_totalSupply -= amount;
	}

	function transfer(address recipient, uint256 amount) returns (bool) {
		_transfer(msg.sender, recipient, amount);
		return true;
	}

	function transferFrom(address sender, address recipient, uint256 amount)
		returns (bool)
	{
		_transfer(sender, recipient, amount);

		uint256 currentAllowance = _allowances[sender][msg.sender];
		require(currentAllowance >= amount);
		_approve(sender, msg.sender, currentAllowance - amount);

		return true;
	}

	function _transfer(address sender, address recipient, uint256 amount)
		returns (bool)
	{
		require(sender != address(0));
		require(recipient != address(0));

		_beforeTokenTransfer(sender, recipient, amount);

		uint256 senderBalance = _balances[sender];
		require(senderBalance >= amount);
		_balances[sender] = senderBalance - amount;
		_balances[recipient] += amount;
	}

	function _approve(address owner, address spender, uint256 amount) {
		require(owner != address(0));
		require(spender != address(0));

		_allowances[owner][spender] = amount;
	}
}
