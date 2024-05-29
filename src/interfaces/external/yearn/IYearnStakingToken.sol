pragma solidity >=0.5.0;

import {IYearnVaultV2} from '../../../interfaces/external/yearn/IYearnVaultV2.sol';
import {IStakingRewards} from '../../../interfaces/external/yearn/IStakingRewards.sol';

interface IYearnStakingToken {
    function claimRewards() external returns (uint256);
    function deposit(address recipient, uint256 amount, bool fromUnderlying) external returns (uint256);
    function withdraw(address recipient, uint256 amount, uint256 maxSlippage, bool fromUnderlying) external returns (uint256, uint256);
    function YEARN_VAULT() external view returns (IYearnVaultV2);
    function STAKNG_REWARDS() external view returns (IStakingRewards);
}