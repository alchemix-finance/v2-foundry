pragma solidity 0.8.13;

import {console} from "forge-std/console.sol";
import {DSTest} from "ds-test/test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {Hevm} from "./utils/Hevm.sol";
import {AutoleverageCurveMetapool} from "../AutoleverageCurveMetapool.sol";

contract AutoleverageTest is DSTestPlus {

    AutoleverageCurveMetapool helper = new AutoleverageCurveMetapool();
    address daiWhale = 0xE78388b4CE79068e89Bf8aA7f218eF6b9AB0e9d0;
    IERC20 dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address wethWhale = 0xE78388b4CE79068e89Bf8aA7f218eF6b9AB0e9d0;
    IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address whitelistOwner = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;


    function setUp() public {
    }

    function testFlashLoan() public {
        address metapool = 0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c; // alUSD-3CRV metapool
        int128 metapoolI = 0; // alUSD index
        int128 metapoolJ = 1; // DAI index
        address alchemist = 0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd; // Alchemist alUSD
        address yieldToken = 0xdA816459F1AB5631232FE5e97a05BBBb94970c95; // yvDAI
        uint collateralInitial = 1_000_000 ether;
        uint collateralTotal = 1_900_000 ether;
        uint slippageMultiplier = 10050; // out of 10000
        uint targetDebt = (collateralTotal - collateralInitial) * slippageMultiplier / 10000;
        address recipient = daiWhale;

        console.log("targetDebt:");
        console.log(targetDebt / 1 ether);

        // Add helper contract to whitelist
        address whitelist = IAlchemistV2(alchemist).whitelist();
        hevm.startPrank(whitelistOwner, whitelistOwner);
        IWhitelist(whitelist).add(address(helper));

        // Impersonate the EOA whale
        hevm.startPrank(daiWhale, daiWhale);
        dai.approve(address(helper), collateralInitial);
        console.log("approveMint()");
        IAlchemistV2(alchemist).approveMint(address(helper), type(uint).max);
        
        console.log("autoleverage()");
        helper.autoleverage(
            metapool,
            metapoolI,
            metapoolJ,
            alchemist,
            yieldToken,
            collateralInitial,
            collateralTotal,
            targetDebt,
            recipient
        );

        (uint shares, uint lastAccruedWeight) = IAlchemistV2(alchemist).positions(recipient, yieldToken);
        console.log("shares:");
        console.log(shares / 1 ether);
        console.log("lastAccruedWeight:");
        console.log(lastAccruedWeight);
    }

}