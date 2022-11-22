pragma solidity ^0.8.11;

import {IllegalState} from "../../base/Errors.sol";

import "../../interfaces/IAlchemistV2.sol";
import "../../interfaces/ITokenAdapter.sol";
import "../../interfaces/external/stakedao/IAngleStableMaster.sol";
import "../../interfaces/external/stakedao/IOracle.sol";
import "../../interfaces/external/stakedao/IPerpetualManager.sol";
import "../../interfaces/external/stakedao/IPoolManager.sol";
import "../../interfaces/external/stakedao/ISanGaugeToken.sol";
import "../../interfaces/external/stakedao/ISanToken.sol";
import "../../interfaces/external/stakedao/ISanVault.sol";
import "../../interfaces/external/sushi/ISushiSwapRouter.sol";


import "../../libraries/TokenUtils.sol";

struct InitializationParams {
    address alchemist;
    address angleToken;
    address angleStableMaster;
    address parentToken;
    address poolManager;
    address stakeDaoToken;
    address sanVault;
    address swapRouter;
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
    address public immutable swapRouter;
    IStableMaster angleStableMaster;
    ISanVault sanVault;

    constructor(InitializationParams memory params) {
        alchemist = params.alchemist;
        angleToken = params.angleToken;
        parentToken = params.parentToken;
        poolManager = params.poolManager;
        stakeDaoToken = params.stakeDaoToken;
        swapRouter = params.swapRouter;
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

    /// Balance of both reward tokens currently in the contract
    function harvestableBalance() external view returns (uint256, uint256) {
        return (TokenUtils.safeBalanceOf(angleToken, address(this)), TokenUtils.safeBalanceOf(stakeDaoToken, address(this)));
    }

    function donateRewards() external returns (uint256) {
        ISanGaugeToken(token).claim_rewards(address(this));

        (uint256 angle, uint256 sdt) = (TokenUtils.safeBalanceOf(angleToken, address(this)), TokenUtils.safeBalanceOf(stakeDaoToken, address(this)));

        // Angle -> weth -> alUSD
        address[] memory path = new address[](3);
        path[0] = 0x31429d1856aD1377A8A0079410B297e1a9e214c2;
        path[1] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        path[2] = 0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9;
        TokenUtils.safeApprove(angleToken, swapRouter, angle);
        uint[] memory amountsAngle = ISushiSwapRouter(swapRouter).swapExactTokensForTokens(TokenUtils.safeBalanceOf(angleToken, address(this)), 0, path, address(this), 1669109807);

        // SDT -> weth -> alUSD
        path[0] = 0x73968b9a57c6E53d41345FD57a6E6ae27d6CDB2F;
        path[1] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        path[2] = 0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9;
        TokenUtils.safeApprove(stakeDaoToken, swapRouter, sdt);
        uint[] memory amountsSdt = ISushiSwapRouter(swapRouter).swapExactTokensForTokens(TokenUtils.safeBalanceOf(stakeDaoToken, address(this)), 0, path, address(this), 16691098070);
        uint256 total = amountsAngle[2] + amountsSdt[2];

        // Donate to users
        TokenUtils.safeApprove(IAlchemistV2(alchemist).debtToken(), alchemist, total);
        IAlchemistV2(alchemist).donate(token, total);

        return total;
    }
}