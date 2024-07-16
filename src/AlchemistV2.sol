// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {Unauthorized, IllegalState, IllegalArgument} from "./base/Errors.sol";

import "./base/Multicall.sol";
import "./base/Mutex.sol";

import "./interfaces/IAlchemistV2.sol";
import "./interfaces/IERC20TokenReceiver.sol";
import "./interfaces/ITokenAdapter.sol";
import "./interfaces/IAlchemicToken.sol";
import "./interfaces/IWhitelist.sol";
import "./interfaces/IRewardCollector.sol";
import "./interfaces/external/vesper/IVesperRewards.sol";
import "./interfaces/external/vesper/IVesperPool.sol";

import "./libraries/SafeCast.sol";
import "./libraries/Sets.sol";
import "./libraries/TokenUtils.sol";
import "./libraries/Limiters.sol";

/// @title  AlchemistV2
/// @author Alchemix Finance
contract AlchemistV2 is IAlchemistV2, Initializable, Multicall, Mutex {
    using Limiters for Limiters.LinearGrowthLimiter;
    using Sets for Sets.AddressSet;

    /// @notice A user account.
    struct Account {
        // A signed value which represents the current amount of debt or credit that the account has accrued.
        // Positive values indicate debt, negative values indicate credit.
        int256 debt;
        // The share balances for each yield token.
        mapping(address => uint256) balances;
        // The last values recorded for accrued weights for each yield token.
        mapping(address => uint256) lastAccruedWeights;
        // The set of yield tokens that the account has deposited into the system.
        Sets.AddressSet depositedTokens;
        // The allowances for mints.
        mapping(address => uint256) mintAllowances;
        // The allowances for withdrawals.
        mapping(address => mapping(address => uint256)) withdrawAllowances;
    }

    /// @notice The number of basis points there are to represent exactly 100%.
    uint256 public constant BPS = 10_000;

    /// @notice The scalar used for conversion of integral numbers to fixed point numbers. Fixed point numbers in this
    ///         implementation have 18 decimals of resolution, meaning that 1 is represented as 1e18, 0.5 is
    ///         represented as 5e17, and 2 is represented as 2e18.
    uint256 public constant FIXED_POINT_SCALAR = 1e18;

    /// @inheritdoc IAlchemistV2Immutables
    string public constant override version = "2.2.8";

    /// @inheritdoc IAlchemistV2Immutables
    address public override debtToken;

    /// @inheritdoc IAlchemistV2State
    address public override admin;

    /// @inheritdoc IAlchemistV2State
    address public override pendingAdmin;

    /// @inheritdoc IAlchemistV2State
    mapping(address => bool) public override sentinels;

    /// @inheritdoc IAlchemistV2State
    mapping(address => bool) public override keepers;

    /// @inheritdoc IAlchemistV2State
    address public override transmuter;

    /// @inheritdoc IAlchemistV2State
    uint256 public override minimumCollateralization;

    /// @inheritdoc IAlchemistV2State
    uint256 public override protocolFee;

    /// @inheritdoc IAlchemistV2State
    address public override protocolFeeReceiver;

    /// @inheritdoc IAlchemistV2State
    address public override whitelist;

    /// @dev A linear growth function that limits the amount of debt-token minted.
    Limiters.LinearGrowthLimiter private _mintingLimiter;

    // @dev The repay limiters for each underlying token.
    mapping(address => Limiters.LinearGrowthLimiter) private _repayLimiters;

    // @dev The liquidation limiters for each underlying token.
    mapping(address => Limiters.LinearGrowthLimiter) private _liquidationLimiters;

    /// @dev Accounts mapped by the address that owns them.
    mapping(address => Account) private _accounts;

    /// @dev Underlying token parameters mapped by token address.
    mapping(address => UnderlyingTokenParams) private _underlyingTokens;

    /// @dev Yield token parameters mapped by token address.
    mapping(address => YieldTokenParams) private _yieldTokens;

    /// @dev An iterable set of the underlying tokens that are supported by the system.
    Sets.AddressSet private _supportedUnderlyingTokens;

    /// @dev An iterable set of the yield tokens that are supported by the system.
    Sets.AddressSet private _supportedYieldTokens;

    /// @inheritdoc IAlchemistV2State
    address public override transferAdapter;

    constructor() initializer {}

    /// @inheritdoc IAlchemistV2State
    function getYieldTokensPerShare(address yieldToken) external view override returns (uint256) {
        return convertSharesToYieldTokens(yieldToken, 10**_yieldTokens[yieldToken].decimals);
    }

    /// @inheritdoc IAlchemistV2State
    function getUnderlyingTokensPerShare(address yieldToken) external view override returns (uint256) {
        return convertSharesToUnderlyingTokens(yieldToken, 10**_yieldTokens[yieldToken].decimals);
    }

    /// @inheritdoc IAlchemistV2State
    function getSupportedUnderlyingTokens() external view override returns (address[] memory) {
        return _supportedUnderlyingTokens.values;
    }

    /// @inheritdoc IAlchemistV2State
    function getSupportedYieldTokens() external view override returns (address[] memory) {
        return _supportedYieldTokens.values;
    }

    /// @inheritdoc IAlchemistV2State
    function isSupportedUnderlyingToken(address underlyingToken) external view override returns (bool) {
        return _supportedUnderlyingTokens.contains(underlyingToken);
    }

    /// @inheritdoc IAlchemistV2State
    function isSupportedYieldToken(address yieldToken) external view override returns (bool) {
        return _supportedYieldTokens.contains(yieldToken);
    }

    /// @inheritdoc IAlchemistV2State
    function accounts(address owner)
        external view override
        returns (
            int256 debt,
            address[] memory depositedTokens
        )
    {
        Account storage account = _accounts[owner];

        return (
            _calculateUnrealizedDebt(owner),
            account.depositedTokens.values
        );
    }

    /// @inheritdoc IAlchemistV2State
    function positions(address owner, address yieldToken)
        external view override
        returns (
            uint256 shares,
            uint256 lastAccruedWeight
        )
    {
        Account storage account = _accounts[owner];
        return (account.balances[yieldToken], account.lastAccruedWeights[yieldToken]);
    }

    /// @inheritdoc IAlchemistV2State
    function mintAllowance(address owner, address spender)
        external view override
        returns (uint256)
    {
        Account storage account = _accounts[owner];
        return account.mintAllowances[spender];
    }

    /// @inheritdoc IAlchemistV2State
    function withdrawAllowance(address owner, address spender, address yieldToken)
        external view override
        returns (uint256)
    {
        Account storage account = _accounts[owner];
        return account.withdrawAllowances[spender][yieldToken];
    }

    /// @inheritdoc IAlchemistV2State
    function getUnderlyingTokenParameters(address underlyingToken)
        external view override
        returns (UnderlyingTokenParams memory)
    {
        return _underlyingTokens[underlyingToken];
    }

    /// @inheritdoc IAlchemistV2State
    function getYieldTokenParameters(address yieldToken)
        external view override
        returns (YieldTokenParams memory)
    {
        return _yieldTokens[yieldToken];
    }

    /// @inheritdoc IAlchemistV2State
    function getMintLimitInfo()
        external view override
        returns (
            uint256 currentLimit,
            uint256 rate,
            uint256 maximum
        )
    {
        return (
            _mintingLimiter.get(),
            _mintingLimiter.rate,
            _mintingLimiter.maximum
        );
    }

    /// @inheritdoc IAlchemistV2State
    function getRepayLimitInfo(address underlyingToken)
        external view override
        returns (
            uint256 currentLimit,
            uint256 rate,
            uint256 maximum
        )
    {
        Limiters.LinearGrowthLimiter storage limiter = _repayLimiters[underlyingToken];
        return (
            limiter.get(),
            limiter.rate,
            limiter.maximum
        );
    }

    /// @inheritdoc IAlchemistV2State
    function getLiquidationLimitInfo(address underlyingToken)
        external view override
        returns (
            uint256 currentLimit,
            uint256 rate,
            uint256 maximum
        )
    {
        Limiters.LinearGrowthLimiter storage limiter = _liquidationLimiters[underlyingToken];
        return (
            limiter.get(),
            limiter.rate,
            limiter.maximum
        );
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function initialize(InitializationParams memory params) external initializer {
        _checkArgument(params.protocolFee <= BPS);

        debtToken                = params.debtToken;
        admin                    = params.admin;
        transmuter               = params.transmuter;
        minimumCollateralization = params.minimumCollateralization;
        protocolFee              = params.protocolFee;
        protocolFeeReceiver      = params.protocolFeeReceiver;
        whitelist                = params.whitelist;

        _mintingLimiter = Limiters.createLinearGrowthLimiter(
            params.mintingLimitMaximum,
            params.mintingLimitBlocks,
            params.mintingLimitMinimum
        );

        emit AdminUpdated(admin);
        emit TransmuterUpdated(transmuter);
        emit MinimumCollateralizationUpdated(minimumCollateralization);
        emit ProtocolFeeUpdated(protocolFee);
        emit MintingLimitUpdated(params.mintingLimitMaximum, params.mintingLimitBlocks);
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function setPendingAdmin(address value) external override {
        _onlyAdmin();
        pendingAdmin = value;
        emit PendingAdminUpdated(value);
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function acceptAdmin() external override {
        _checkState(pendingAdmin != address(0));

        if (msg.sender != pendingAdmin) {
            revert Unauthorized();
        }

        admin = pendingAdmin;
        pendingAdmin = address(0);

        emit AdminUpdated(admin);
        emit PendingAdminUpdated(address(0));
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function setSentinel(address sentinel, bool flag) external override {
        _onlyAdmin();
        sentinels[sentinel] = flag;
        emit SentinelSet(sentinel, flag);
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function setKeeper(address keeper, bool flag) external override {
        _onlyAdmin();
        keepers[keeper] = flag;
        emit KeeperSet(keeper, flag);
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function addUnderlyingToken(address underlyingToken, UnderlyingTokenConfig calldata config) external override lock {
        _onlyAdmin();
        _checkState(!_supportedUnderlyingTokens.contains(underlyingToken));

        uint8 tokenDecimals = TokenUtils.expectDecimals(underlyingToken);
        uint8 debtTokenDecimals = TokenUtils.expectDecimals(debtToken);

        _checkArgument(tokenDecimals <= debtTokenDecimals);

        _underlyingTokens[underlyingToken] = UnderlyingTokenParams({
            decimals:         tokenDecimals,
            conversionFactor: 10**(debtTokenDecimals - tokenDecimals),
            enabled:          false
        });

        _repayLimiters[underlyingToken] = Limiters.createLinearGrowthLimiter(
            config.repayLimitMaximum,
            config.repayLimitBlocks,
            config.repayLimitMinimum
        );

        _liquidationLimiters[underlyingToken] = Limiters.createLinearGrowthLimiter(
            config.liquidationLimitMaximum,
            config.liquidationLimitBlocks,
            config.liquidationLimitMinimum
        );

        _supportedUnderlyingTokens.add(underlyingToken);

        emit AddUnderlyingToken(underlyingToken);
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function addYieldToken(address yieldToken, YieldTokenConfig calldata config) external override lock {
        _onlyAdmin();
        _checkArgument(config.maximumLoss <= BPS);
        _checkArgument(config.creditUnlockBlocks > 0);

        _checkState(!_supportedYieldTokens.contains(yieldToken));

        ITokenAdapter adapter = ITokenAdapter(config.adapter);

        _checkState(yieldToken == adapter.token());
        _checkSupportedUnderlyingToken(adapter.underlyingToken());

        _yieldTokens[yieldToken] = YieldTokenParams({
            decimals:              TokenUtils.expectDecimals(yieldToken),
            underlyingToken:       adapter.underlyingToken(),
            adapter:               config.adapter,
            maximumLoss:           config.maximumLoss,
            maximumExpectedValue:  config.maximumExpectedValue,
            creditUnlockRate:      FIXED_POINT_SCALAR / config.creditUnlockBlocks,
            activeBalance:         0,
            harvestableBalance:    0,
            totalShares:           0,
            expectedValue:         0,
            accruedWeight:         0,
            pendingCredit:         0,
            distributedCredit:     0,
            lastDistributionBlock: 0,
            enabled:               false
        });

        _supportedYieldTokens.add(yieldToken);

        TokenUtils.safeApprove(yieldToken, config.adapter, type(uint256).max);
        TokenUtils.safeApprove(adapter.underlyingToken(), config.adapter, type(uint256).max);

        emit AddYieldToken(yieldToken);
        emit TokenAdapterUpdated(yieldToken, config.adapter);
        emit MaximumLossUpdated(yieldToken, config.maximumLoss);
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function setUnderlyingTokenEnabled(address underlyingToken, bool enabled) external override {
        _onlySentinelOrAdmin();
        _checkSupportedUnderlyingToken(underlyingToken);
        _underlyingTokens[underlyingToken].enabled = enabled;
        emit UnderlyingTokenEnabled(underlyingToken, enabled);
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function setYieldTokenEnabled(address yieldToken, bool enabled) external override {
        _onlySentinelOrAdmin();
        _checkSupportedYieldToken(yieldToken);
        _yieldTokens[yieldToken].enabled = enabled;
        emit YieldTokenEnabled(yieldToken, enabled);
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function configureRepayLimit(address underlyingToken, uint256 maximum, uint256 blocks) external override {
        _onlyAdmin();
        _checkSupportedUnderlyingToken(underlyingToken);
        _repayLimiters[underlyingToken].update();
        _repayLimiters[underlyingToken].configure(maximum, blocks);
        emit RepayLimitUpdated(underlyingToken, maximum, blocks);
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function configureLiquidationLimit(address underlyingToken, uint256 maximum, uint256 blocks) external override {
        _onlyAdmin();
        _checkSupportedUnderlyingToken(underlyingToken);
        _liquidationLimiters[underlyingToken].update();
        _liquidationLimiters[underlyingToken].configure(maximum, blocks);
        emit LiquidationLimitUpdated(underlyingToken, maximum, blocks);
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function setTransmuter(address value) external override {
        _onlyAdmin();
        _checkArgument(value != address(0));
        transmuter = value;
        emit TransmuterUpdated(value);
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function setMinimumCollateralization(uint256 value) external override {
        _onlyAdmin();
        _checkArgument(value >= 1e18);
        minimumCollateralization = value;
        emit MinimumCollateralizationUpdated(value);
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function setProtocolFee(uint256 value) external override {
        _onlyAdmin();
        _checkArgument(value <= BPS);
        protocolFee = value;
        emit ProtocolFeeUpdated(value);
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function setProtocolFeeReceiver(address value) external override {
        _onlyAdmin();
        _checkArgument(value != address(0));
        protocolFeeReceiver = value;
        emit ProtocolFeeReceiverUpdated(value);
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function configureMintingLimit(uint256 maximum, uint256 rate) external override {
        _onlyAdmin();
        _mintingLimiter.update();
        _mintingLimiter.configure(maximum, rate);
        emit MintingLimitUpdated(maximum, rate);
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function configureCreditUnlockRate(address yieldToken, uint256 blocks) external override {
        _onlyAdmin();
        _checkArgument(blocks > 0);
        _checkSupportedYieldToken(yieldToken);
        _yieldTokens[yieldToken].creditUnlockRate = FIXED_POINT_SCALAR / blocks;
        emit CreditUnlockRateUpdated(yieldToken, blocks);
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function setTokenAdapter(address yieldToken, address adapter) external override {
        _onlyAdmin();
        _checkState(yieldToken == ITokenAdapter(adapter).token());
        _checkSupportedYieldToken(yieldToken);
        _yieldTokens[yieldToken].adapter = adapter;
        TokenUtils.safeApprove(yieldToken, adapter, type(uint256).max);
        TokenUtils.safeApprove(ITokenAdapter(adapter).underlyingToken(), adapter, type(uint256).max);
        emit TokenAdapterUpdated(yieldToken, adapter);
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function setMaximumExpectedValue(address yieldToken, uint256 value) external override {
        _onlyAdmin();
        _checkSupportedYieldToken(yieldToken);
        _yieldTokens[yieldToken].maximumExpectedValue = value;
        emit MaximumExpectedValueUpdated(yieldToken, value);
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function setMaximumLoss(address yieldToken, uint256 value) external override {
        _onlyAdmin();
        _checkArgument(value <= BPS);
        _checkSupportedYieldToken(yieldToken);

        _yieldTokens[yieldToken].maximumLoss = value;

        emit MaximumLossUpdated(yieldToken, value);
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function snap(address yieldToken) external override lock {
        _onlyAdmin();
        _checkSupportedYieldToken(yieldToken);

        uint256 expectedValue = convertYieldTokensToUnderlying(yieldToken, _yieldTokens[yieldToken].activeBalance);

        _yieldTokens[yieldToken].expectedValue = expectedValue;

        emit Snap(yieldToken, expectedValue);
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function setTransferAdapterAddress(address transferAdapterAddress) external override lock {
        _onlyAdmin();
        transferAdapter = transferAdapterAddress;
    }

    /// @inheritdoc IAlchemistV2AdminActions
    function transferDebtV1(
        address owner, 
        int256 debt
    ) external override lock {
        _onlyTransferAdapter();
        _poke(owner);
        _updateDebt(owner, debt);
        _validate(owner);
    }

    /// @inheritdoc IAlchemistV2Actions
    function approveMint(address spender, uint256 amount) external override {
        _onlyWhitelisted();
        _approveMint(msg.sender, spender, amount);
    }

    /// @inheritdoc IAlchemistV2Actions
    function approveWithdraw(address spender, address yieldToken, uint256 shares) external override {
        _onlyWhitelisted();
        _checkSupportedYieldToken(yieldToken);
        _approveWithdraw(msg.sender, spender, yieldToken, shares);
    }

    /// @inheritdoc IAlchemistV2Actions
    function poke(address owner) external override lock {
        _onlyWhitelisted();
        _preemptivelyHarvestDeposited(owner);
        _distributeUnlockedCreditDeposited(owner);
        _poke(owner);
    }

    /// @inheritdoc IAlchemistV2Actions
    function deposit(
        address yieldToken,
        uint256 amount,
        address recipient
    ) external override lock returns (uint256) {
        _onlyWhitelisted();
        _checkArgument(recipient != address(0));
        _checkSupportedYieldToken(yieldToken);

        // Deposit the yield tokens to the recipient.
        uint256 shares = _deposit(yieldToken, amount, recipient);

        // Transfer tokens from the message sender now that the internal storage updates have been committed.
        TokenUtils.safeTransferFrom(yieldToken, msg.sender, address(this), amount);

        return shares;
    }

    /// @inheritdoc IAlchemistV2Actions
    function depositUnderlying(
        address yieldToken,
        uint256 amount,
        address recipient,
        uint256 minimumAmountOut
    ) external override lock returns (uint256) {
        _onlyWhitelisted();
        _checkArgument(recipient != address(0));
        _checkSupportedYieldToken(yieldToken);

        // Before depositing, the underlying tokens must be wrapped into yield tokens.
        uint256 amountYieldTokens = _wrap(yieldToken, amount, minimumAmountOut);

        // Deposit the yield-tokens to the recipient.
        return _deposit(yieldToken, amountYieldTokens, recipient);
    }

    /// @inheritdoc IAlchemistV2Actions
    function withdraw(
        address yieldToken,
        uint256 shares,
        address recipient
    ) external override lock returns (uint256) {
        _onlyWhitelisted();
        _checkArgument(recipient != address(0));
        _checkSupportedYieldToken(yieldToken);

        // Withdraw the shares from the system.
        uint256 amountYieldTokens = _withdraw(yieldToken, msg.sender, shares, recipient);

        // Transfer the yield tokens to the recipient.
        TokenUtils.safeTransfer(yieldToken, recipient, amountYieldTokens);

        return amountYieldTokens;
    }

    /// @inheritdoc IAlchemistV2Actions
    function withdrawFrom(
        address owner,
        address yieldToken,
        uint256 shares,
        address recipient
    ) external override lock returns (uint256) {
        _onlyWhitelisted();
        _checkArgument(recipient != address(0));
        _checkSupportedYieldToken(yieldToken);

        // Preemptively try and decrease the withdrawal allowance. This will save gas when the allowance is not
        // sufficient for the withdrawal.
        _decreaseWithdrawAllowance(owner, msg.sender, yieldToken, shares);

        // Withdraw the shares from the system.
        uint256 amountYieldTokens = _withdraw(yieldToken, owner, shares, recipient);

        // Transfer the yield tokens to the recipient.
        TokenUtils.safeTransfer(yieldToken, recipient, amountYieldTokens);

        return amountYieldTokens;
    }

    /// @inheritdoc IAlchemistV2Actions
    function withdrawUnderlying(
        address yieldToken,
        uint256 shares,
        address recipient,
        uint256 minimumAmountOut
    ) external override lock returns (uint256) {
        _onlyWhitelisted();
        _checkArgument(recipient != address(0));
        _checkSupportedYieldToken(yieldToken);
        _checkLoss(yieldToken);

        uint256 amountYieldTokens = _withdraw(yieldToken, msg.sender, shares, recipient);

        return _unwrap(yieldToken, amountYieldTokens, recipient, minimumAmountOut);
    }

    /// @inheritdoc IAlchemistV2Actions
    function withdrawUnderlyingFrom(
        address owner,
        address yieldToken,
        uint256 shares,
        address recipient,
        uint256 minimumAmountOut
    ) external override lock returns (uint256) {
        _onlyWhitelisted();
        _checkArgument(recipient != address(0));
        _checkSupportedYieldToken(yieldToken);
        _checkLoss(yieldToken);
        _decreaseWithdrawAllowance(owner, msg.sender, yieldToken, shares);

        uint256 amountYieldTokens = _withdraw(yieldToken, owner, shares, recipient);

        return _unwrap(yieldToken, amountYieldTokens, recipient, minimumAmountOut);
    }

    /// @inheritdoc IAlchemistV2Actions
    function mint(uint256 amount, address recipient) external override lock {
        _onlyWhitelisted();
        _checkArgument(amount > 0);
        _checkArgument(recipient != address(0));

        // Mint tokens from the message sender's account to the recipient.
        _mint(msg.sender, amount, recipient);
    }

    /// @inheritdoc IAlchemistV2Actions
    function mintFrom(
        address owner,
        uint256 amount,
        address recipient
    ) external override lock {
        _onlyWhitelisted();
        _checkArgument(amount > 0);
        _checkArgument(recipient != address(0));

        // Preemptively try and decrease the minting allowance. This will save gas when the allowance is not sufficient
        // for the mint.
        _decreaseMintAllowance(owner, msg.sender, amount);

        // Mint tokens from the owner's account to the recipient.
        _mint(owner, amount, recipient);
    }

    /// @inheritdoc IAlchemistV2Actions
    function burn(uint256 amount, address recipient) external override lock returns (uint256) {
        _onlyWhitelisted();

        _checkArgument(amount > 0);
        _checkArgument(recipient != address(0));

        // Distribute unlocked credit to depositors.
        _distributeUnlockedCreditDeposited(recipient);

        // Update the recipient's account, decrease the debt of the recipient by the number of tokens burned.
        _poke(recipient);

        // Check that the debt is greater than zero.
        //
        // It is possible that the number of debt which is repayable is equal to or less than zero after realizing the
        // credit that was earned since the last update. We do not want to perform a noop so we need to check that the
        // amount of debt to repay is greater than zero.
        int256 debt;
        _checkState((debt = _accounts[recipient].debt) > 0);

        // Limit how much debt can be repaid up to the current amount of debt that the account has. This prevents
        // situations where the user may be trying to repay their entire debt, but it decreases since they send the
        // transaction and causes a revert because burning can never decrease the debt below zero.
        //
        // Casts here are safe because it is asserted that debt is greater than zero.
        uint256 credit = amount > uint256(debt) ? uint256(debt) : amount;

        // Update the recipient's debt.
        _updateDebt(recipient, -SafeCast.toInt256(credit));

        // Burn the tokens from the message sender.
        TokenUtils.safeBurnFrom(debtToken, msg.sender, credit);

        // Increase the global amount of mintable debt tokens.
        // Do this after burning instead of before because mint limit increase is an action beneficial to the user.
        _mintingLimiter.increase(credit);

        emit Burn(msg.sender, credit, recipient);

        return credit;
    }

    /// @inheritdoc IAlchemistV2Actions
    function repay(address underlyingToken, uint256 amount, address recipient) external override lock returns (uint256) {
        _onlyWhitelisted();

        _checkArgument(amount > 0);
        _checkArgument(recipient != address(0));

        _checkSupportedUnderlyingToken(underlyingToken);
        _checkUnderlyingTokenEnabled(underlyingToken);

        // Distribute unlocked credit to depositors.
        _distributeUnlockedCreditDeposited(recipient);

        // Update the recipient's account and decrease the amount of debt incurred.
        _poke(recipient);

        // Check that the debt is greater than zero.
        //
        // It is possible that the amount of debt which is repayable is equal to or less than zero after realizing the
        // credit that was earned since the last update. We do not want to perform a noop so we need to check that the
        // amount of debt to repay is greater than zero.
        int256 debt;
        _checkState((debt = _accounts[recipient].debt) > 0);

        // Determine the maximum amount of underlying tokens that can be repaid.
        //
        // It is implied that this value is greater than zero because `debt` is greater than zero so a noop is not possible
        // beyond this point. Casting the debt to an unsigned integer is also safe because `debt` is greater than zero.
        uint256 maximumAmount = normalizeDebtTokensToUnderlying(underlyingToken, uint256(debt));

        // Limit the number of underlying tokens to repay up to the maximum allowed.
        uint256 actualAmount = amount > maximumAmount ? maximumAmount : amount;

        Limiters.LinearGrowthLimiter storage limiter = _repayLimiters[underlyingToken];

        // Check to make sure that the underlying token repay limit has not been breached.
        uint256 currentRepayLimit = limiter.get();
        if (actualAmount > currentRepayLimit) {
          revert RepayLimitExceeded(underlyingToken, actualAmount, currentRepayLimit);
        }

        uint256 credit = normalizeUnderlyingTokensToDebt(underlyingToken, actualAmount);

        // Update the recipient's debt.
        _updateDebt(recipient, -SafeCast.toInt256(credit));

        // Decrease the amount of the underlying token which is globally available to be repaid.
        limiter.decrease(actualAmount);

        // Transfer the repaid tokens to the transmuter.
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, transmuter, actualAmount);

        // Inform the transmuter that it has received tokens.
        IERC20TokenReceiver(transmuter).onERC20Received(underlyingToken, actualAmount);

        emit Repay(msg.sender, underlyingToken, actualAmount, recipient, credit);

        return actualAmount;
    }

    /// @inheritdoc IAlchemistV2Actions
    function liquidate(
        address yieldToken,
        uint256 shares,
        uint256 minimumAmountOut
    ) external override lock returns (uint256) {
        _onlyWhitelisted();

        _checkArgument(shares > 0);

        YieldTokenParams storage yieldTokenParams = _yieldTokens[yieldToken];
        address underlyingToken = yieldTokenParams.underlyingToken;

        _checkSupportedYieldToken(yieldToken);
        _checkYieldTokenEnabled(yieldToken);
        _checkUnderlyingTokenEnabled(underlyingToken);
        _checkLoss(yieldToken);

        // Calculate the unrealized debt.
        //
        // It is possible that the number of debt which is repayable is equal to or less than zero after realizing the
        // credit that was earned since the last update. We do not want to perform a noop so we need to check that the
        // amount of debt to repay is greater than zero.
        int256 unrealizedDebt;
        _checkState((unrealizedDebt = _calculateUnrealizedDebt(msg.sender)) > 0);

        // Determine the maximum amount of shares that can be liquidated from the unrealized debt.
        //
        // It is implied that this value is greater than zero because `debt` is greater than zero. Casting the debt to an
        // unsigned integer is also safe for this reason.
        uint256 maximumShares = convertUnderlyingTokensToShares(
          yieldToken,
          normalizeDebtTokensToUnderlying(underlyingToken, uint256(unrealizedDebt))
        );

        // Limit the number of shares to liquidate up to the maximum allowed.
        uint256 actualShares = shares > maximumShares ? maximumShares : shares;

        // Unwrap the yield tokens that the shares are worth.
        uint256 amountYieldTokens      = convertSharesToYieldTokens(yieldToken, actualShares);
        uint256 amountUnderlyingTokens = _unwrap(yieldToken, amountYieldTokens, address(this), minimumAmountOut);

        // Again, perform another noop check. It is possible that the amount of underlying tokens that were received by
        // unwrapping the yield tokens was zero because the amount of yield tokens to unwrap was too small.
        _checkState(amountUnderlyingTokens > 0);

        Limiters.LinearGrowthLimiter storage limiter = _liquidationLimiters[underlyingToken];

        // Check to make sure that the underlying token liquidation limit has not been breached.
        uint256 liquidationLimit = limiter.get();
        if (amountUnderlyingTokens > liquidationLimit) {
          revert LiquidationLimitExceeded(underlyingToken, amountUnderlyingTokens, liquidationLimit);
        }

        // Buffers any harvestable yield tokens. This will properly synchronize the balance which is held by users
        // and the balance which is held by the system. This is required for `_sync` to function correctly.
        _preemptivelyHarvest(yieldToken);

        // Distribute unlocked credit to depositors.
        _distributeUnlockedCreditDeposited(msg.sender);

        uint256 credit = normalizeUnderlyingTokensToDebt(underlyingToken, amountUnderlyingTokens);

        // Update the message sender's account, proactively burn shares, decrease the amount of debt incurred, and then
        // decrease the value of the token that the system is expected to hold.
        _poke(msg.sender, yieldToken);
        _burnShares(msg.sender, yieldToken, actualShares);
        _updateDebt(msg.sender, -SafeCast.toInt256(credit));
        _sync(yieldToken, amountYieldTokens, _usub);

        // Decrease the amount of the underlying token which is globally available to be liquidated.
        limiter.decrease(amountUnderlyingTokens);

        // Transfer the liquidated tokens to the transmuter.
        TokenUtils.safeTransfer(underlyingToken, transmuter, amountUnderlyingTokens);

        // Inform the transmuter that it has received tokens.
        IERC20TokenReceiver(transmuter).onERC20Received(underlyingToken, amountUnderlyingTokens);

        // In the case that slippage allowed by minimumAmountOut would create an undercollateralized position
        _validate(msg.sender);

        emit Liquidate(msg.sender, yieldToken, underlyingToken, actualShares, credit);

        return actualShares;
    }

    /// @inheritdoc IAlchemistV2Actions
    function donate(address yieldToken, uint256 amount) external override lock {
        _onlyWhitelisted();
        _checkArgument(amount > 0);

        // Distribute any unlocked credit so that the accrued weight is up to date.
        _distributeUnlockedCredit(yieldToken);

        // Update the message sender's account. This will assure that any credit that was earned is not overridden.
        _poke(msg.sender);

        uint256 shares = _yieldTokens[yieldToken].totalShares - _accounts[msg.sender].balances[yieldToken];

        _yieldTokens[yieldToken].accruedWeight += amount * FIXED_POINT_SCALAR / shares;
        _accounts[msg.sender].lastAccruedWeights[yieldToken] = _yieldTokens[yieldToken].accruedWeight;

        TokenUtils.safeBurnFrom(debtToken, msg.sender, amount);

        // Increase the global amount of mintable debt tokens.
        // Do this after burning instead of before because mint limit increase is an action beneficial to the user.
        _mintingLimiter.increase(amount);

        emit Donate(msg.sender, yieldToken, amount);
    }

    /// @inheritdoc IAlchemistV2Actions
    function harvest(address yieldToken, uint256 minimumAmountOut) external override lock {
        _onlyKeeper();
        _checkSupportedYieldToken(yieldToken);

        YieldTokenParams storage yieldTokenParams = _yieldTokens[yieldToken];

        // Buffer any harvestable yield tokens. This will properly synchronize the balance which is held by users
        // and the balance which is held by the system to be harvested during this call.
        _preemptivelyHarvest(yieldToken);

        // Load and proactively clear the amount of harvestable tokens so that future calls do not rely on stale data.
        // Because we cannot call an external unwrap until the amount of harvestable tokens has been calculated,
        // clearing this data immediately prevents any potential reentrancy attacks which would use stale harvest
        // buffer values.
        uint256 harvestableAmount = yieldTokenParams.harvestableBalance;
        yieldTokenParams.harvestableBalance = 0;

        // Check that the harvest will not be a no-op.
        _checkState(harvestableAmount != 0);

        address underlyingToken = yieldTokenParams.underlyingToken;
        uint256 amountUnderlyingTokens = _unwrap(yieldToken, harvestableAmount, address(this), minimumAmountOut);

        // Calculate how much of the unwrapped underlying tokens will be allocated for fees and distributed to users.
        uint256 feeAmount = amountUnderlyingTokens * protocolFee / BPS;
        uint256 distributeAmount = amountUnderlyingTokens - feeAmount;

        uint256 credit = normalizeUnderlyingTokensToDebt(underlyingToken, distributeAmount);

        // Distribute credit to all of the users who hold shares of the yield token.
        _distributeCredit(yieldToken, credit);

        // Transfer the tokens to the fee receiver and transmuter.
        TokenUtils.safeTransfer(underlyingToken, protocolFeeReceiver, feeAmount);
        TokenUtils.safeTransfer(underlyingToken, transmuter, distributeAmount);

        // Inform the transmuter that it has received tokens.
        IERC20TokenReceiver(transmuter).onERC20Received(underlyingToken, distributeAmount);

        emit Harvest(yieldToken, minimumAmountOut, amountUnderlyingTokens, credit);
    }

    /// @dev Checks that the `msg.sender` is the administrator.
    ///
    /// @dev `msg.sender` must be the administrator or this call will revert with an {Unauthorized} error.
    function _onlyAdmin() internal view {
        if (msg.sender != admin) {
            revert Unauthorized();
        }
    }

    /// @dev Checks that the `msg.sender` is the administrator or a sentinel.
    ///
    /// @dev `msg.sender` must be either the administrator or a sentinel or this call will revert with an
    ///      {Unauthorized} error.
    function _onlySentinelOrAdmin() internal view {
        // Check if the message sender is the administrator.
        if (msg.sender == admin) {
            return;
        }

        // Check if the message sender is a sentinel. After this check we can revert since we know that it is neither
        // the administrator or a sentinel.
        if (!sentinels[msg.sender]) {
            revert Unauthorized();
        }
    }

    /// @dev Checks that the `msg.sender` is a keeper.
    ///
    /// @dev `msg.sender` must be a keeper or this call will revert with an {Unauthorized} error.
    function _onlyKeeper() internal view {
        if (!keepers[msg.sender]) {
            revert Unauthorized();
        }
    }

    /// @dev Checks that the `msg.sender` is the V1 transfer adapter.
    ///
    /// @dev `msg.sender` must be the administrator or this call will revert with an {Unauthorized} error.
    function _onlyTransferAdapter() internal view {
        if (msg.sender != transferAdapter) {
            revert Unauthorized();
        }
    }

    /// @dev Preemptively harvests all of the yield tokens that have been deposited into an account.
    ///
    /// @param owner The address which owns the account.
    function _preemptivelyHarvestDeposited(address owner) internal {
        Sets.AddressSet storage depositedTokens = _accounts[owner].depositedTokens;
        for (uint256 i = 0; i < depositedTokens.values.length; ++i) {
            _preemptivelyHarvest(depositedTokens.values[i]);
        }
    }

    /// @dev Preemptively harvests `yieldToken`.
    ///
    /// @dev This will earmark yield tokens to be harvested at a future time when the current value of the token is
    ///      greater than the expected value. The purpose of this function is to synchronize the balance of the yield
    ///      token which is held by users versus tokens which will be seized by the protocol.
    ///
    /// @param yieldToken The address of the yield token to preemptively harvest.
    function _preemptivelyHarvest(address yieldToken) internal {
        uint256 activeBalance = _yieldTokens[yieldToken].activeBalance;
        if (activeBalance == 0) {
            return;
        }

        uint256 currentValue = convertYieldTokensToUnderlying(yieldToken, activeBalance);
        uint256 expectedValue = _yieldTokens[yieldToken].expectedValue;
        if (currentValue <= expectedValue) {
            return;
        }

        uint256 harvestable = convertUnderlyingTokensToYield(yieldToken, currentValue - expectedValue);
        if (harvestable == 0) {
            return;
        }
        _yieldTokens[yieldToken].activeBalance -= harvestable;
        _yieldTokens[yieldToken].harvestableBalance += harvestable;
    }

    /// @dev Checks if a yield token is enabled.
    ///
    /// @param yieldToken The address of the yield token.
    function _checkYieldTokenEnabled(address yieldToken) internal view {
        if (!_yieldTokens[yieldToken].enabled) {
          revert TokenDisabled(yieldToken);
        }
    }

    /// @dev Checks if an underlying token is enabled.
    ///
    /// @param underlyingToken The address of the underlying token.
    function _checkUnderlyingTokenEnabled(address underlyingToken) internal view {
        if (!_underlyingTokens[underlyingToken].enabled) {
          revert TokenDisabled(underlyingToken);
        }
    }

    /// @dev Checks if an address is a supported yield token.
    ///
    /// If the address is not a supported yield token, this function will revert using a {UnsupportedToken} error.
    ///
    /// @param yieldToken The address to check.
    function _checkSupportedYieldToken(address yieldToken) internal view {
        if (!_supportedYieldTokens.contains(yieldToken)) {
            revert UnsupportedToken(yieldToken);
        }
    }

    /// @dev Checks if an address is a supported underlying token.
    ///
    /// If the address is not a supported yield token, this function will revert using a {UnsupportedToken} error.
    ///
    /// @param underlyingToken The address to check.
    function _checkSupportedUnderlyingToken(address underlyingToken) internal view {
        if (!_supportedUnderlyingTokens.contains(underlyingToken)) {
            revert UnsupportedToken(underlyingToken);
        }
    }

    /// @dev Checks if `amount` of debt tokens can be minted.
    ///
    /// @dev `amount` must be less than the current minting limit or this call will revert with a
    ///      {MintingLimitExceeded} error.
    ///
    /// @param amount The amount to check.
    function _checkMintingLimit(uint256 amount) internal view {
        uint256 limit = _mintingLimiter.get();
        if (amount > limit) {
            revert MintingLimitExceeded(amount, limit);
        }
    }

    /// @dev Checks if the current loss of `yieldToken` has exceeded its maximum acceptable loss.
    ///
    /// @dev The loss that `yieldToken` has incurred must be less than its maximum accepted value or this call will
    ///      revert with a {LossExceeded} error.
    ///
    /// @param yieldToken The address of the yield token.
    function _checkLoss(address yieldToken) internal view {
        uint256 loss = _loss(yieldToken);
        uint256 maximumLoss = _yieldTokens[yieldToken].maximumLoss;
        if (loss > maximumLoss) {
            revert LossExceeded(yieldToken, loss, maximumLoss);
        }
    }

    /// @dev Deposits `amount` yield tokens into the account of `recipient`.
    ///
    /// @dev Emits a {Deposit} event.
    ///
    /// @param yieldToken The address of the yield token to deposit.
    /// @param amount     The amount of yield tokens to deposit.
    /// @param recipient  The recipient of the yield tokens.
    ///
    /// @return The number of shares minted to `recipient`.
    function _deposit(
        address yieldToken,
        uint256 amount,
        address recipient
    ) internal returns (uint256) {
        _checkArgument(amount > 0);

        YieldTokenParams storage yieldTokenParams = _yieldTokens[yieldToken];
        address underlyingToken = yieldTokenParams.underlyingToken;

        // Check that the yield token and it's underlying token are enabled. Disabling the yield token and or the
        // underlying token prevents the system from holding more of the disabled yield token or underlying token.
        _checkYieldTokenEnabled(yieldToken);
        _checkUnderlyingTokenEnabled(underlyingToken);

        // Check to assure that the token has not experienced a sudden unexpected loss. This prevents users from being
        // able to deposit funds and then have them siphoned if the price recovers.
        _checkLoss(yieldToken);

        // Buffers any harvestable yield tokens. This will properly synchronize the balance which is held by users
        // and the balance which is held by the system to eventually be harvested.
        _preemptivelyHarvest(yieldToken);

        // Distribute unlocked credit to depositors.
        _distributeUnlockedCreditDeposited(recipient);

        // Update the recipient's account, proactively issue shares for the deposited tokens to the recipient, and then
        // increase the value of the token that the system is expected to hold.
        _poke(recipient, yieldToken);
        uint256 shares = _issueSharesForAmount(recipient, yieldToken, amount);
        _sync(yieldToken, amount, _uadd);

        // Check that the maximum expected value has not been breached.
        uint256 maximumExpectedValue = yieldTokenParams.maximumExpectedValue;
        if (yieldTokenParams.expectedValue > maximumExpectedValue) {
          revert ExpectedValueExceeded(yieldToken, amount, maximumExpectedValue);
        }

        emit Deposit(msg.sender, yieldToken, amount, recipient);

        return shares;
    }

    /// @dev Withdraw `yieldToken` from the account owned by `owner` by burning shares and receiving yield tokens of
    ///      equivalent value.
    ///
    /// @dev Emits a {Withdraw} event.
    ///
    /// @param yieldToken The address of the yield token to withdraw.
    /// @param owner      The address of the account owner to withdraw from.
    /// @param shares     The number of shares to burn.
    /// @param recipient  The recipient of the withdrawn shares. This parameter is only used for logging.
    ///
    /// @return The amount of yield tokens that the burned shares were exchanged for.
    function _withdraw(
        address yieldToken,
        address owner,
        uint256 shares,
        address recipient
    ) internal returns (uint256) {
        // Buffers any harvestable yield tokens that the owner of the account has deposited. This will properly
        // synchronize the balance of all the tokens held by the owner so that the validation check properly
        // computes the total value of the tokens held by the owner.
        _preemptivelyHarvestDeposited(owner);

        // Distribute unlocked credit for all of the tokens that the user has deposited into the system. This updates
        // the accrued weights so that the debt is properly calculated before the account is validated.
        _distributeUnlockedCreditDeposited(owner);

        uint256 amountYieldTokens = convertSharesToYieldTokens(yieldToken, shares);

        // Update the owner's account, burn shares from the owner's account, and then decrease the value of the token
        // that the system is expected to hold.
        _poke(owner);
        _burnShares(owner, yieldToken, shares);
        _sync(yieldToken, amountYieldTokens, _usub);

        // Valid the owner's account to assure that the collateralization invariant is still held.
        _validate(owner);

        emit Withdraw(owner, yieldToken, shares, recipient);

        return amountYieldTokens;
    }

    /// @dev Mints debt tokens to `recipient` using the account owned by `owner`.
    ///
    /// @dev Emits a {Mint} event.
    ///
    /// @param owner     The owner of the account to mint from.
    /// @param amount    The amount to mint.
    /// @param recipient The recipient of the minted debt tokens.
    function _mint(address owner, uint256 amount, address recipient) internal {
        // Check that the system will allow for the specified amount to be minted.
        _checkMintingLimit(amount);

        // Preemptively harvest all tokens that the user has deposited into the system. This allows the debt to be
        // properly calculated before the account is validated.
        _preemptivelyHarvestDeposited(owner);

        // Distribute unlocked credit for all of the tokens that the user has deposited into the system. This updates
        // the accrued weights so that the debt is properly calculated before the account is validated.
        _distributeUnlockedCreditDeposited(owner);

        // Update the owner's account, increase their debt by the amount of tokens to mint, and then finally validate
        // their account to assure that the collateralization invariant is still held.
        _poke(owner);
        _updateDebt(owner, SafeCast.toInt256(amount));
        _validate(owner);

        // Decrease the global amount of mintable debt tokens.
        _mintingLimiter.decrease(amount);

        // Mint the debt tokens to the recipient.
        TokenUtils.safeMint(debtToken, recipient, amount);

        emit Mint(owner, amount, recipient);
    }

    /// @dev Synchronizes the active balance and expected value of `yieldToken`.
    ///
    /// @param yieldToken The address of the yield token.
    /// @param amount     The amount to add or subtract from the debt.
    /// @param operation  The mathematical operation to perform for the update. Either one of {_uadd} or {_usub}.
    function _sync(
        address yieldToken,
        uint256 amount,
        function(uint256, uint256) internal pure returns (uint256) operation
    ) internal {
        YieldTokenParams memory yieldTokenParams = _yieldTokens[yieldToken];

        uint256 amountUnderlyingTokens = convertYieldTokensToUnderlying(yieldToken, amount);
        uint256 updatedActiveBalance   = operation(yieldTokenParams.activeBalance, amount);
        uint256 updatedExpectedValue   = operation(yieldTokenParams.expectedValue, amountUnderlyingTokens);

        _yieldTokens[yieldToken].activeBalance = updatedActiveBalance;
        _yieldTokens[yieldToken].expectedValue = updatedExpectedValue;
    }

    /// @dev Gets the amount of loss that `yieldToken` has incurred measured in basis points. When the expected
    ///      underlying value is less than the actual value, this will return zero.
    ///
    /// @param yieldToken The address of the yield token.
    ///
    /// @return The loss in basis points.
    function _loss(address yieldToken) internal view returns (uint256) {
        YieldTokenParams memory yieldTokenParams = _yieldTokens[yieldToken];

        uint256 amountUnderlyingTokens = convertYieldTokensToUnderlying(yieldToken, yieldTokenParams.activeBalance);
        uint256 expectedUnderlyingValue = yieldTokenParams.expectedValue;

        return expectedUnderlyingValue > amountUnderlyingTokens
            ? ((expectedUnderlyingValue - amountUnderlyingTokens) * BPS) / expectedUnderlyingValue
            : 0;
    }

    /// @dev Distributes `amount` credit to all depositors of `yieldToken`.
    ///
    /// @param yieldToken The address of the yield token to distribute credit for.
    /// @param amount     The amount of credit to distribute in debt tokens.
    function _distributeCredit(address yieldToken, uint256 amount) internal {
        YieldTokenParams storage yieldTokenParams = _yieldTokens[yieldToken];

        uint256 pendingCredit     = yieldTokenParams.pendingCredit;
        uint256 distributedCredit = yieldTokenParams.distributedCredit;
        uint256 unlockedCredit    = _calculateUnlockedCredit(yieldToken);
        uint256 lockedCredit      = pendingCredit - (distributedCredit + unlockedCredit);

        // Distribute any unlocked credit before overriding it.
        if (unlockedCredit > 0) {
            yieldTokenParams.accruedWeight += unlockedCredit * FIXED_POINT_SCALAR / yieldTokenParams.totalShares;
        }

        yieldTokenParams.pendingCredit         = amount + lockedCredit;
        yieldTokenParams.distributedCredit     = 0;
        yieldTokenParams.lastDistributionBlock = block.number;
    }

    /// @dev Distributes unlocked credit for all of the yield tokens that have been deposited into the account owned
    ///      by `owner`.
    ///
    /// @param owner The address of the account owner.
    function _distributeUnlockedCreditDeposited(address owner) internal {
        Sets.AddressSet storage depositedTokens = _accounts[owner].depositedTokens;
        for (uint256 i = 0; i < depositedTokens.values.length; ++i) {
            _distributeUnlockedCredit(depositedTokens.values[i]);
        }
    }

    /// @dev Distributes unlocked credit of `yieldToken` to all depositors.
    ///
    /// @param yieldToken The address of the yield token to distribute unlocked credit for.
    function _distributeUnlockedCredit(address yieldToken) internal {
        YieldTokenParams storage yieldTokenParams = _yieldTokens[yieldToken];

        uint256 unlockedCredit = _calculateUnlockedCredit(yieldToken);
        if (unlockedCredit == 0) {
            return;
        }

        yieldTokenParams.accruedWeight     += unlockedCredit * FIXED_POINT_SCALAR / yieldTokenParams.totalShares;
        yieldTokenParams.distributedCredit += unlockedCredit;
    }

    /// @dev Wraps `amount` of an underlying token into its `yieldToken`.
    ///
    /// @param yieldToken       The address of the yield token to wrap the underlying tokens into.
    /// @param amount           The amount of the underlying token to wrap.
    /// @param minimumAmountOut The minimum amount of yield tokens that are expected to be received from the operation.
    ///
    /// @return The amount of yield tokens that resulted from the operation.
    function _wrap(
        address yieldToken,
        uint256 amount,
        uint256 minimumAmountOut
    ) internal returns (uint256) {
        YieldTokenParams storage yieldTokenParams = _yieldTokens[yieldToken];

        ITokenAdapter adapter = ITokenAdapter(yieldTokenParams.adapter);
        address underlyingToken = yieldTokenParams.underlyingToken;

        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
        uint256 wrappedShares = adapter.wrap(amount, address(this));
        if (wrappedShares < minimumAmountOut) {
            revert SlippageExceeded(wrappedShares, minimumAmountOut);
        }

        return wrappedShares;
    }

    /// @dev Unwraps `amount` of `yieldToken` into its underlying token.
    ///
    /// @param yieldToken       The address of the yield token to unwrap.
    /// @param amount           The amount of the underlying token to wrap.
    /// @param recipient        The recipient of the tokens after they are unwrapped.
    /// @param minimumAmountOut The minimum amount of underlying tokens that are expected to be received from the
    ///                         operation.
    ///
    /// @return The amount of underlying tokens that resulted from the operation.
    function _unwrap(
        address yieldToken,
        uint256 amount,
        address recipient,
        uint256 minimumAmountOut
    ) internal returns (uint256) {
        ITokenAdapter adapter = ITokenAdapter(_yieldTokens[yieldToken].adapter);
        uint256 amountUnwrapped = adapter.unwrap(amount, recipient);
        if (amountUnwrapped < minimumAmountOut) {
            revert SlippageExceeded(amountUnwrapped, minimumAmountOut);
        }
        return amountUnwrapped;
    }

    /// @dev Synchronizes the state for all of the tokens deposited in the account owned by `owner`.
    ///
    /// @param owner The address of the account owner.
    function _poke(address owner) internal {
        Sets.AddressSet storage depositedTokens = _accounts[owner].depositedTokens;
        for (uint256 i = 0; i < depositedTokens.values.length; ++i) {
            _poke(owner, depositedTokens.values[i]);
        }
    }

    /// @dev Synchronizes the state of `yieldToken` for the account owned by `owner`.
    ///
    /// @param owner      The address of the account owner.
    /// @param yieldToken The address of the yield token to synchronize the state for.
    function _poke(address owner, address yieldToken) internal {
        Account storage account = _accounts[owner];

        uint256 currentAccruedWeight = _yieldTokens[yieldToken].accruedWeight;
        uint256 lastAccruedWeight    = account.lastAccruedWeights[yieldToken];

        if (currentAccruedWeight == lastAccruedWeight) {
            return;
        }

        uint256 balance          = account.balances[yieldToken];
        uint256 unrealizedCredit = (currentAccruedWeight - lastAccruedWeight) * balance / FIXED_POINT_SCALAR;

        account.debt                           -= SafeCast.toInt256(unrealizedCredit);
        account.lastAccruedWeights[yieldToken]  = currentAccruedWeight;
    }

    /// @dev Increases the debt by `amount` for the account owned by `owner`.
    ///
    /// @param owner     The address of the account owner.
    /// @param amount    The amount to increase the debt by.
    function _updateDebt(address owner, int256 amount) internal {
        Account storage account = _accounts[owner];
        account.debt += amount;
    }

    /// @dev Set the mint allowance for `spender` to `amount` for the account owned by `owner`.
    ///
    /// @param owner   The address of the account owner.
    /// @param spender The address of the spender.
    /// @param amount  The amount of debt tokens to set the mint allowance to.
    function _approveMint(address owner, address spender, uint256 amount) internal {
        Account storage account = _accounts[owner];
        account.mintAllowances[spender] = amount;
        emit ApproveMint(owner, spender, amount);
    }

    /// @dev Decrease the mint allowance for `spender` by `amount` for the account owned by `owner`.
    ///
    /// @param owner   The address of the account owner.
    /// @param spender The address of the spender.
    /// @param amount  The amount of debt tokens to decrease the mint allowance by.
    function _decreaseMintAllowance(address owner, address spender, uint256 amount) internal {
        Account storage account = _accounts[owner];
        account.mintAllowances[spender] -= amount;
    }

    /// @dev Set the withdraw allowance of `yieldToken` for `spender` to `shares` for the account owned by `owner`.
    ///
    /// @param owner      The address of the account owner.
    /// @param spender    The address of the spender.
    /// @param yieldToken The address of the yield token to set the withdraw allowance for.
    /// @param shares     The amount of shares to set the withdraw allowance to.
    function _approveWithdraw(address owner, address spender, address yieldToken, uint256 shares) internal {
        Account storage account = _accounts[owner];
        account.withdrawAllowances[spender][yieldToken] = shares;
        emit ApproveWithdraw(owner, spender, yieldToken, shares);
    }

    /// @dev Decrease the withdraw allowance of `yieldToken` for `spender` by `amount` for the account owned by `owner`.
    ///
    /// @param owner      The address of the account owner.
    /// @param spender    The address of the spender.
    /// @param yieldToken The address of the yield token to decrease the withdraw allowance for.
    /// @param amount     The amount of shares to decrease the withdraw allowance by.
    function _decreaseWithdrawAllowance(address owner, address spender, address yieldToken, uint256 amount) internal {
        Account storage account = _accounts[owner];
        account.withdrawAllowances[spender][yieldToken] -= amount;
    }

    /// @dev Checks that the account owned by `owner` is properly collateralized.
    ///
    /// @dev If the account is undercollateralized then this will revert with an {Undercollateralized} error.
    ///
    /// @param owner The address of the account owner.
    function _validate(address owner) internal view {
        int256 debt = _accounts[owner].debt;
        if (debt <= 0) {
            return;
        }

        uint256 collateralization = totalValue(owner) * FIXED_POINT_SCALAR / uint256(debt);

        if (collateralization < minimumCollateralization) {
            revert Undercollateralized();
        }
    }

    /// @dev Gets the total value of the deposit collateral measured in debt tokens of the account owned by `owner`.
    ///
    /// @param owner The address of the account owner.
    ///
    /// @return The total value.
    function totalValue(address owner) public view returns (uint256) {
        uint256 totalValue = 0;

        Sets.AddressSet storage depositedTokens = _accounts[owner].depositedTokens;
        for (uint256 i = 0; i < depositedTokens.values.length; ++i) {
            address yieldToken             = depositedTokens.values[i];
            address underlyingToken        = _yieldTokens[yieldToken].underlyingToken;
            uint256 shares                 = _accounts[owner].balances[yieldToken];
            uint256 amountUnderlyingTokens = convertSharesToUnderlyingTokens(yieldToken, shares);

            totalValue += normalizeUnderlyingTokensToDebt(underlyingToken, amountUnderlyingTokens);
        }

        return totalValue;
    }

    /// @dev Issues shares of `yieldToken` for `amount` of its underlying token to `recipient`.
    ///
    /// IMPORTANT: `amount` must never be 0.
    ///
    /// @param recipient  The address of the recipient.
    /// @param yieldToken The address of the yield token.
    /// @param amount     The amount of the underlying token.
    ///
    /// @return The amount of shares issued to `recipient`.
    function _issueSharesForAmount(
        address recipient,
        address yieldToken,
        uint256 amount
    ) internal returns (uint256) {
        uint256 shares = convertYieldTokensToShares(yieldToken, amount);

        if (_accounts[recipient].balances[yieldToken] == 0) {
          _accounts[recipient].depositedTokens.add(yieldToken);
        }

        _accounts[recipient].balances[yieldToken] += shares;
        _yieldTokens[yieldToken].totalShares += shares;

        return shares;
    }

    /// @dev Burns `share` shares of `yieldToken` from the account owned by `owner`.
    ///
    /// @param owner      The address of the owner.
    /// @param yieldToken The address of the yield token.
    /// @param shares     The amount of shares to burn.
    function _burnShares(address owner, address yieldToken, uint256 shares) internal {
        Account storage account = _accounts[owner];

        account.balances[yieldToken] -= shares;
        _yieldTokens[yieldToken].totalShares -= shares;

        if (account.balances[yieldToken] == 0) {
            account.depositedTokens.remove(yieldToken);
        }
    }

    /// @dev Gets the amount of debt that the account owned by `owner` will have after an update occurs.
    ///
    /// @param owner The address of the account owner.
    ///
    /// @return The amount of debt that the account owned by `owner` will have after an update.
    function _calculateUnrealizedDebt(address owner) internal view returns (int256) {
        int256 debt = _accounts[owner].debt;

        Sets.AddressSet storage depositedTokens = _accounts[owner].depositedTokens;
        for (uint256 i = 0; i < depositedTokens.values.length; ++i) {
            address yieldToken = depositedTokens.values[i];

            uint256 currentAccruedWeight = _yieldTokens[yieldToken].accruedWeight;
            uint256 lastAccruedWeight    = _accounts[owner].lastAccruedWeights[yieldToken];
            uint256 unlockedCredit       = _calculateUnlockedCredit(yieldToken);

            currentAccruedWeight += unlockedCredit > 0
                ? unlockedCredit * FIXED_POINT_SCALAR / _yieldTokens[yieldToken].totalShares
                : 0;

            if (currentAccruedWeight == lastAccruedWeight) {
                continue;
            }

            uint256 balance = _accounts[owner].balances[yieldToken];
            uint256 unrealizedCredit = ((currentAccruedWeight - lastAccruedWeight) * balance) / FIXED_POINT_SCALAR;

            debt -= SafeCast.toInt256(unrealizedCredit);
        }

        return debt;
    }

    /// @dev Gets the virtual active balance of `yieldToken`.
    ///
    /// @dev The virtual active balance is the active balance minus any harvestable tokens which have yet to be realized.
    ///
    /// @param yieldToken The address of the yield token to get the virtual active balance of.
    ///
    /// @return The virtual active balance.
    function _calculateUnrealizedActiveBalance(address yieldToken) internal view returns (uint256) {
        YieldTokenParams storage yieldTokenParams = _yieldTokens[yieldToken];

        uint256 activeBalance = yieldTokenParams.activeBalance;
        if (activeBalance == 0) {
          return activeBalance;
        }

        uint256 currentValue = convertYieldTokensToUnderlying(yieldToken, activeBalance);
        uint256 expectedValue = yieldTokenParams.expectedValue;
        if (currentValue <= expectedValue) {
          return activeBalance;
        }

        uint256 harvestable = convertUnderlyingTokensToYield(yieldToken, currentValue - expectedValue);
        if (harvestable == 0) {
          return activeBalance;
        }

        return activeBalance - harvestable;
    }

    /// @dev Calculates the amount of unlocked credit for `yieldToken` that is available for distribution.
    ///
    /// @param yieldToken The address of the yield token.
    ///
    /// @return The amount of unlocked credit available.
    function _calculateUnlockedCredit(address yieldToken) internal view returns (uint256) {
        YieldTokenParams storage yieldTokenParams = _yieldTokens[yieldToken];

        uint256 pendingCredit = yieldTokenParams.pendingCredit;
        if (pendingCredit == 0) {
            return 0;
        }

        uint256 creditUnlockRate      = yieldTokenParams.creditUnlockRate;
        uint256 distributedCredit     = yieldTokenParams.distributedCredit;
        uint256 lastDistributionBlock = yieldTokenParams.lastDistributionBlock;

        uint256 percentUnlocked = (block.number - lastDistributionBlock) * creditUnlockRate;

        return percentUnlocked < FIXED_POINT_SCALAR
            ? (pendingCredit * percentUnlocked / FIXED_POINT_SCALAR) - distributedCredit
            : pendingCredit - distributedCredit;
    }

    /// @dev Gets the amount of shares that `amount` of `yieldToken` is exchangeable for.
    ///
    /// @param yieldToken The address of the yield token.
    /// @param amount     The amount of yield tokens.
    ///
    /// @return The number of shares.
    function convertYieldTokensToShares(address yieldToken, uint256 amount) public view returns (uint256) {
        if (_yieldTokens[yieldToken].totalShares == 0) {
            return amount;
        }
        return amount * _yieldTokens[yieldToken].totalShares / _calculateUnrealizedActiveBalance(yieldToken);
    }

    /// @dev Gets the amount of yield tokens that `shares` shares of `yieldToken` is exchangeable for.
    ///
    /// @param yieldToken The address of the yield token.
    /// @param shares     The amount of shares.
    ///
    /// @return The amount of yield tokens.
    function convertSharesToYieldTokens(address yieldToken, uint256 shares) public view returns (uint256) {
        uint256 totalShares = _yieldTokens[yieldToken].totalShares;
        if (totalShares == 0) {
          return shares;
        }
        return (shares * _calculateUnrealizedActiveBalance(yieldToken)) / totalShares;
    }

    /// @dev Gets the amount of underlying tokens that `shares` shares of `yieldToken` is exchangeable for.
    ///
    /// @param yieldToken The address of the yield token.
    /// @param shares     The amount of shares.
    ///
    /// @return The amount of underlying tokens.
    function convertSharesToUnderlyingTokens(address yieldToken, uint256 shares) public view returns (uint256) {
        uint256 amountYieldTokens = convertSharesToYieldTokens(yieldToken, shares);
        return convertYieldTokensToUnderlying(yieldToken, amountYieldTokens);
    }

    /// @dev Gets the amount of an underlying token that `amount` of `yieldToken` is exchangeable for.
    ///
    /// @param yieldToken The address of the yield token.
    /// @param amount     The amount of yield tokens.
    ///
    /// @return The amount of underlying tokens.
    function convertYieldTokensToUnderlying(address yieldToken, uint256 amount) public view returns (uint256) {
        YieldTokenParams storage yieldTokenParams = _yieldTokens[yieldToken];
        ITokenAdapter adapter = ITokenAdapter(yieldTokenParams.adapter);
        return amount * adapter.price() / 10**yieldTokenParams.decimals;
    }

    /// @dev Gets the amount of `yieldToken` that `amount` of its underlying token is exchangeable for.
    ///
    /// @param yieldToken The address of the yield token.
    /// @param amount     The amount of underlying tokens.
    ///
    /// @return The amount of yield tokens.
    function convertUnderlyingTokensToYield(address yieldToken, uint256 amount) public view returns (uint256) {
        YieldTokenParams storage yieldTokenParams = _yieldTokens[yieldToken];
        ITokenAdapter adapter = ITokenAdapter(yieldTokenParams.adapter);
        return amount * 10**yieldTokenParams.decimals / adapter.price();
    }

    /// @dev Gets the amount of shares of `yieldToken` that `amount` of its underlying token is exchangeable for.
    ///
    /// @param yieldToken The address of the yield token.
    /// @param amount     The amount of underlying tokens.
    ///
    /// @return The amount of shares.
    function convertUnderlyingTokensToShares(address yieldToken, uint256 amount) public view returns (uint256) {
        uint256 amountYieldTokens = convertUnderlyingTokensToYield(yieldToken, amount);
        return convertYieldTokensToShares(yieldToken, amountYieldTokens);
    }

    /// @dev Normalize `amount` of `underlyingToken` to a value which is comparable to units of the debt token.
    ///
    /// @param underlyingToken The address of the underlying token.
    /// @param amount          The amount of the debt token.
    ///
    /// @return The normalized amount.
    function normalizeUnderlyingTokensToDebt(address underlyingToken, uint256 amount) public view returns (uint256) {
        return amount * _underlyingTokens[underlyingToken].conversionFactor;
    }

    /// @dev Normalize `amount` of the debt token to a value which is comparable to units of `underlyingToken`.
    ///
    /// @dev This operation will result in truncation of some of the least significant digits of `amount`. This
    ///      truncation amount will be the least significant N digits where N is the difference in decimals between
    ///      the debt token and the underlying token.
    ///
    /// @param underlyingToken The address of the underlying token.
    /// @param amount          The amount of the debt token.
    ///
    /// @return The normalized amount.
    function normalizeDebtTokensToUnderlying(address underlyingToken, uint256 amount) public view returns (uint256) {
        return amount / _underlyingTokens[underlyingToken].conversionFactor;
    }

    /// @dev Checks the whitelist for msg.sender.
    ///
    /// Reverts if msg.sender is not in the whitelist.
    function _onlyWhitelisted() internal view {
        // Check if the message sender is an EOA. In the future, this potentially may break. It is important that functions
        // which rely on the whitelist not be explicitly vulnerable in the situation where this no longer holds true.
        if (tx.origin == msg.sender) {
          return;
        }

        // Only check the whitelist for calls from contracts.
        if (!IWhitelist(whitelist).isWhitelisted(msg.sender)) {
          revert Unauthorized();
        }
    }

    /// @dev Checks an expression and reverts with an {IllegalArgument} error if the expression is {false}.
    ///
    /// @param expression The expression to check.
    function _checkArgument(bool expression) internal pure {
        if (!expression) {
            revert IllegalArgument();
        }
    }

    /// @dev Checks an expression and reverts with an {IllegalState} error if the expression is {false}.
    ///
    /// @param expression The expression to check.
    function _checkState(bool expression) internal pure {
        if (!expression) {
            revert IllegalState();
        }
    }

    /// @dev Adds two unsigned 256 bit integers together and returns the result.
    ///
    /// @dev This operation is checked and will fail if the result overflows.
    ///
    /// @param x The first operand.
    /// @param y The second operand.
    ///
    /// @return z The result.
    function _uadd(uint256 x, uint256 y) internal pure returns (uint256 z) { z = x + y; }

    /// @dev Subtracts two unsigned 256 bit integers together and returns the result.
    ///
    /// @dev This operation is checked and will fail if the result overflows.
    ///
    /// @param x The first operand.
    /// @param y The second operand.
    ///
    /// @return z the result.
    function _usub(uint256 x, uint256 y) internal pure returns (uint256 z) { z = x - y; }
}