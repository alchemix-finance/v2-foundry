// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {AccessControlUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";


import "./base/Errors.sol";

import "./interfaces/IWhitelist.sol";

import "./interfaces/transmuter/ITransmuterV2.sol";
import "./interfaces/transmuter/ITransmuterBuffer.sol";

import "./libraries/FixedPointMath.sol";
import "./libraries/LiquidityMath.sol";
import "./libraries/SafeCast.sol";
import "./libraries/Tick.sol";
import "./libraries/TokenUtils.sol";

/// @title TransmuterV2
///
/// @notice A contract which facilitates the exchange of synthetic assets for their underlying
//          asset. This contract guarantees that synthetic assets are exchanged exactly 1:1
//          for the underlying asset.
contract TransmuterV2 is ITransmuterV2, Initializable, ReentrancyGuardUpgradeable, AccessControlUpgradeable {
  using FixedPointMath for FixedPointMath.Number;
  using Tick for Tick.Cache;

  struct Account {
    // The total number of unexchanged tokens that an account has deposited into the system
    uint256 unexchangedBalance;
    // The total number of exchanged tokens that an account has had credited
    uint256 exchangedBalance;
    // The tick that the account has had their deposit associated in
    uint256 occupiedTick;
  }

  struct UpdateAccountParams {
    // The owner address whose account will be modified
    address owner;
    // The amount to change the account's unexchanged balance by
    int256 unexchangedDelta;
    // The amount to change the account's exchanged balance by
    int256 exchangedDelta;
  }

  struct ExchangeCache {
    // The total number of unexchanged tokens that exist at the start of the exchange call
    uint256 totalUnexchanged;
    // The tick which has been satisfied up to at the start of the exchange call
    uint256 satisfiedTick;
    // The head of the active ticks queue at the start of the exchange call
    uint256 ticksHead;
  }

  struct ExchangeState {
    // The position in the buffer of current tick which is being examined
    uint256 examineTick;
    // The total number of unexchanged tokens that currently exist in the system for the current distribution step
    uint256 totalUnexchanged;
    // The tick which has been satisfied up to, inclusive
    uint256 satisfiedTick;
    // The amount of tokens to distribute for the current step
    uint256 distributeAmount;
    // The accumulated weight to write at the new tick after the exchange is completed
    FixedPointMath.Number accumulatedWeight;
    // Reserved for the maximum weight of the current distribution step
    FixedPointMath.Number maximumWeight;
    // Reserved for the dusted weight of the current distribution step
    FixedPointMath.Number dustedWeight;
  }

  struct UpdateAccountCache {
    // The total number of unexchanged tokens that the account held at the start of the update call
    uint256 unexchangedBalance;
    // The total number of exchanged tokens that the account held at the start of the update call
    uint256 exchangedBalance;
    // The tick that the account's deposit occupies at the start of the update call
    uint256 occupiedTick;
    // The total number of unexchanged tokens that exist at the start of the update call
    uint256 totalUnexchanged;
    // The current tick that is being written to
    uint256 currentTick;
  }

  struct UpdateAccountState {
    // The updated unexchanged balance of the account being updated
    uint256 unexchangedBalance;
    // The updated exchanged balance of the account being updated
    uint256 exchangedBalance;
    // The updated total unexchanged balance
    uint256 totalUnexchanged;
  }

  address public constant ZERO_ADDRESS = address(0);

  /// @dev The identifier of the role which maintains other roles.
  bytes32 public constant ADMIN = keccak256("ADMIN");

  /// @dev The identifier of the sentinel role
  bytes32 public constant SENTINEL = keccak256("SENTINEL");

  /// @inheritdoc ITransmuterV2
  string public constant override version = "2.2.1";

  /// @dev the synthetic token to be transmuted
  address public syntheticToken;

  /// @dev the underlying token to be received
  address public override underlyingToken;

  /// @dev The total amount of unexchanged tokens which are held by all accounts.
  uint256 public totalUnexchanged;

  /// @dev The total amount of tokens which are in the auxiliary buffer.
  uint256 public totalBuffered;

  /// @dev A mapping specifying all of the accounts.
  mapping(address => Account) private accounts;

  // @dev The tick buffer which stores all of the tick information along with the tick that is
  //      currently being written to. The "current" tick is the tick at the buffer write position.
  Tick.Cache private ticks;

  // The tick which has been satisfied up to, inclusive.
  uint256 private satisfiedTick;

  /// @dev contract pause state
  bool public isPaused;

  /// @dev the source of the exchanged collateral
  address public buffer;

  /// @dev The address of the external whitelist contract.
  address public override whitelist;

  /// @dev The amount of decimal places needed to normalize collateral to debtToken
  uint256 public override conversionFactor;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

  function initialize(
    address _syntheticToken,
    address _underlyingToken,
    address _buffer,
    address _whitelist
  ) external initializer {
    _setupRole(ADMIN, msg.sender);
    _setRoleAdmin(ADMIN, ADMIN);
    _setRoleAdmin(SENTINEL, ADMIN);

    syntheticToken = _syntheticToken;
    underlyingToken = _underlyingToken;
    uint8 debtTokenDecimals = TokenUtils.expectDecimals(syntheticToken);
    uint8 underlyingTokenDecimals = TokenUtils.expectDecimals(underlyingToken);
    conversionFactor = 10**(debtTokenDecimals - underlyingTokenDecimals);
    buffer = _buffer;
    // Push a blank tick to function as a sentinel value in the active ticks queue.
    ticks.next();

    isPaused = false;
    whitelist = _whitelist;
  }

  /// @dev A modifier which checks if caller is an alchemist.
  modifier onlyBuffer() {
    if (msg.sender != buffer) {
      revert Unauthorized();
    }
    _;
  }

  /// @dev A modifier which checks if caller is a sentinel or admin.
  modifier onlySentinelOrAdmin() {
    if (!hasRole(SENTINEL, msg.sender) && !hasRole(ADMIN, msg.sender)) {
      revert Unauthorized();
    }
    _;
  }

  /// @dev A modifier which checks whether the transmuter is unpaused.
  modifier notPaused() {
    if (isPaused) {
      revert IllegalState();
    }
    _;
  }

  function _onlyAdmin() internal view {
    if (!hasRole(ADMIN, msg.sender)) {
      revert Unauthorized();
    }
  }

  function setCollateralSource(address _newCollateralSource) external {
    _onlyAdmin();
    buffer = _newCollateralSource;
    emit SetNewCollateralSource(_newCollateralSource);
  }

  function setPause(bool pauseState) external onlySentinelOrAdmin {
    isPaused = pauseState;
    emit Paused(isPaused);
  }

  /// @inheritdoc ITransmuterV2
  function deposit(uint256 amount, address owner) external override nonReentrant {
    _onlyWhitelisted();
    _updateAccount(
      UpdateAccountParams({
        owner: owner,
        unexchangedDelta: SafeCast.toInt256(amount),
        exchangedDelta: 0
      })
    );
    TokenUtils.safeTransferFrom(syntheticToken, msg.sender, address(this), amount);
    emit Deposit(msg.sender, owner, amount);
  }

  /// @inheritdoc ITransmuterV2
  function withdraw(uint256 amount, address recipient) external override nonReentrant {
    _onlyWhitelisted();
    _updateAccount(
      UpdateAccountParams({ 
        owner: msg.sender,
        unexchangedDelta: -SafeCast.toInt256(amount),
        exchangedDelta: 0
      })
    );
    TokenUtils.safeTransfer(syntheticToken, recipient, amount);
    emit Withdraw(msg.sender, recipient, amount);
  }

  /// @inheritdoc ITransmuterV2
  function claim(uint256 amount, address recipient) external override nonReentrant {
    _onlyWhitelisted();
    _updateAccount(
      UpdateAccountParams({
        owner: msg.sender,
        unexchangedDelta: 0,
        exchangedDelta: -SafeCast.toInt256(_normalizeUnderlyingTokensToDebt(amount))
      })
    );
    TokenUtils.safeBurn(syntheticToken, _normalizeUnderlyingTokensToDebt(amount));
    ITransmuterBuffer(buffer).withdraw(underlyingToken, amount, recipient);
    emit Claim(msg.sender, recipient, amount);
  }

  /// @inheritdoc ITransmuterV2
  function exchange(uint256 amount) external override nonReentrant onlyBuffer notPaused {
    uint256 normaizedAmount = _normalizeUnderlyingTokensToDebt(amount);

    if (totalUnexchanged == 0) {
      totalBuffered += normaizedAmount;
      emit Exchange(msg.sender, amount);
      return;
    }

    // Push a storage reference to the current tick.
    Tick.Info storage current = ticks.current();

    ExchangeCache memory cache = ExchangeCache({
      totalUnexchanged: totalUnexchanged,
      satisfiedTick: satisfiedTick,
      ticksHead: ticks.head
    });

    ExchangeState memory state = ExchangeState({
      examineTick: cache.ticksHead,
      totalUnexchanged: cache.totalUnexchanged,
      satisfiedTick: cache.satisfiedTick,
      distributeAmount: normaizedAmount,
      accumulatedWeight: current.accumulatedWeight,
      maximumWeight: FixedPointMath.encode(0),
      dustedWeight: FixedPointMath.encode(0)
    });

    // Distribute the buffered tokens as part of the exchange.
    state.distributeAmount += totalBuffered;
    totalBuffered = 0;

    // Push a storage reference to the next tick to write to.
    Tick.Info storage next = ticks.next();

    // Only iterate through the active ticks queue when it is not empty.
    while (state.examineTick != 0) {
      // Check if there is anything left to distribute.
      if (state.distributeAmount == 0) {
        break;
      }

      Tick.Info storage examineTickData = ticks.get(state.examineTick);

      // Add the weight for the distribution step to the accumulated weight.
      state.accumulatedWeight = state.accumulatedWeight.add(
        FixedPointMath.rational(state.distributeAmount, state.totalUnexchanged)
      );

      // Clear the distribute amount.
      state.distributeAmount = 0;

      // Calculate the current maximum weight in the system.
      state.maximumWeight = state.accumulatedWeight.sub(examineTickData.accumulatedWeight);

      // Check if there exists at least one account which is completely satisfied..
      if (state.maximumWeight.n < FixedPointMath.ONE) {
        break;
      }

      // Calculate how much weight of the distributed weight is dust.
      state.dustedWeight = FixedPointMath.Number(state.maximumWeight.n - FixedPointMath.ONE);

      // Calculate how many tokens to distribute in the next step. These are tokens from any tokens which
      // were over allocated to accounts occupying the tick with the maximum weight.
      state.distributeAmount = LiquidityMath.calculateProduct(examineTickData.totalBalance, state.dustedWeight);

      // Remove the tokens which were completely exchanged from the total unexchanged balance.
      state.totalUnexchanged -= examineTickData.totalBalance;

      // Write that all ticks up to and including the examined tick have been satisfied.
      state.satisfiedTick = state.examineTick;

      // Visit the next active tick. This is equivalent to popping the head of the active ticks queue.
      state.examineTick = examineTickData.next;
    }

    // Write the accumulated weight to the next tick.
    next.accumulatedWeight = state.accumulatedWeight;

    if (cache.totalUnexchanged != state.totalUnexchanged) {
      totalUnexchanged = state.totalUnexchanged;
    }

    if (cache.satisfiedTick != state.satisfiedTick) {
      satisfiedTick = state.satisfiedTick;
    }

    if (cache.ticksHead != state.examineTick) {
      ticks.head = state.examineTick;
    }

    if (state.distributeAmount > 0) {
      totalBuffered += state.distributeAmount;
    }

    emit Exchange(msg.sender, amount);
  }

  /// @inheritdoc ITransmuterV2
  function getUnexchangedBalance(address owner) external view override returns (uint256) {
    Account storage account = accounts[owner];

    if (account.occupiedTick <= satisfiedTick) {
      return 0;
    }

    uint256 unexchangedBalance = account.unexchangedBalance;

    uint256 exchanged = LiquidityMath.calculateProduct(
      unexchangedBalance,
      ticks.getWeight(account.occupiedTick, ticks.position)
    );

    unexchangedBalance -= exchanged;

    return unexchangedBalance;
  }

  /// @inheritdoc ITransmuterV2
  function getExchangedBalance(address owner) external view override returns (uint256 exchangedBalance) {
    return _getExchangedBalance(owner);
  }

  function getClaimableBalance(address owner) external view override returns (uint256 claimableBalance) {
    return _normalizeDebtTokensToUnderlying(_getExchangedBalance(owner));
  }

  /// @dev Updates an account.
  ///
  /// @param params The call parameters.
  function _updateAccount(UpdateAccountParams memory params) internal {
    Account storage account = accounts[params.owner];

    UpdateAccountCache memory cache = UpdateAccountCache({
      unexchangedBalance: account.unexchangedBalance,
      exchangedBalance: account.exchangedBalance,
      occupiedTick: account.occupiedTick,
      totalUnexchanged: totalUnexchanged,
      currentTick: ticks.position
    });

    UpdateAccountState memory state = UpdateAccountState({
      unexchangedBalance: cache.unexchangedBalance,
      exchangedBalance: cache.exchangedBalance,
      totalUnexchanged: cache.totalUnexchanged
    });

    // Updating an account is broken down into five steps:
    // 1). Synchronize the account if it previously occupied a satisfied tick
    // 2). Update the account balances to account for exchanged tokens, if any
    // 3). Apply the deltas to the account balances
    // 4). Update the previously occupied and or current tick's liquidity
    // 5). Commit changes to the account and global state when needed

    // Step one:
    // ---------
    // Check if the tick that the account was occupying previously was satisfied. If it was, we acknowledge
    // that all of the tokens were exchanged.
    if (state.unexchangedBalance > 0 && satisfiedTick >= cache.occupiedTick) {
      state.unexchangedBalance = 0;
      state.exchangedBalance += cache.unexchangedBalance;
    }

    // Step Two:
    // ---------
    // Calculate how many tokens were exchanged since the last update.
    if (state.unexchangedBalance > 0) {
      uint256 exchanged = LiquidityMath.calculateProduct(
        state.unexchangedBalance,
        ticks.getWeight(cache.occupiedTick, cache.currentTick)
      );

      state.totalUnexchanged -= exchanged;
      state.unexchangedBalance -= exchanged;
      state.exchangedBalance += exchanged;
    }

    // Step Three:
    // -----------
    // Apply the unexchanged and exchanged deltas to the state.
    state.totalUnexchanged = LiquidityMath.addDelta(state.totalUnexchanged, params.unexchangedDelta);
    state.unexchangedBalance = LiquidityMath.addDelta(state.unexchangedBalance, params.unexchangedDelta);
    state.exchangedBalance = LiquidityMath.addDelta(state.exchangedBalance, params.exchangedDelta);

    // Step Four:
    // ----------
    // The following is a truth table relating various values which in combinations specify which logic branches
    // need to be executed in order to update liquidity in the previously occupied and or current tick.
    //
    // Some states are not obtainable and are just discarded by setting all the branches to false.
    //
    // | P | C | M | Modify Liquidity | Add Liquidity | Subtract Liquidity |
    // |---|---|---|------------------|---------------|--------------------|
    // | F | F | F | F                | F             | F                  |
    // | F | F | T | F                | F             | F                  |
    // | F | T | F | F                | T             | F                  |
    // | F | T | T | F                | T             | F                  |
    // | T | F | F | F                | F             | T                  |
    // | T | F | T | F                | F             | T                  |
    // | T | T | F | T                | F             | F                  |
    // | T | T | T | F                | T             | T                  |
    //
    // | Branch             | Reduction |
    // |--------------------|-----------|
    // | Modify Liquidity   | PCM'      |
    // | Add Liquidity      | P'C + CM  |
    // | Subtract Liquidity | PC' + PM  |

    bool previouslyActive = cache.unexchangedBalance > 0;
    bool currentlyActive = state.unexchangedBalance > 0;
    bool migrate = cache.occupiedTick != cache.currentTick;

    bool modifyLiquidity = previouslyActive && currentlyActive && !migrate;

    if (modifyLiquidity) {
      Tick.Info storage tick = ticks.get(cache.occupiedTick);

      // Consolidate writes to save gas.
      uint256 totalBalance = tick.totalBalance;
      totalBalance -= cache.unexchangedBalance;
      totalBalance += state.unexchangedBalance;
      tick.totalBalance = totalBalance;
    } else {
      bool addLiquidity = (!previouslyActive && currentlyActive) || (currentlyActive && migrate);
      bool subLiquidity = (previouslyActive && !currentlyActive) || (previouslyActive && migrate);

      if (addLiquidity) {
        Tick.Info storage tick = ticks.get(cache.currentTick);

        if (tick.totalBalance == 0) {
          ticks.addLast(cache.currentTick);
        }

        tick.totalBalance += state.unexchangedBalance;
      }

      if (subLiquidity) {
        Tick.Info storage tick = ticks.get(cache.occupiedTick);
        tick.totalBalance -= cache.unexchangedBalance;

        if (tick.totalBalance == 0) {
          ticks.remove(cache.occupiedTick);
        }
      }
    }

    // Step Five:
    // ----------
    // Commit the changes to the account.
    if (cache.unexchangedBalance != state.unexchangedBalance) {
      account.unexchangedBalance = state.unexchangedBalance;
    }

    if (cache.exchangedBalance != state.exchangedBalance) {
      account.exchangedBalance = state.exchangedBalance;
    }

    if (cache.totalUnexchanged != state.totalUnexchanged) {
      totalUnexchanged = state.totalUnexchanged;
    }

    if (cache.occupiedTick != cache.currentTick) {
      account.occupiedTick = cache.currentTick;
    }
  }

  /// @dev Checks the whitelist for msg.sender.
  ///
  /// @notice Reverts if msg.sender is not in the whitelist.
  function _onlyWhitelisted() internal view {
    // Check if the message sender is an EOA. In the future, this potentially may break. It is important that
    // functions which rely on the whitelist not be explicitly vulnerable in the situation where this no longer
    // holds true.
    if (tx.origin != msg.sender) {
      // Only check the whitelist for calls from contracts.
      if (!IWhitelist(whitelist).isWhitelisted(msg.sender)) {
        revert Unauthorized();
      }
    }
  }

  /// @dev Normalize `amount` of `underlyingToken` to a value which is comparable to units of the debt token.
  ///
  /// @param amount          The amount of the debt token.
  ///
  /// @return The normalized amount.
  function _normalizeUnderlyingTokensToDebt(uint256 amount) internal view returns (uint256) {
    return amount * conversionFactor;
  }

  /// @dev Normalize `amount` of the debt token to a value which is comparable to units of `underlyingToken`.
  ///
  /// @dev This operation will result in truncation of some of the least significant digits of `amount`. This
  ///      truncation amount will be the least significant N digits where N is the difference in decimals between
  ///      the debt token and the underlying token.
  ///
  /// @param amount          The amount of the debt token.
  ///
  /// @return The normalized amount.
  function _normalizeDebtTokensToUnderlying(uint256 amount) internal view returns (uint256) {
    return amount / conversionFactor;
  }

  function _getExchangedBalance(address owner) internal view returns (uint256 exchangedBalance) {
    Account storage account = accounts[owner];

    if (account.occupiedTick <= satisfiedTick) {
      exchangedBalance = account.exchangedBalance;
      exchangedBalance += account.unexchangedBalance;
      return exchangedBalance;
    }

    exchangedBalance = account.exchangedBalance;

    uint256 exchanged = LiquidityMath.calculateProduct(
      account.unexchangedBalance,
      ticks.getWeight(account.occupiedTick, ticks.position)
    );

    exchangedBalance += exchanged;

    return exchangedBalance;
  }
}
