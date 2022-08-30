pragma solidity ^0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TokenUtils} from "../libraries/TokenUtils.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IStaticAToken} from "../interfaces/external/aave/IStaticAToken.sol";
import {IVelodromeSwapRouter} from "../interfaces/external/velodrome/IVelodromeSwapRouter.sol";

import "../base/Errors.sol";
import "../interfaces/ISidecar.sol";
import "../libraries/Sets.sol";
import "../libraries/TokenUtils.sol";

import {console} from "../../lib/forge-std/src/console.sol";


struct InitializationParams {
    address alchemist;
    address debtToken;
    address rewardsController;
    address rewardToken;
    address swapRouter;
}

/// @title  Sidecar
/// @author Alchemix Finance
contract Sidecar is ISidecar {
    string public override version = "1.0.0";
    address public alchemist;
    address public debtToken;
    address public override rewardToken;
    address public override swapRouter;
    uint256 FIXED_POINT_SCALAR = 1e18;

    mapping(address => uint256) public yieldTokens;

    constructor(InitializationParams memory params) {
        alchemist       = params.alchemist;
        debtToken       = params.debtToken;
        rewardToken     = params.rewardToken;
        swapRouter      = params.swapRouter;
    }

    function claimAndDistributeRewards(address[] calldata tokens) external returns (uint256) {
        uint256 totalClaimed;

        for (uint i = 0; i < tokens.length; i++) {
            IStaticAToken(tokens[i]).claimRewards();
            uint256 claimed = IERC20(rewardToken).balanceOf(address(this));

            if (claimed == 0) continue;

            yieldTokens[tokens[i]] += claimed;
            totalClaimed += claimed;

            TokenUtils.safeApprove(rewardToken, swapRouter, claimed);

            IVelodromeSwapRouter.route[] memory routes = new IVelodromeSwapRouter.route[](2);
            routes[0] = IVelodromeSwapRouter.route(0x4200000000000000000000000000000000000042, 0x7F5c764cBc14f9669B88837ca1490cCa17c31607, false);
            routes[1] = IVelodromeSwapRouter.route(0x7F5c764cBc14f9669B88837ca1490cCa17c31607, 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A, true);

            IVelodromeSwapRouter(swapRouter).swapExactTokensForTokens(claimed, 0, routes, address(this), block.timestamp + 10000);
            TokenUtils.safeApprove(debtToken, alchemist, IERC20(debtToken).balanceOf(address(this)));
            console.logUint(IERC20(debtToken).allowance(address(this), address(alchemist)));
            IAlchemistV2(alchemist).donate(tokens[i], IERC20(debtToken).balanceOf(address(this)));
        }
        return totalClaimed;
    }
}