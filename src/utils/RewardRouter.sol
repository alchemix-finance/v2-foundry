pragma solidity ^0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TokenUtils} from "../libraries/TokenUtils.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IRewardCollector} from "../interfaces/IRewardCollector.sol";
import {IRewardRouter} from "../interfaces/IRewardRouter.sol";
import {IStaticAToken} from "../interfaces/external/aave/IStaticAToken.sol";

import {Unauthorized, IllegalState, IllegalArgument} from "../base/ErrorMessages.sol";

struct RewardCollector {
    address rewardCollectorAddress;
    address rewardToken;
    uint256 rewardAmount;
}

/// @title  Reward Router
/// @author Alchemix Finance
contract RewardRouter is IRewardRouter {
    string public override version = "1.0.0";

    /// @dev A mapping of the yield tokens to their respective reward collectors
    mapping(address => RewardCollector) public rewardCollectors;

    /// @dev 
    function distributeRewards(address token, uint256 minimumAmountOut) external returns (uint256) {        
        // If vault is set to receive rewards from OP grant send amount to reward collector to donate
        if (rewardCollectors[token].rewardAmount > 0) {
            TokenUtils.safeTransfer(rewardCollectors[token].rewardToken, rewardCollectors[token].rewardCollectorAddress, rewardCollectors[token].rewardAmount);
        }

        return IRewardCollector(rewardCollectors[token].rewardCollectorAddress).claimAndDonateRewards(token, minimumAmountOut);
    }

    function sweepTokens(address token, address recipient) external {
        TokenUtils.safeTransfer(token, recipient, TokenUtils.safeBalanceOf(token, address(this)));
    }

    /// @dev Add reward collector params to a map of yield tokens
    function addRewardCollector(address vault, address rewardCollectorAddress, address rewardToken, uint256 rewardAmount) external {
        rewardCollectors[vault] = RewardCollector(rewardCollectorAddress, rewardToken, rewardAmount);
    }

    /// @dev set 
    function setRewardCollectorAddress(address vault, address rewardCollectorAddress) external {
        rewardCollectors[vault].rewardCollectorAddress = rewardCollectorAddress;
    }

    function setRewardToken(address vault, address rewardToken) external {
        rewardCollectors[vault].rewardToken = rewardToken;
    }

    function setRewardAmount(address vault, uint256 rewardAmount) external {
        rewardCollectors[vault].rewardAmount = rewardAmount;
    }

    function getRewardCollector(address vault) external view returns (address, address, uint256) {
        return (rewardCollectors[vault].rewardCollectorAddress, rewardCollectors[vault].rewardToken, rewardCollectors[vault].rewardAmount);
    }
}