pragma solidity ^0.8.11;

import {console} from "forge-std/console.sol";
import {stdCheats} from "forge-std/stdlib.sol";

import {DSTest} from "ds-test/test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {Hevm} from "./utils/Hevm.sol";
import {AutoleverageCurveMetapool} from "../AutoleverageCurveMetapool.sol";
import {AutoleverageCurveFactoryethpool} from "../AutoleverageCurveFactoryethpool.sol";
import {AutoleverageBase} from "../AutoleverageBase.sol";

contract AutoleverageTest is DSTestPlus, stdCheats {

    AutoleverageCurveMetapool immutable metapoolHelper = new AutoleverageCurveMetapool();
    AutoleverageCurveFactoryethpool immutable factoryethpoolHelper = new AutoleverageCurveFactoryethpool();
    address constant daiWhale = 0xE78388b4CE79068e89Bf8aA7f218eF6b9AB0e9d0;
    address constant wethWhale = 0xE78388b4CE79068e89Bf8aA7f218eF6b9AB0e9d0;
    IERC20 constant dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 constant weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address constant devMultisig = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;


    function setUp() public {
        hevm.label(address(metapoolHelper), "helper");
        hevm.label(address(factoryethpoolHelper), "helper");
        hevm.label(daiWhale, "whale");
        hevm.label(address(dai), "dai");
        hevm.label(address(weth), "weth");
        hevm.label(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9, "lendingPool");
        hevm.label(0xA3dfCcbad1333DC69997Da28C961FF8B2879e653, "alethWhitelist");
        hevm.label(0x78537a6CeBa16f412E123a90472C6E0e9A8F1132, "alusdWhitelist");
        hevm.label(0xf547b87Cd37607bDdAbAFd9bF1EA4587a0F4aCFb, "alchemistAlusdImpl");
        hevm.label(devMultisig, "devMultisig");
    }


    function testFlashLoanMetapool() public {
        address metapool = 0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c; // alUSD-3CRV metapool
        int128 metapoolI = 0; // alUSD index
        int128 metapoolJ = 1; // DAI index
        address alchemist = 0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd; // Alchemist alUSD
        address yieldToken = 0xdA816459F1AB5631232FE5e97a05BBBb94970c95; // yvDAI
        uint256 collateralInitial = 1_000_000 ether; // will error out if we hit mint caps
        uint256 collateralTotal = 1_900_000 ether;
        uint256 slippageMultiplier = 10050; // out of 10000
        uint256 targetDebt = (collateralTotal - collateralInitial) * slippageMultiplier / 10000;
        address recipient = daiWhale;

        hevm.label(alchemist, "alchemist");
        hevm.label(yieldToken, "yieldToken");

        hevm.startPrank(devMultisig, devMultisig);

        // Boost deposit and mint caps so we don't hit
        IAlchemistV2.YieldTokenParams memory prevYieldTokenParams = IAlchemistV2(alchemist).getYieldTokenParameters(yieldToken);
        uint256 maximumExpectedValue = prevYieldTokenParams.maximumExpectedValue;
        IAlchemistV2(alchemist).setMaximumExpectedValue(yieldToken, maximumExpectedValue + collateralTotal);

        // Add metapoolHelper contract to whitelist
        address whitelist = IAlchemistV2(alchemist).whitelist();
        IWhitelist(whitelist).add(address(metapoolHelper));

        // Impersonate the EOA whale
        hevm.stopPrank();
        hevm.startPrank(daiWhale, daiWhale);
        dai.approve(address(metapoolHelper), collateralInitial);
        IAlchemistV2(alchemist).approveMint(address(metapoolHelper), type(uint256).max);
        
        metapoolHelper.autoleverage(
            metapool,
            metapoolI,
            metapoolJ,
            alchemist,
            yieldToken,
            collateralInitial,
            collateralTotal,
            targetDebt
        );

        // Calculate collateral and ensure gte target
        (uint256 shares, ) = IAlchemistV2(alchemist).positions(recipient, yieldToken);

        IAlchemistV2.YieldTokenParams memory yieldTokenParams = IAlchemistV2(alchemist).getYieldTokenParameters(yieldToken);
        uint256 collateralValue = yieldTokenParams.expectedValue * shares / yieldTokenParams.totalShares;
        assertGe(collateralValue, collateralTotal, "Collateral doesn't meet or exceed target");

        // Calculate debt and ensure it matches the target
        (int256 iDebt, ) = IAlchemistV2(alchemist).accounts(recipient);
        require(iDebt > 0, "Debt should be positive"); // Can't do ds-test assertGt here because int128 instead of uint256
        uint256 debt = uint256(iDebt);
        assertEq(debt, targetDebt, "Debt doesn't match target");
    }

    function testFlashLoanFactoryethpoolFromWeth() public {
        address factorypool = 0xC4C319E2D4d66CcA4464C0c2B32c9Bd23ebe784e; // alETH-ETH factoryethpool
        int128 factorypoolI = 1; // alETH index
        int128 factorypoolJ = 0; // ETH index
        address alchemist = 0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c; // Alchemist alETH
        address yieldToken = 0xa258C4606Ca8206D8aA700cE2143D7db854D168c; // yvWETH
        uint256 collateralInitial = 100 ether;
        uint256 collateralTotal = 150 ether;
        uint256 slippageMultiplier = 10100; // out of 10000
        uint256 targetDebt = (collateralTotal - collateralInitial) * slippageMultiplier / 10000;
        address recipient = daiWhale;

        hevm.startPrank(devMultisig, devMultisig);

        // Boost deposit and mint caps so we don't hit
        IAlchemistV2.YieldTokenParams memory prevYieldTokenParams = IAlchemistV2(alchemist).getYieldTokenParameters(yieldToken);
        uint256 maximumExpectedValue = prevYieldTokenParams.maximumExpectedValue;
        IAlchemistV2(alchemist).setMaximumExpectedValue(yieldToken, maximumExpectedValue + collateralTotal);

        // Add factoryethpoolHelper contract to whitelist
        address whitelist = IAlchemistV2(alchemist).whitelist();
        IWhitelist(whitelist).add(address(factoryethpoolHelper));


        // Impersonate the EOA whale
        hevm.stopPrank();
        hevm.startPrank(daiWhale, daiWhale);
        weth.approve(address(factoryethpoolHelper), collateralInitial);
        IAlchemistV2(alchemist).approveMint(address(factoryethpoolHelper), type(uint256).max);
        
        factoryethpoolHelper.autoleverage(
            factorypool,
            factorypoolI,
            factorypoolJ,
            alchemist,
            yieldToken,
            collateralInitial,
            collateralTotal,
            targetDebt
        );

        // Calculate collateral and ensure gte target
        (uint256 shares, ) = IAlchemistV2(alchemist).positions(recipient, yieldToken);

        IAlchemistV2.YieldTokenParams memory yieldTokenParams = IAlchemistV2(alchemist).getYieldTokenParameters(yieldToken);
        uint256 collateralValue = yieldTokenParams.expectedValue * shares / yieldTokenParams.totalShares;
        assertGe(collateralValue, collateralTotal, "Collateral doesn't meet or exceed target");

        // Calculate debt and ensure it matches the target
        (int256 iDebt, ) = IAlchemistV2(alchemist).accounts(recipient);
        require(iDebt > 0, "Debt should be positive");
        uint256 debt = uint256(iDebt);
        assertEq(debt, targetDebt, "Debt doesn't match target");
    }

    function testFlashLoanFactoryethpoolFromEth() public {
        address factorypool = 0xC4C319E2D4d66CcA4464C0c2B32c9Bd23ebe784e; // alETH-ETH factoryethpool
        int128 factorypoolI = 1; // alETH index
        int128 factorypoolJ = 0; // ETH index
        address alchemist = 0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c; // Alchemist alETH
        address yieldToken = 0xa258C4606Ca8206D8aA700cE2143D7db854D168c; // yvWETH
        uint256 collateralInitial = 100 ether;
        uint256 collateralTotal = 150 ether;
        uint256 slippageMultiplier = 10100; // out of 10000
        uint256 targetDebt = (collateralTotal - collateralInitial) * slippageMultiplier / 10000;
        address recipient = daiWhale;

        hevm.startPrank(devMultisig, devMultisig);

        // Boost deposit and mint caps so we don't hit
        IAlchemistV2.YieldTokenParams memory prevYieldTokenParams = IAlchemistV2(alchemist).getYieldTokenParameters(yieldToken);
        uint256 maximumExpectedValue = prevYieldTokenParams.maximumExpectedValue;
        IAlchemistV2(alchemist).setMaximumExpectedValue(yieldToken, maximumExpectedValue + collateralTotal);

        // Add factoryethpoolHelper contract to whitelist
        address whitelist = IAlchemistV2(alchemist).whitelist();
        IWhitelist(whitelist).add(address(factoryethpoolHelper));

        // Impersonate the EOA whale
        hevm.stopPrank();
        hevm.startPrank(daiWhale, daiWhale);
        // No weth approval here
        IAlchemistV2(alchemist).approveMint(address(factoryethpoolHelper), type(uint256).max);
        
        factoryethpoolHelper.autoleverage{value: collateralInitial}(
            factorypool,
            factorypoolI,
            factorypoolJ,
            alchemist,
            yieldToken,
            collateralInitial,
            collateralTotal,
            targetDebt
        );

        // Calculate collateral and ensure gte target
        (uint256 shares, ) = IAlchemistV2(alchemist).positions(recipient, yieldToken);

        IAlchemistV2.YieldTokenParams memory yieldTokenParams = IAlchemistV2(alchemist).getYieldTokenParameters(yieldToken);
        uint256 collateralValue = yieldTokenParams.expectedValue * shares / yieldTokenParams.totalShares;
        assertGe(collateralValue, collateralTotal, "Collateral doesn't meet or exceed target");

        // Calculate debt and ensure it matches the target
        (int256 iDebt, ) = IAlchemistV2(alchemist).accounts(recipient);
        require(iDebt > 0, "Debt should be positive");
        uint256 debt = uint256(iDebt);
        assertEq(debt, targetDebt, "Debt doesn't match target");
    }

}