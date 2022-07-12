pragma solidity ^0.8.13;

import { IAlchemistV2AdminActions } from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import { IAlchemistV2State } from "../interfaces/alchemist/IAlchemistV2State.sol";
import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import { ITokenAdapter } from "../interfaces/ITokenAdapter.sol";
import { YieldTokenMock } from "./YieldTokenMock.sol";

contract AlchemistV2Mock {
  using SafeERC20 for IERC20;

  bool public pause;
  address public rewards;

  mapping(address => IAlchemistV2State.YieldTokenParams) internal yieldTokens;

  constructor(address _rewards) {
    rewards = _rewards;
  }

  function setYieldTokenParameters(address yieldToken, IAlchemistV2AdminActions.YieldTokenConfig calldata config) external {
    yieldTokens[yieldToken] = IAlchemistV2State.YieldTokenParams({
      decimals: YieldTokenMock(yieldToken).decimals(),
      underlyingToken: address(YieldTokenMock(yieldToken).underlying()),
      adapter: config.adapter,
      maximumLoss: config.maximumLoss,
      maximumExpectedValue: config.maximumExpectedValue,
      creditUnlockRate: config.creditUnlockBlocks,
      activeBalance: 0,
      harvestableBalance: 0,
      totalShares: 0,
      expectedValue: 0,
      accruedWeight: 0,
      pendingCredit: 0,
      distributedCredit: 0,
      lastDistributionBlock: block.number,
      enabled: true
    });
  }

  function setEnabledYieldToken(address yieldToken, bool flag) external {
    yieldTokens[yieldToken].enabled = flag;
  }

  function deposit(address yieldToken, uint256 _amount) external {
    IAlchemistV2State.YieldTokenParams storage yToken = yieldTokens[yieldToken];
    yToken.activeBalance += _amount;
    yToken.expectedValue = (ITokenAdapter(yToken.adapter).price() * yToken.activeBalance) / 10**yToken.decimals;
    yieldTokens[yieldToken] = yToken;
    IERC20(yieldToken).safeTransferFrom(msg.sender, address(this), _amount);
  }

  function harvest(address yieldToken, uint256 minimumAmountOut) external {
    IAlchemistV2State.YieldTokenParams storage yToken = yieldTokens[yieldToken];
    uint256 currentValue = (ITokenAdapter(yToken.adapter).price() * yToken.activeBalance) / 10**yToken.decimals;
    if (currentValue > yToken.expectedValue) {
      YieldTokenMock(yieldToken).redeem(currentValue - yToken.expectedValue);
      uint256 redeemed = ((currentValue - yToken.expectedValue) * 10**yToken.decimals) /
        ITokenAdapter(yToken.adapter).price();
      yToken.activeBalance -= redeemed;
    }
  }

  function getYieldTokenParameters(address yieldToken)
    external
    view
    returns (IAlchemistV2State.YieldTokenParams memory yieldTokenParams)
  {
    return yieldTokens[yieldToken];
  }
}
