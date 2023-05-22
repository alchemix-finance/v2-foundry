pragma solidity >=0.5.0;

import {IYearnVaultV2} from '../../../interfaces/external/yearn/IYearnVaultV2.sol';

interface IYearnStakingToken {
<<<<<<< HEAD
    function deposit(address recipient, uint256 amount) external returns (uint256);
    function withdraw(address recipient, uint256 amount, uint256 maxSlippage) external returns (uint256, uint256);
=======
    function claimRewards() external returns (uint256);
    function deposit(address recipient, uint256 amount, bool fromUnderlying) external returns (uint256);
    function withdraw(address recipient, uint256 amount, bool fromUnderlying) external returns (uint256, uint256);
>>>>>>> 96fd20e (YToken Gateway added and tested)
    function YEARN_VAULT() external view returns (IYearnVaultV2);
}