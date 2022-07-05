// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Mintable} from "./IERC20Mintable.sol";

interface IStakingPools {
    function acceptGovernance() external;
    function claim(uint256 _poolId) external;
    function claimExact(uint256 _poolId, uint256 _claimAmount) external;
    function createPool(IERC20 _token) external returns (uint256);
    function deposit(uint256 _poolId, uint256 _depositAmount) external;
    function exit(uint256 _poolId) external;
    function getPoolRewardRate(uint256 _poolId) view external returns (uint256);
    function getPoolRewardWeight(uint256 _poolId) view external returns (uint256);
    function getPoolToken(uint256 _poolId) view external returns (address);
    function getPoolTotalDeposited(uint256 _poolId) view external returns (uint256);
    function getStakeTotalDeposited(address _account, uint256 _poolId) view external returns (uint256);
    function getStakeTotalUnclaimed(address _account, uint256 _poolId) view external returns (uint256);
    function governance() view external returns (address);
    function pendingGovernance() view external returns (address);
    function poolCount() view external returns (uint256);
    function reward() view external returns (IERC20Mintable);
    function rewardRate() view external returns (uint256);
    function setPendingGovernance(address _pendingGovernance) external;
    function setRewardRate(uint256 _rewardRate) external;
    function setRewardWeights(uint256[] memory _rewardWeights) external;
    function tokenPoolIds(IERC20 _token) view external returns (uint256);
    function totalRewardWeight() view external returns (uint256);
    function withdraw(uint256 _poolId, uint256 _withdrawAmount) external;
}