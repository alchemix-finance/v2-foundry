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
			return 0;
		}
		
		return _ethAmount * totalShares / totalPooledEther;
	}
	
	function getPooledEthByShares(uint256 _sharesAmount)
		public view returns (uint256)
	{
		if (totalShares == 0) {
			return 0;
		}
		
		return _sharesAmount * totalPooledEther / totalShares;
	}

	function setTotalShares(uint256 _totalShares) external {
		totalShares = _totalShares;
	}

	function setTotalPooledEther(uint256 _totalPooledEther) external {
		totalPooledEther = _totalPooledEther;
	}

	function submit(address _referral) external payable returns (uint256) {
		address sender = msg.sender;
		uint256 deposit = msg.value;
		require(deposit != 0);
		
		uint256 sharesAmount = getSharesByPooledEth(deposit);
		if (sharesAmount == 0) {
			sharesAmount = deposit;
		}
		
		shares[msg.sender] += sharesAmount;
		totalShares += sharesAmount;
		totalPooledEther += deposit;

		return sharesAmount;
	}

	function allowance(address _owner, address _spender)
		external view returns (uint256)
	{
		return allowanceAmount[_owner][_spender];
	}

	function approve(address _spender, uint256 _amount)
		external returns (bool)
	{
		require(_spender != address(0));
		
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
		allowanceAmount[_sender][msg.sender] -= _amount;

		return true;
	}
}
