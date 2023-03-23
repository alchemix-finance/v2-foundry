pragma solidity ^0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TokenUtils} from "../libraries/TokenUtils.sol";
import "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

import {IRewardCollector} from "../interfaces/IRewardCollector.sol";
import {IRewardRouter} from "../interfaces/IRewardRouter.sol";
import {IStaticAToken} from "../interfaces/external/aave/IStaticAToken.sol";

import {Unauthorized, IllegalState, IllegalArgument} from "../base/ErrorMessages.sol";

struct RewardCollector {
    address rewardCollectorAddress;
    uint256 rewardAmount;
    uint256 rewardTimeframe;
    uint256 lastRewardBlock;
}

/// @title  Reward Router
/// @author Alchemix Finance
contract RewardRouter is IRewardRouter, Ownable {
    string public override version = "1.0.0";
    uint256 public constant BPS = 10000;

    uint256 public slippageBPS = 9500;

    /// @dev A mapping of the yield tokens to their respective reward collectors
    mapping(address => RewardCollector) public rewardCollectors;

    constructor() Ownable() {}

    /// @dev Distributes grant rewards and triggers reward collector to claim and donate
    function distributeRewards(address vault) external returns (uint256) {
        // If vault is set to receive rewards from grants, send amount to reward collector to donate
        if (rewardCollectors[vault].rewardAmount > 0) {
            // Calculates ratio of timeframe to time since last harvest
            // Uses this ratio to determine partial reward amount or extra reward amount
            uint256 blocksSinceLastReward = block.number - rewardCollectors[vault].lastRewardBlock;
            uint256 amountToSend = rewardCollectors[vault].rewardAmount * blocksSinceLastReward / rewardCollectors[vault].rewardTimeframe;
            TokenUtils.safeTransfer(IRewardCollector(rewardCollectors[vault].rewardCollectorAddress).rewardToken(), rewardCollectors[vault].rewardCollectorAddress, amountToSend);
            rewardCollectors[vault].lastRewardBlock = block.number;
        }

        return IRewardCollector(rewardCollectors[vault].rewardCollectorAddress).claimAndDonateRewards(vault, IRewardCollector(rewardCollectors[vault].rewardCollectorAddress).getExpectedExchange(vault) * slippageBPS / BPS);
    }

    /// @dev Sweeps reward tokens to recipient
    ///
    /// @notice This contract is stocked with reward tokens from grants. This function is to retract excess tokens.
    function sweepTokens(address token, address recipient) external onlyOwner {
        TokenUtils.safeTransfer(token, recipient, TokenUtils.safeBalanceOf(token, address(this)));
    }

    /// @dev Add reward collector params to a map of yield tokens
    function addVault(
        address vault,
        address rewardCollectorAddress,
        uint256 rewardAmount,
        uint256 rewardTimeframe,
        uint256 lastRewardBlock
    ) external onlyOwner {
        rewardCollectors[vault] = RewardCollector(rewardCollectorAddress, rewardAmount, rewardTimeframe, lastRewardBlock);
    }

    /// @dev Set the reward collector address for a given vault
    function setRewardCollectorAddress(address vault, address rewardCollectorAddress) external onlyOwner {
        rewardCollectors[vault].rewardCollectorAddress = rewardCollectorAddress;
    }

    /// @dev Set the reward token amount for a given vault
    function setRewardAmount(address vault, uint256 rewardAmount) external onlyOwner {
        rewardCollectors[vault].rewardAmount = rewardAmount;
    }

    /// @dev Set the reward token timeframe for a given vault
    function setRewardTimeframe(address vault, uint256 timeframe) external onlyOwner {
        rewardCollectors[vault].rewardTimeframe = timeframe;
    }

    /// @dev Set the allowed slippage
    function setSlippage(uint256 slippage) external onlyOwner {
        slippageBPS = slippage;
    }

    /// @dev Get reward collector params for a given vault
    function getRewardCollector(address vault) external view returns (address, address, uint256, uint256, uint256) {
        return (
            rewardCollectors[vault].rewardCollectorAddress,
            IRewardCollector(rewardCollectors[vault].rewardCollectorAddress).rewardToken(),
            rewardCollectors[vault].rewardAmount,
            rewardCollectors[vault].rewardTimeframe,
            rewardCollectors[vault].lastRewardBlock
        );
    }
}