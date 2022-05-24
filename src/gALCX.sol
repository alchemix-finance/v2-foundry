// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import { IERC20 } from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { ERC20 } from "../lib/solmate/src/tokens/ERC20.sol";

import { IALCXSource } from "./interfaces/IALCXSource.sol";

/// @title A wrapper for single-sided ALCX staking
contract gALCX is ERC20 {

    IERC20 public alcx = IERC20(0xdBdb4d16EdA451D0503b854CF79D55697F90c8DF);
    IALCXSource public pools = IALCXSource(0xAB8e74017a8Cc7c15FFcCd726603790d26d7DeCa);
    uint public poolId = 1;
    uint public constant exchangeRatePrecision = 1e18;
    uint public exchangeRate = exchangeRatePrecision;
    address public owner;

    event ExchangeRateChange(uint _exchangeRate);
    event Stake(address _from, uint _gAmount, uint _amount);
    event Unstake(address _from, uint _gAmount, uint _amount);

    /// @param _name The token name
    /// @param _symbol The token symbol
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol, 18) {
        owner = msg.sender;
        reApprove();
    }

    // OWNERSHIP

    modifier onlyOwner {
        require(msg.sender == owner, "Not owner");
        _;
    }

    /// @notice Transfer contract ownership
    /// @param _owner The new owner address
    function transferOwnership(address _owner) external onlyOwner {
        owner = _owner;
    }

    /// @notice Set a new staking pool address and migrate funds there
    /// @param _pools The new pool address
    /// @param _poolId The new pool id
    function migrateSource(address _pools, uint _poolId) external onlyOwner {
        // Withdraw ALCX
        bumpExchangeRate();

        uint poolBalance = pools.getStakeTotalDeposited(address(this), poolId);
        pools.withdraw(poolId, poolBalance);
        // Update staking pool address and id
        pools = IALCXSource(_pools);
        poolId = _poolId;
        // Deposit ALCX
        uint balance = alcx.balanceOf(address(this));
        reApprove();
        pools.deposit(poolId, balance);
    }

    /// @notice Approve the staking pool to move funds in this address, can be called by anyone
    function reApprove() public {
        bool success = alcx.approve(address(pools), type(uint).max);
    }

    // PUBLIC FUNCTIONS

    /// @notice Claim and autocompound rewards
    function bumpExchangeRate() public {
        // Claim from pool
        pools.claim(poolId);
        // Bump exchange rate
        uint balance = alcx.balanceOf(address(this));

        if (balance > 0) {
            exchangeRate += (balance * exchangeRatePrecision) / totalSupply;
            emit ExchangeRateChange(exchangeRate);
            // Restake
            pools.deposit(poolId, balance);
        }
    }

    /// @notice Deposit new funds into the staking pool
    /// @param amount The amount of ALCX to deposit
    function stake(uint amount) external {
        // Get current exchange rate between ALCX and gALCX
        bumpExchangeRate();
        // Then receive new deposits
        bool success = alcx.transferFrom(msg.sender, address(this), amount);
        require(success, "Transfer failed");
        pools.deposit(poolId, amount);
        // gAmount always <= amount
        uint gAmount = amount * exchangeRatePrecision / exchangeRate;
        _mint(msg.sender, gAmount);
        emit Stake(msg.sender, gAmount, amount);
    }

    /// @notice Withdraw funds from the staking pool
    /// @param gAmount the amount of gALCX to withdraw
    function unstake(uint gAmount) external {
        bumpExchangeRate();
        uint amount = gAmount * exchangeRate / exchangeRatePrecision;
        _burn(msg.sender, gAmount);
        // Withdraw ALCX and send to user
        pools.withdraw(poolId, amount);
        bool success = alcx.transfer(msg.sender, amount); // Should return true or revert, but doesn't hurt
        require(success, "Transfer failed"); 
        emit Unstake(msg.sender, gAmount, amount);
    }
}