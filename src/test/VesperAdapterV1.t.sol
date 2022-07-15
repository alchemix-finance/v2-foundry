// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {stdCheats} from "../../lib/forge-std/src/stdlib.sol";
import {
    VesperAdapterV1,
    InitializationParams as AdapterInitializationParams
} from "../adapters/vesper/VesperAdapterV1.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";
import {IVesperPool} from "../interfaces/external/vesper/IVesperPool.sol";
import {SafeERC20} from "../libraries/SafeERC20.sol";
import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";
import {TokenUtils} from "../libraries/TokenUtils.sol";

contract VesperAdapterV1Test is DSTestPlus, stdCheats {
    uint256 constant BPS = 10000;
    IVesperPool constant vWethPool = IVesperPool(0xd1C117319B3595fbc39b471AB1fd485629eb05F2); // weth vesper pool
    IVesperPool constant vDaiPool = IVesperPool(0x0538C8bAc84E95A9dF8aC10Aad17DbE81b9E36ee); // dai vesper pool
    // IVesperPool constant vUsdcPool = IVesperPool(0x0C49066C0808Ee8c673553B7cbd99BCC9ABf113d); // usdc vesper pool
    IVesperPool constant vUsdtPool = IVesperPool(0xBA680a906d8f624a5F11fba54D3C672f09F26e47); // usdt vesper pool
    IWETH9 constant weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address alchemistAlUSD = 0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd;
    address alchemistAlETH = 0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c;
    address alchemistAdmin = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address alchemistAlUSDWhitelist = 0x78537a6CeBa16f412E123a90472C6E0e9A8F1132;
    address alchemistAlETHWhitelist = 0xA3dfCcbad1333DC69997Da28C961FF8B2879e653;

    VesperAdapterV1 adapter;

    function setUp() external {
        adapter = new VesperAdapterV1(AdapterInitializationParams({
            alchemist:       address(this),
            token:           address(vWethPool),
            underlyingToken: address(weth)
        }));

        hevm.startPrank(alchemistAdmin);
        IWhitelist(alchemistAlUSDWhitelist).add(address(this));
        IWhitelist(alchemistAlETHWhitelist).add(address(this));
        hevm.stopPrank();
    }

       function testRoundTrip() external {
        tip(address(weth), address(this), 1e18);

        SafeERC20.safeApprove(address(weth), address(adapter), 1e18);
        uint256 wrapped = adapter.wrap(1e18, address(this));

        uint256 underlyingValue = wrapped * adapter.price() / 10**SafeERC20.expectDecimals(address(vWethPool));
        assertGt(underlyingValue, 1e18 * 9900 / BPS);
        
        SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
        uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));
        
        assertEq(weth.balanceOf(address(0xbeef)), unwrapped);
        assertEq(vWethPool.balanceOf(address(this)), 0);
        assertEq(vWethPool.balanceOf(address(adapter)), 0);
    }

    // function testRoundTrip(uint256 amount) external {
    //     hevm.assume(
    //         amount >= 10**SafeERC20.expectDecimals(address(weth)) && 
    //         amount < type(uint96).max
    //     );
        
    //     tip(address(weth), address(this), amount);

    //     SafeERC20.safeApprove(address(weth), address(adapter), amount);
    //     uint256 wrapped = adapter.wrap(amount, address(this));

    //     uint256 underlyingValue = wrapped * adapter.price() / 10**SafeERC20.expectDecimals(address(vWethPool));
    //     assertGt(underlyingValue, amount * 9900 / BPS);
        
    //     SafeERC20.safeApprove(adapter.token(), address(adapter), wrapped);
    //     uint256 unwrapped = adapter.unwrap(wrapped, address(0xbeef));
        
    //     assertEq(weth.balanceOf(address(0xbeef)), unwrapped);
    //     assertEq(vWethPool.balanceOf(address(this)), 0);
    //     assertEq(vWethPool.balanceOf(address(adapter)), 0);
    // }

    function testTokenDai() external {
        runTokenTest(alchemistAlUSD, address(vDaiPool), 0x6B175474E89094C44Da98b954EedeAC495271d0F, 1000 ether);
    }

    // function testTokenUsdc() external {
    //     runTokenTest(alchemistAlUSD, address(vUsdcPool), 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 1000000000);
    // }

    function testTokenUsdt() external {
        runTokenTest(alchemistAlUSD, address(vUsdtPool), 0xdAC17F958D2ee523a2206206994597C13D831ec7, 1000000000);
    }

    function testTokenWeth() external {
        runTokenTest(alchemistAlETH, address(vWethPool), 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 1000 ether);
    }

    function runTokenTest(address alchemist, address yieldToken, address underlyingToken, uint256 amount) internal {
        VesperAdapterV1 yieldTokenAdapter = new VesperAdapterV1(AdapterInitializationParams({
            alchemist:       alchemist,
            token:           yieldToken,
            underlyingToken: underlyingToken
        }));
        IAlchemistV2.YieldTokenConfig memory ytc = IAlchemistV2AdminActions.YieldTokenConfig({
            adapter: address(yieldTokenAdapter),
            maximumLoss: 1,
            maximumExpectedValue: 1000000 ether,
            creditUnlockBlocks: 7200
        });
        hevm.startPrank(alchemistAdmin);
        IAlchemistV2(alchemist).addYieldToken(yieldToken, ytc);
        IAlchemistV2(alchemist).setYieldTokenEnabled(yieldToken, true);
        hevm.stopPrank();

        tip(underlyingToken, address(this), amount);
        uint256 startPrice = IAlchemistV2(alchemist).getUnderlyingTokensPerShare(yieldToken);
        TokenUtils.safeApprove(underlyingToken, alchemist, amount);
        IAlchemistV2(alchemist).depositUnderlying(yieldToken, amount, address(this), 0);
        (uint256 startShares, ) = IAlchemistV2(alchemist).positions(address(this), yieldToken);
        uint256 expectedValue = startShares * startPrice / 1e18;
        assertApproxEq(amount, expectedValue, 1000);

        uint256 startBal = IERC20(underlyingToken).balanceOf(address(this));
        assertEq(startBal, 0);

        IAlchemistV2(alchemist).withdrawUnderlying(yieldToken, startShares, address(this), 0);
        (uint256 endShares, ) = IAlchemistV2(alchemist).positions(address(this), yieldToken);
        assertEq(endShares, 0);

        uint256 endBal = IERC20(underlyingToken).balanceOf(address(this));
        assertApproxEq(endBal, amount, 1);
    }
}