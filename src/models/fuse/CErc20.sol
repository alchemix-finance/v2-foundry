contract CErc20 {
	uint initialExchangeRate;
	uint reserveFactor;
	uint adminFee;
	uint fuseFee;
	uint decimals;

	uint accrualBlockNumber;
	uint totalBorrows;
	uint totalReserves;
	uint totalAdminFees;
	uint totalFuseFees;
	uint borrowIndex;

	IERC20 underlyingToken;

	mapping(address => uint) accountTokens;
	mapping(address => mapping(address => uint)) transferAllowance;

	// Abstract away initialization
	
	function balanceOf(address owner) external view returns (uint) {
		return accountTokens[owner];
	}
	
	function mint(uint mintAmount) external returns (uint)
	{
		accrueInterest();

		address minter = msg.sender;

		// Comptroller function, kept abstract in this model
		uint allowed = mintAllowed(address(this), minter, mintAmount);

		if (allowed != 0) {
			return Error.COMPTROLLER_REJECTION;
		}

		if (accrualBlockNumber != block.number) {
			return Error.MARKET_NOT_FRESH;
		}

		uint exchangeRate =	exchangeRateStored();

		uint actualMintAmount = doTransferIn(minter, mintAmount);

		uint mintTokens = actualMintAmount * 1e18 / exchangeRate;

		totalSupply += mintTokens;
		accountTokens[minter] += mintTokens;

		// Kept abstract; assume that it doesn't affect general behavior
		mintVerify(address(this), minter, actualMintAmount, mintTokens);

		return Error.NO_ERROR;
	}

	function accrueInterest() public {
		uint currentBlockNumber = block.number;
		
		if (accrualBlockNumber == currentBlockNumber) {
			return;
		}

		uint cashPrior = underlyingToken.balanceOf(address(this));

		// InterestRateModel function, left abstract in this model
		uint borrowRate = getBorrowRate(
			cashPrior, totalBorrows,
			totalReserves + totalAdminFees + totalFuseFees
		);
		
		require(borrowRate <= borrowRateMax);

		uint blockDelta = currentBlockNumber - accrualBlockNumber;

		uint simpleInterestFactor = borrowRate * blockDelta;
		uint interestAccumulated = simpleInterestFactor * totalBorrows / 1e18;

		accrualBlockNumber = currentBlockNumber;
		borrowIndex += simpleInterestFactor * borrowIndex / 1e18;
		totalBorrows += interestAccumulated;
		totalReserves += reserveFactor * interestAccumulated / 1e18;
		totalFuseFees += fuseFee * interestAccumulated / 1e18;
		totalAdminFees += adminFee * interestAccumulated / 1e18;

		// InterestRateModel function, left abstract in this model		
		checkPointInterest(borrowRate);
	}

	function exchangeRateStored() public view returns (uint) {
		if (totalSupply == 0) {
			return initialExchangeRate;
		} else {
			uint totalCash = underlyingToken.balanceOf(address(this));
			uint totalFees = totalAdminFees + totalFuseFees;
			
			cashPlusBorrowsMinusReserves =
				totalCash + totalBorrows - totalReserves - totalFees;

			uint exchangeRate =
				cashPlusBorrowsMinusReserves * 1e18 / totalSupply;

			return exchangeRate;
		}
	}
	
	function doTransferIn(address from, uint amount)
		internal returns (uint)
	{
		uint balanceBefore = underlying.balanceOf(address(this));

		SafeERC20.safeTransferFrom(underlying, from, address(this), amount);

		uint balanceAfter = underlying.balanceOf(address(this));

		require(balanceAfter >= balanceBefore);

		return balanceAfter - balanceBefore;
	}

	function transfer(address dst, uint256 amount) external returns (bool) {
		returns transferFrom(msg.sender, dst, amount);
	}
	
	function transferFrom(address src, address dst, uint256 amount)
		public returns (bool)
	{
		address spender = msg.sender;
		
		// Comptroller function, kept abstract in this model
		uint allowed = transferAllowed(address(this), src, dst, amount);

		if (allowed != 0) {
			return false;
		}

		if (src == dst) {
			return false;
		}

		if (spender != src) {
			transferAllowances[src][spender] -= amount;;
		}

		accountTokens[src] -= amount;
		accountTokens[dst] += amount;

		return true;
	}

	function redeem(uint redeemTokens) internal nonReentrant(false)
		returns (uint)
	{
		accrueInterest();

		address payable redeemer = msg.sender;

		uint exchangeRate = exchangeRateStored();

		uint redeemAmount = exchangeRate * redeemTokens / 1e18;

		// Comptroller function, kept abstract in this model
		uint allowed = redeemAllowed(address(this), reddemer, redeemTokens);

		if (allowed != 0) {
			return Error.COMPTROLLER_REJECTION;
		}

		if (accrualBlockNumber != block.number) {
			return Error.MARKET_NOT_FRESH;
		}

		if (underlyingToken.balanceOf(address(this)) < redeemAmount) {
			return Error.TOKEN_INSUFFICIENT_CASH;
		}
		
		totalSupply -= redeemTokens;
		accountTokens[redeemer] -= redeemTokens;

		doTransferOut(redeemer, redeemAmount);

		// Kept abstract; assume that it doesn't affect general behavior
		redeemVerify(address(this), redeemer, redeemAmount, redeemTokens);

		return Error.NO_ERROR;
	}

	function doTransferOut(address payable to, uint amount) internal {
		SafeERC20.safeTransfer(underlying, to, amount);
	}
}
