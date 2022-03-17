pragma solidity 0.8.12;

import {console} from "forge-std/console.sol";
import {DSTest} from "ds-test/test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {Hevm} from "./utils/Hevm.sol";
import {Autoleverage} from "../Autoleverage.sol";

contract AutoleverageTest is DSTestPlus {

    Autoleverage helper = new Autoleverage();
    address wethWhale = 0xE78388b4CE79068e89Bf8aA7f218eF6b9AB0e9d0;
    IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address whitelistOwner = 0x526D542FFBAe26D510cD610b8050438586fd203C;


    function setUp() public {
    }

    function testFlashLoan() public {
        address flashLender = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9; // Aave Lending Pool V2
        address alchemist = 0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c; // Alchemist alETH V2
        address yieldToken = 0xa258C4606Ca8206D8aA700cE2143D7db854D168c; // yvWETH
        uint amountInitial = 100;
        uint amountTotal = 200;
        address recipient = wethWhale;
        uint minimumAmountOut = 0;

        address whitelist = IAlchemistV2(alchemist).whitelist();
        console.log(whitelist);

        hevm.prank(whitelistOwner, whitelistOwner);
        IWhitelist(whitelist).disable();

        hevm.startPrank(wethWhale);

        weth.approve(address(helper), amountInitial);
        IAlchemistV2(alchemist).approveMint(address(helper), type(uint).max);
        
        helper.autoleverage(
            flashLender,
            alchemist,
            yieldToken,
            amountInitial,
            amountTotal,
            recipient,
            minimumAmountOut
        );
    }

}