pragma solidity ^0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TokenUtils} from "../libraries/TokenUtils.sol";
import "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

import {IRewardCollector} from "../interfaces/IRewardCollector.sol";
import {IRewardRouter} from "../interfaces/IRewardRouter.sol";
import {IStaticAToken} from "../interfaces/external/aave/IStaticAToken.sol";

import {Unauthorized, IllegalState, IllegalArgument} from "../base/ErrorMessages.sol";

struct Reward {
    address rewardCollectorAddress;
    uint256 rewardAmount;
    uint256 rewardPaid;
    uint256 rewardTimeframe;
    uint256 lastRewardTimestamp;
}

/// @title  Reward Router
/// @author Alchemix Finance
contract RewardRouter is IRewardRouter, Ownable {
    string public override version = "1.1.0";
    uint256 public constant BPS = 10000;

    uint256 public slippageBPS = 9500;

    /// @dev A mapping of the yield tokens to their respective reward collectors
    mapping(address => Reward) public rewards;

    ///@dev Address of the approved harvester
    address harvester;

    constructor() Ownable() {}

    /// @dev Distributes grant rewards and triggers reward collector to claim and donate
    function distributeRewards(address vault) external returns (uint256) {
        require(msg.sender == harvester, "Caller not harvester");

        // If vault is set to receive rewards from grants, send amount to reward collector to donate
        if (rewards[vault].rewardAmount > 0) {
            // Calculates ratio of timeframe to time since last harvest
            // Uses this ratio to determine partial reward amount or extra reward amount
            uint256 blocksSinceLastReward = block.timestamp - rewards[vault].lastRewardTimestamp;
            uint256 maxReward = rewards[vault].rewardAmount - rewards[vault].rewardPaid;
            uint256 currentReward = rewards[vault].rewardAmount * blocksSinceLastReward / rewards[vault].rewardTimeframe;
            uint256 amountToSend = currentReward > maxReward ? maxReward : currentReward;

            TokenUtils.safeTransfer(IRewardCollector(rewards[vault].rewardCollectorAddress).rewardToken(), rewards[vault].rewardCollectorAddress, amountToSend);
            rewards[vault].lastRewardTimestamp = block.timestamp;
            rewards[vault].rewardPaid += amountToSend;

            if (rewards[vault].rewardPaid == rewards[vault].rewardAmount) {
                rewards[vault].rewardAmount = 0;
                rewards[vault].rewardPaid = 0;
            }
        }

        return IRewardCollector(rewards[vault].rewardCollectorAddress).claimAndDonateRewards(vault, IRewardCollector(rewards[vault].rewardCollectorAddress).getExpectedExchange() * slippageBPS / BPS);
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
        uint256 rewardTimeframe
    ) external onlyOwner {
        rewards[vault] = Reward(rewardCollectorAddress, rewardAmount, 0, rewardTimeframe, block.timestamp);
    }

    /// @dev Set the reward collector address for a given vault
    function setRewardCollectorAddress(address vault, address rewardCollectorAddress) external onlyOwner {
        rewards[vault].rewardCollectorAddress = rewardCollectorAddress;
    }

    /// @dev Set the reward token amount for a given vault
    function setRewardAmount(address vault, uint256 rewardAmount) external onlyOwner {
        rewards[vault].rewardAmount = rewardAmount;
    }

    /// @dev Set the reward token timeframe for a given vault
    function setRewardTimeframe(address vault, uint256 timeframe) external onlyOwner {
        rewards[vault].rewardTimeframe = timeframe;
    }

    /// @dev Set the allowed slippage
    function setSlippage(uint256 slippage) external onlyOwner {
        slippageBPS = slippage;
    }

    /// @dev Set the harvester address
    function setHarvester(address harvesterAddress) external onlyOwner {
        harvester = harvesterAddress;
    }

    /// @dev Get reward collector params for a given vault
    function getRewardCollector(address vault) external view returns (address, address, uint256, uint256, uint256) {
        if (rewards[vault].rewardCollectorAddress == address(0)) {
            return (address(0), address(0), 0, 0, 0);
        }
        return (
            rewards[vault].rewardCollectorAddress,
            IRewardCollector(rewards[vault].rewardCollectorAddress).rewardToken(),
            rewards[vault].rewardAmount,
            rewards[vault].rewardTimeframe,
            rewards[vault].lastRewardTimestamp
        );
    }
}