pragma solidity ^0.8.11;

import {IllegalState} from "../../base/Errors.sol";

import "../../interfaces/IAlchemistV2.sol";
import "../../interfaces/ITokenAdapter.sol";
import "../../interfaces/external/stakedao/IAngleStableMaster.sol";
import "../../interfaces/external/stakedao/IOracle.sol";
import "../../interfaces/external/stakedao/IPerpetualManager.sol";
import "../../interfaces/external/stakedao/IPoolManager.sol";
import "../../interfaces/external/stakedao/ISanToken.sol";
import "../../interfaces/external/stakedao/ISanVault.sol";

import "../../libraries/TokenUtils.sol";

struct InitializationParams {
    address alchemist;
    address angleToken;
    address angleStableMaster;
    address parentToken;
    address poolManager;
    address stakeDaoToken;
    address sanVault;
    address token;
    address underlyingToken;
}

/// @title  Stakedao San token adapter
/// @author Alchemix Finance
contract SanTokenAdapter is ITokenAdapter {
    uint256 private constant MAXIMUM_SLIPPAGE = 10000;
    uint256 private constant stableManagerBaseParams = 1000000000;
    uint256 private constant stableManagerBaseTokens = 1000000000000000000;
    string public constant override version = "2.1.0";

    address public immutable override token;
    address public immutable override underlyingToken;
    address public immutable alchemist;
    address public immutable angleToken;
    address public immutable poolManager;
    address public immutable parentToken;
    address public immutable stakeDaoToken;
    IStableMaster angleStableMaster;
    ISanVault sanVault;

    constructor(InitializationParams memory params) {
        alchemist = params.alchemist;
        angleToken = params.angleToken;
        parentToken = params.parentToken;
        poolManager = params.poolManager;
        stakeDaoToken = params.stakeDaoToken;
        token = params.token;
        underlyingToken = params.underlyingToken;


        angleStableMaster = IStableMaster(params.angleStableMaster);
        sanVault = ISanVault(params.sanVault);
    }

    /// @inheritdoc ITokenAdapter
    function price() external view override returns (uint256) {
        (
            IERC20 token,
            ISanToken sanToken,
            IPerpetualManager perpetualManager,
            IOracle oracle,
            uint256 stocksUsers,
            uint256 sanRate,
            uint256 collatBase,
            SLPData memory slpData,
            MintBurnData memory feeData
        ) = angleStableMaster.collateralMap(IPoolManager(poolManager));

        uint256 exchange = (10**TokenUtils.expectDecimals(underlyingToken) * (angleStableMaster.BASE_PARAMS() - slpData.slippage) * sanRate) / (angleStableMaster.BASE_PARAMS() * angleStableMaster.BASE_TOKENS());

        return exchange;
    }

    /// @inheritdoc ITokenAdapter
    function wrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);

        TokenUtils.safeApprove(underlyingToken, address(angleStableMaster), amount);
        angleStableMaster.deposit(amount, address(this), poolManager);

        uint256 parentBalance = TokenUtils.safeBalanceOf(parentToken, address(this));
        TokenUtils.safeApprove(parentToken, address(sanVault), parentBalance);
        sanVault.deposit(recipient, parentBalance, false);

        return TokenUtils.safeBalanceOf(token, recipient);
    }

    /// @inheritdoc ITokenAdapter
    function unwrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(token, msg.sender, address(this), amount);

        TokenUtils.safeApprove(token, address(sanVault), amount);
        sanVault.withdraw(amount);

        uint256 parentBalance = TokenUtils.safeBalanceOf(parentToken, address(this));
        TokenUtils.safeApprove(parentToken, address(angleStableMaster), parentBalance);
        angleStableMaster.withdraw(TokenUtils.safeBalanceOf(parentToken, address(this)), address(this), recipient, poolManager);

        return TokenUtils.safeBalanceOf(underlyingToken, recipient);
    }

    function harvestableBalance() external view returns (uint256, uint256) {
        return (TokenUtils.safeBalanceOf(angleToken, address(this)), TokenUtils.safeBalanceOf(stakeDaoToken, address(this)));
    }

    function donateRewards() external returns (uint256) {
        
    }
}