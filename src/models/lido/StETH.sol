pragma solidity ^0.8.11;

import {IStETH} from "src/interfaces/external/lido/IStETH.sol";

contract StETH is IStETH {
	mapping(address => uint256) shares;
	uint256 totalShares;
	uint256 totalPooledEther;

	mapping(address => mapping(address => uint256)) allowanceAmount;

	function sharesOf(address _account) external view returns (uint256) {
		return shares[_account];
	}

	function balanceOf(address _account) external view returns (uint256) {
		return getPooledEthByShares(shares[_account]);
	}

	function getSharesByPooledEth(uint256 _ethAmount)
		public view returns (uint256)
	{
		if (totalPooledEther == 0) {
			return _ethAmount;
		}
		
		return _ethAmount * totalShares / totalPooledEther;
	}
	
	function getPooledEthByShares(uint256 _sharesAmount)
		public view returns (uint256)
	{
		if (totalShares == 0) {
			return _sharesAmount;
		}
		
		return _sharesAmount * totalPooledEther / totalShares;
	}

	function setTotalShares(uint256 _totalShares) external {
		require(_totalShares > 0);
		totalShares = _totalShares;
	}

	function setTotalPooledEther(uint256 _totalPooledEther) external {
		require(_totalPooledEther > 0);
		totalPooledEther = _totalPooledEther;
	}

	function reset() external {
		totalShares = 0;
		totalPooledEther = 0;
	}
	
	function submit(address _referral) external payable returns (uint256) {
		uint256 amount = msg.value;
		uint256 mintedShares = getSharesByPooledEth(amount);

		shares[msg.sender] += mintedShares;
		totalShares += mintedShares;
		totalPooledEther += amount;

		return mintedShares;
	}

	function allowance(address _owner, address _spender)
		external view returns (uint256)
	{
		return allowanceAmount[_owner][_spender];
	}

	function approve(address _spender, uint256 _amount)
		external returns (bool)
	{
		allowanceAmount[msg.sender][_spender] = _amount;

		return true;
	}

	function totalSupply() external view returns (uint256) {
		return totalPooledEther;
	}

	function transfer(address _recipient, uint256 _amount)
		public returns (bool)
	{
		require(_recipient != address(0));

		uint256 shareAmount = getSharesByPooledEth(_amount);

		require(shares[msg.sender] >= shareAmount);

		shares[msg.sender] -= shareAmount;
		shares[_recipient] += shareAmount;

		return true;
		
	}
	
	function transferFrom(
		address _sender,
		address _recipient,
		uint256 _amount
    ) public returns (bool) {
		require(_sender != address(0));
		require(_recipient != address(0));
		require(allowanceAmount[_sender][msg.sender] >= _amount);

		uint256 shareAmount = getSharesByPooledEth(_amount);

		require(shares[_sender] >= shareAmount);

		shares[_sender] -= shareAmount;
		shares[_recipient] += shareAmount;
		allowanceAmount[_sender][msg.sender] -= shareAmount;

		return true;
	}
}
