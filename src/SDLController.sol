pragma solidity ^0.8.11;

import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import { Unauthorized, IllegalState, IllegalArgument } from "./base/Errors.sol";
import "./interfaces/stakedao/IveSDT.sol";
import "./interfaces/stakedao/IRewardDistributor.sol";
import "./interfaces/snapshot/IDelegateRegistry.sol";
import "./interfaces/stakedao/ILiquidityGauge.sol";

contract SDLController is Initializable, OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  string public constant version = "1.1.0";

  constructor() initializer {}

  function initialize() external initializer {
    __Ownable_init();
  }
}
