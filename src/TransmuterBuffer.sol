// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import "./base/Errors.sol";

import "./interfaces/IAlchemistV2.sol";
import "./interfaces/ITokenAdapter.sol";
import "./interfaces/transmuter/ITransmuterBuffer.sol";
import "./interfaces/transmuter/ITransmuterV2.sol";

import "./libraries/FixedPointMath.sol";
import "./libraries/LiquidityMath.sol";
import "./libraries/SafeCast.sol";
import "./libraries/TokenUtils.sol";
import "./interfaces/IERC20TokenReceiver.sol";

/// @title  ITransmuterBuffer
/// @author Alchemix Finance
///
/// @notice An interface contract to buffer funds between the Alchemist and the Transmuter
contract TransmuterBuffer is ITransmuterBuffer, AccessControl, Initializable {
    using FixedPointMath for FixedPointMath.Number;

    uint256 public constant BPS = 10_000;

    /// @notice The identifier of the role which maintains other roles.
    bytes32 public constant ADMIN = keccak256("ADMIN");

    /// @notice The identifier of the keeper role.
    bytes32 public constant KEEPER = keccak256("KEEPER");

    /// @inheritdoc ITransmuterBuffer
    string public constant override version = "2.2.0";

    /// @notice The alchemist address.
    address public alchemist;

    /// @notice The public transmuter address for each address.
    mapping(address => address) public transmuter;

    /// @notice The flowRate for each address.
    mapping(address => uint256) public flowRate;

    /// @notice The last update timestamp gor the flowRate for each address.
    mapping(address => uint256) public lastFlowrateUpdate;

    /// @notice The amount of flow available per ERC20.
    mapping(address => uint256) public flowAvailable;

    /// @notice The yieldTokens of each underlying supported by the Alchemist.
    mapping(address => address[]) public _yieldTokens;

    /// @notice The total amount of an underlying token that has been exchanged into the transmuter, and has not been claimed.
    mapping(address => uint256) public currentExchanged;

    /// @notice The underlying-tokens registered in the TransmuterBuffer.
    address[] public registeredUnderlyings;

    /// @notice The debt-token used by the TransmuterBuffer.
    address public debtToken;

    /// @notice A mapping of weighting schemas to be used in actions taken on the Alchemist (burn, deposit).
    mapping(address => Weighting) public weightings;

    /// @dev A mapping of addresses to denote permissioned sources of funds
    mapping(address => bool) public sources;

    /// @dev A mapping of addresses to their respective AMOs.
    mapping(address => address) public amos;

    /// @dev A mapping of underlying tokens to divert to the AMO.
    mapping(address => bool) public divertToAmo;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    /// @dev Initialize the contract
    ///
    /// @param _admin     The governing address of the buffer.
    /// @param _debtToken The debt token minted by the Alchemist and accepted by the Transmuter.
    function initialize(address _admin, address _debtToken) external initializer {
        _setupRole(ADMIN, _admin);
        _setRoleAdmin(ADMIN, ADMIN);
        _setRoleAdmin(KEEPER, ADMIN);
        debtToken = _debtToken;
    }

    /// @dev Only allows the transmuter to call the modified function
    ///
    /// Reverts if the caller is not a correct transmuter.
    ///
    /// @param underlyingToken the underlying token associated with the transmuter.
    modifier onlyTransmuter(address underlyingToken) {
        if (msg.sender != transmuter[underlyingToken]) {
            revert Unauthorized();
        }
        _;
    }

    /// @dev Only allows a governance-permissioned source to call the modified function
    ///
    /// Reverts if the caller is not a permissioned source.
    modifier onlySource() {
        if (!sources[msg.sender]) {
            revert Unauthorized();
        }
        _;
    }

    /// @dev Only calls from the admin address are authorized to pass.
    modifier onlyAdmin() {
        if (!hasRole(ADMIN, msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    /// @dev Only calls from a keeper address are authorized to pass.
    modifier onlyKeeper() {
        if (!hasRole(KEEPER, msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    /// @inheritdoc ITransmuterBuffer
    function getWeight(address weightToken, address token)
        external
        view
        override
        returns (uint256 weight)
    {
        return weightings[weightToken].weights[token];
    }

    /// @inheritdoc ITransmuterBuffer
    function getAvailableFlow(address underlyingToken)
        external
        view
        override
        returns (uint256)
    {
        // total amount of collateral that the buffer controls in the alchemist
        uint256 totalUnderlyingBuffered = getTotalUnderlyingBuffered(
            underlyingToken
        );

        if (totalUnderlyingBuffered < flowAvailable[underlyingToken]) {
            return totalUnderlyingBuffered;
        } else {
            return flowAvailable[underlyingToken];
        }
    }

    /// @inheritdoc ITransmuterBuffer
    function getTotalCredit() public view override returns (uint256) {
        (int256 debt, ) = IAlchemistV2(alchemist).accounts(address(this));
        return debt >= 0 ? 0 : SafeCast.toUint256(-debt);
    }

    /// @inheritdoc ITransmuterBuffer
    function getTotalUnderlyingBuffered(address underlyingToken)
        public
        view
        override
        returns (uint256 totalBuffered)
    {
        totalBuffered = TokenUtils.safeBalanceOf(underlyingToken, address(this));
        for (uint256 i = 0; i < _yieldTokens[underlyingToken].length; ++i) {
            totalBuffered += _getTotalBuffered(_yieldTokens[underlyingToken][i]);
        }
    }

    /// @inheritdoc ITransmuterBuffer
    function setWeights(
        address weightToken,
        address[] memory tokens,
        uint256[] memory weights
    ) external override onlyAdmin {
        if(tokens.length != weights.length) {
            revert IllegalArgument();
        }
        Weighting storage weighting = weightings[weightToken];
        delete weighting.tokens;
        weighting.totalWeight = 0;
        for (uint256 i = 0; i < tokens.length; ++i) {
            address yieldToken = tokens[i];

            // For any weightToken that is not the debtToken, we want to verify that the yield-tokens being
            // set for the weight schema accept said weightToken as collateral.
            //
            // We don't want to do this check on the debtToken because it is only used in the burnCredit() function
            // and we want to be able to burn credit to any yield-token in the Alchemist.
            if (weightToken != debtToken) {
                IAlchemistV2.YieldTokenParams memory params = IAlchemistV2(alchemist)
                    .getYieldTokenParameters(yieldToken);
                address underlyingToken = ITokenAdapter(params.adapter)
                    .underlyingToken();

                if (weightToken != underlyingToken) {
                    revert IllegalState();
                }
            }

            weighting.tokens.push(yieldToken);
            weighting.weights[yieldToken] = weights[i];
            weighting.totalWeight += weights[i];
        }
    }

    /// @inheritdoc ITransmuterBuffer
    function setSource(address source, bool flag) external override onlyAdmin {
        if (sources[source] == flag) {
            revert IllegalArgument();
        }
        sources[source] = flag;
        emit SetSource(source, flag);
    }

    /// @inheritdoc ITransmuterBuffer
    function setTransmuter(address underlyingToken, address newTransmuter) external override onlyAdmin {
        if (ITransmuterV2(newTransmuter).underlyingToken() != underlyingToken) {
            revert IllegalArgument();
        }
        transmuter[underlyingToken] = newTransmuter;
        emit SetTransmuter(underlyingToken, newTransmuter);
    }

    /// @inheritdoc ITransmuterBuffer
    function setAlchemist(address _alchemist) external override onlyAdmin {
        sources[alchemist] = false;
        sources[_alchemist] = true;

        if (alchemist != address(0)) {
            for (uint256 i = 0; i < registeredUnderlyings.length; ++i) {
                TokenUtils.safeApprove(registeredUnderlyings[i], alchemist, 0);
            }
            TokenUtils.safeApprove(debtToken, alchemist, 0);
        }

        alchemist = _alchemist;
        for (uint256 i = 0; i < registeredUnderlyings.length; ++i) {
            TokenUtils.safeApprove(registeredUnderlyings[i], alchemist, type(uint256).max);
        }
        TokenUtils.safeApprove(debtToken, alchemist, type(uint256).max);

        emit SetAlchemist(alchemist);
    }

    /// @inheritdoc ITransmuterBuffer
    function setAmo(address underlyingToken, address amo) external override onlyAdmin {
        amos[underlyingToken] = amo;
        emit SetAmo(underlyingToken, amo);
    }

    /// @inheritdoc ITransmuterBuffer
    function setDivertToAmo(address underlyingToken, bool divert) external override onlyAdmin {
        divertToAmo[underlyingToken] = divert;
        emit SetDivertToAmo(underlyingToken, divert);
    }

    /// @inheritdoc ITransmuterBuffer
    function registerAsset(
        address underlyingToken,
        address _transmuter
    ) external override onlyAdmin {
        if (!IAlchemistV2(alchemist).isSupportedUnderlyingToken(underlyingToken)) {
            revert IllegalState();
        }

        // only add to the array if not already contained in it
        for (uint256 i = 0; i < registeredUnderlyings.length; ++i) {
            if (registeredUnderlyings[i] == underlyingToken) {
                revert IllegalState();
            }
        }

        if (ITransmuterV2(_transmuter).underlyingToken() != underlyingToken) {
            revert IllegalArgument();
        }

        transmuter[underlyingToken] = _transmuter;
        registeredUnderlyings.push(underlyingToken);
        TokenUtils.safeApprove(underlyingToken, alchemist, type(uint256).max);
        emit RegisterAsset(underlyingToken, _transmuter);
    }

    /// @inheritdoc ITransmuterBuffer
    function setFlowRate(address underlyingToken, uint256 _flowRate)
        external
        override
        onlyAdmin
    {
        _exchange(underlyingToken);

        flowRate[underlyingToken] = _flowRate;
        emit SetFlowRate(underlyingToken, _flowRate);
    }

    /// @inheritdoc IERC20TokenReceiver
    function onERC20Received(address underlyingToken, uint256 amount)
        external
        override
        onlySource
    {
        if (divertToAmo[underlyingToken]) {
            _flushToAmo(underlyingToken, amount);
        } else {
            _updateFlow(underlyingToken);

            // total amount of collateral that the buffer controls in the alchemist
            uint256 localBalance = TokenUtils.safeBalanceOf(underlyingToken, address(this));

            // if there is not enough locally buffered collateral to meet the flow rate, exchange only the exchanged amount
            if (localBalance < flowAvailable[underlyingToken]) {
                currentExchanged[underlyingToken] += amount;
                ITransmuterV2(transmuter[underlyingToken]).exchange(amount);
            } else {
                uint256 exchangeable = flowAvailable[underlyingToken] - currentExchanged[underlyingToken];
                currentExchanged[underlyingToken] += exchangeable;
                ITransmuterV2(transmuter[underlyingToken]).exchange(exchangeable);
            }
        }
    }

    /// @inheritdoc ITransmuterBuffer
    function exchange(address underlyingToken) external override onlyKeeper {
        _exchange(underlyingToken);
    }

    /// @inheritdoc ITransmuterBuffer
    function flushToAmo(address underlyingToken, uint256 amount) external override onlyKeeper {
        if (divertToAmo[underlyingToken]) {
            _flushToAmo(underlyingToken, amount);
        } else {
            revert IllegalState();
        }
    }

    /// @inheritdoc ITransmuterBuffer
    function withdraw(
        address underlyingToken,
        uint256 amount,
        address recipient
    ) external override onlyTransmuter(underlyingToken) {
        if (amount > flowAvailable[underlyingToken]) {
            revert IllegalArgument();
        }

        uint256 localBalance = TokenUtils.safeBalanceOf(underlyingToken, address(this));
        if (amount > localBalance) {
            revert IllegalArgument();
        }

        flowAvailable[underlyingToken] -= amount;
        currentExchanged[underlyingToken] -= amount;

        TokenUtils.safeTransfer(underlyingToken, recipient, amount);
    }

    /// @inheritdoc ITransmuterBuffer
    function withdrawFromAlchemist(
        address yieldToken,
        uint256 shares,
        uint256 minimumAmountOut
    ) external override onlyKeeper {
        IAlchemistV2(alchemist).withdrawUnderlying(yieldToken, shares, address(this), minimumAmountOut);
    }

    /// @inheritdoc ITransmuterBuffer
    function refreshStrategies() public override {
        address[] memory supportedYieldTokens = IAlchemistV2(alchemist)
            .getSupportedYieldTokens();
        address[] memory supportedUnderlyingTokens = IAlchemistV2(alchemist)
            .getSupportedUnderlyingTokens();

        if (registeredUnderlyings.length != supportedUnderlyingTokens.length) {
            revert IllegalState();
        }

        // clear current strats
        for (uint256 j = 0; j < registeredUnderlyings.length; ++j) {
            delete _yieldTokens[registeredUnderlyings[j]];
        }

        uint256 numYTokens = supportedYieldTokens.length;
        for (uint256 i = 0; i < numYTokens; ++i) {
            address yieldToken = supportedYieldTokens[i];

            IAlchemistV2.YieldTokenParams memory params = IAlchemistV2(alchemist)
                .getYieldTokenParameters(yieldToken);
            if (params.enabled) {
                _yieldTokens[params.underlyingToken].push(yieldToken);
            }
        }
        emit RefreshStrategies();
    }

    /// @inheritdoc ITransmuterBuffer
    function burnCredit() external override onlyKeeper {
        IAlchemistV2(alchemist).poke(address(this));
        uint256 credit = getTotalCredit();
        if (credit == 0) {
            revert IllegalState();
        }
        IAlchemistV2(alchemist).mint(credit, address(this));

        _alchemistAction(credit, debtToken, _alchemistDonate);
    }

    /// @inheritdoc ITransmuterBuffer
    function depositFunds(address underlyingToken, uint256 amount)
        external
        override
        onlyKeeper
    {
        if (amount == 0) {
            revert IllegalArgument();
        }
        uint256 localBalance = TokenUtils.safeBalanceOf(underlyingToken, address(this));
        if (localBalance < amount) {
            revert IllegalArgument();
        }
        _updateFlow(underlyingToken);
        
        // Don't deposit exchanged funds into the Alchemist.
        // Doing so puts those funds at risk, and could lead to users being unable to claim
        // their transmuted funds in the event of a vault loss.
        if (localBalance - amount < currentExchanged[underlyingToken]) {
            revert IllegalState();
        }
        _alchemistAction(amount, underlyingToken, _alchemistDeposit);
    }

    /// @dev Gets the total value of the yield tokens in units of underlying tokens that this contract holds.
    ///
    /// @param yieldToken The address of the target yield token.
    /// @return totalBuffered The total amount buffered.
    function _getTotalBuffered(address yieldToken)
        internal
        view
        returns (uint256)
    {
        (uint256 balance, ) = IAlchemistV2(alchemist).positions(address(this), yieldToken);
        IAlchemistV2.YieldTokenParams memory params = IAlchemistV2(alchemist)
            .getYieldTokenParameters(yieldToken);
        uint256 tokensPerShare = IAlchemistV2(alchemist)
            .getUnderlyingTokensPerShare(yieldToken);
        return (balance * tokensPerShare) / 10**params.decimals;
    }

    /// @dev Updates the available flow for a give underlying token.
    ///
    /// @param underlyingToken the underlying token whos flow is being updated.
    /// @return marginalFlow the marginal flow.
    function _updateFlow(address underlyingToken) internal returns (uint256) {
        // additional flow to be allocated based on flow rate
        uint256 marginalFlow = (block.timestamp -
            lastFlowrateUpdate[underlyingToken]) * flowRate[underlyingToken];
        flowAvailable[underlyingToken] += marginalFlow;
        lastFlowrateUpdate[underlyingToken] = block.timestamp;
        return marginalFlow;
    }

    /// @notice Runs an action on the Alchemist according to a given weighting schema.
    ///
    /// This function gets a weighting schema defined under the `weightToken` key, and calls the target action
    /// with a weighted value of `amount` and the associated token.
    ///
    /// @param amount       The amount of funds to use in the action.
    /// @param weightToken  The key of the weighting schema to be used for the action.
    /// @param action       The action to be taken.
    function _alchemistAction(
        uint256 amount,
        address weightToken,
        function(address, uint256) action
    ) internal {
        IAlchemistV2(alchemist).poke(address(this));

        Weighting storage weighting = weightings[weightToken];
        for (uint256 j = 0; j < weighting.tokens.length; ++j) {
            address token = weighting.tokens[j];
            uint256 actionAmt = (amount * weighting.weights[token]) / weighting.totalWeight;
            action(token, actionAmt);
        }
    }

    /// @notice Donate credit weight to a target yield-token by burning debt-tokens.
    ///
    /// @param token    The target yield-token.
    /// @param amount      The amount of debt-tokens to burn.
    function _alchemistDonate(address token, uint256 amount) internal {
        IAlchemistV2(alchemist).donate(token, amount);
    }

    /// @notice Deposits funds into the Alchemist.
    ///
    /// @param token  The yield-token to deposit.
    /// @param amount The amount to deposit.
    function _alchemistDeposit(address token, uint256 amount) internal {
        IAlchemistV2(alchemist).depositUnderlying(
            token,
            amount,
            address(this),
            0
        );
    }

    /// @notice Withdraws funds from the Alchemist.
    ///
    /// @param token            The yield-token to withdraw.
    /// @param amountUnderlying The amount of underlying to withdraw.
    function _alchemistWithdraw(address token, uint256 amountUnderlying) internal {
        uint8 decimals = TokenUtils.expectDecimals(token);
        uint256 pricePerShare = IAlchemistV2(alchemist).getUnderlyingTokensPerShare(token);
        uint256 wantShares = amountUnderlying * 10**decimals / pricePerShare;
        (uint256 availableShares, uint256 lastAccruedWeight) = IAlchemistV2(alchemist).positions(address(this), token);
        if (wantShares > availableShares) {
            wantShares = availableShares;
        }
        // Allow 1% slippage
        uint256 minimumAmountOut = amountUnderlying - amountUnderlying * 100 / BPS;
        if (wantShares > 0) {
            IAlchemistV2(alchemist).withdrawUnderlying(token, wantShares, address(this), minimumAmountOut);
        }
    }

    /// @notice Pull necessary funds from the Alchemist and exchange them.
    ///
    /// @param underlyingToken The underlying-token to exchange.
    function _exchange(address underlyingToken) internal {
        _updateFlow(underlyingToken);

        uint256 totalUnderlyingBuffered = getTotalUnderlyingBuffered(underlyingToken);
        uint256 initialLocalBalance = TokenUtils.safeBalanceOf(underlyingToken, address(this));
        uint256 want = 0;
        // Here we assume the invariant underlyingToken.balanceOf(address(this)) >= currentExchanged[underlyingToken].
        if (totalUnderlyingBuffered < flowAvailable[underlyingToken]) {
            // Pull the rest of the funds from the Alchemist.
            want = totalUnderlyingBuffered - initialLocalBalance;
        } else if (initialLocalBalance < flowAvailable[underlyingToken]) {
            // totalUnderlyingBuffered > flowAvailable so we have funds available to pull.
            want = flowAvailable[underlyingToken] - initialLocalBalance;
        }

        if (want > 0) {
            _alchemistAction(want, underlyingToken, _alchemistWithdraw);
        }

        uint256 localBalance = TokenUtils.safeBalanceOf(underlyingToken, address(this));
        uint256 exchangeDelta = 0;
        if (localBalance > flowAvailable[underlyingToken]) {
            exchangeDelta = flowAvailable[underlyingToken] - currentExchanged[underlyingToken];
        } else {
            exchangeDelta = localBalance - currentExchanged[underlyingToken];
        }

        if (exchangeDelta > 0) {
            currentExchanged[underlyingToken] += exchangeDelta;
            ITransmuterV2(transmuter[underlyingToken]).exchange(exchangeDelta);
        }
    }

    /// @notice Flush funds to the amo.
    ///
    /// @param underlyingToken The underlyingToken to flush.
    /// @param amount          The amount to flush.
    function _flushToAmo(address underlyingToken, uint256 amount) internal {
        TokenUtils.safeTransfer(underlyingToken, amos[underlyingToken], amount);
        IERC20TokenReceiver(amos[underlyingToken]).onERC20Received(underlyingToken, amount);
    }
}
