// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "ds-test/test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Invariants} from "./utils/Invariants.sol";

import {ERC20Mock} from "./utils/mocks/ERC20Mock.sol";
import {YearnTokenAdapter} from "../adapters/yearn/YearnTokenAdapter.sol";
import {YearnVaultMock} from "./utils/mocks/yearn/YearnVaultMock.sol";

contract TestInvariants is Invariants {
    //using Sets for Sets.AddressSet;

    function setUp() public {}

    /* Invariant A1: Assume all CDPs are fully updated (using _poke) and no rounding errors. */
    /* Let m be the amount of debt tokens minted by the Alchemist, b the amount of debt tokens */
    /* burned by the Alchemist, d the sum of all debts in the Alchemist, and t the amount of */
    /* underlying tokens sent to the TransmuterBuffer from the Alchemist. Then, m = b + d + t. */
    /* Note that if a CDP has credit (negative debt) this amount is subtracted from d. */
    function testInvariantA1(address caller,
                             address proxyOwner,
                             address[] calldata userList,
                             uint64[]  calldata amountList) public {
        cheats.assume(userList.length <= amountList.length);
        // Enforce that at least be one user, otherwise `harvest` will revert
        // because of no harvestable amount
        cheats.assume(5 < userList.length);
        // Force that at least the first user has some amount
        cheats.assume(0 < amountList[0]);
        // Force that no user is the zero address
        for (uint256 i; i < userList.length; i++) {
            cheats.assume(userList[i] != address(0));
            //cheats.assume(2E18 < amountList[i]);
            for (uint256 j; j < i; j++) {
                cheats.assume(userList[j] != userList[i]);
            }
            cheats.assume(userList[i] != caller);
            cheats.assume(userList[i] != proxyOwner);
        }

        uint256 tokensMinted;
        uint256 tokensBurned;
        uint256 sentToTransmuer;
        uint256 tokensClaimed; // Total amount of tokens claimed from the transmuter
        uint256 creditInTransmuterSystem;

        // Deploy necessary contracts
        turnOn(caller, proxyOwner);

        address yieldToken        = address(yearnFake);
        address underlyingToken   = address(daiFake);
        address yieldTokenAdapter = address(yearnAdapter);

        // Check invariant
        invariantA1(userList, yieldToken, tokensMinted, tokensBurned, sentToTransmuer);

        // Add underlying token but not yield token and check the invariant
        addUnderlyingToken(1,
                           1000,
                           10,
                           1,
                           10000,
                           10);
        invariantA1(userList, yieldToken, tokensMinted, tokensBurned, sentToTransmuer);

        // Add yield token and check invariant
        addYieldToken(yieldTokenAdapter, 1, 100000 ether, 1);
        underlyingToken =
            alchemist.getYieldTokenParameters(yieldToken).underlyingToken;
        invariantA1(userList, yieldToken, tokensMinted, tokensBurned, sentToTransmuer);

        // Enable and disable the tokens before any user interacts with the system
        alchemist.setUnderlyingTokenEnabled(underlyingToken, true);
        // Register underlying token for transmuter buffer
        transmuterBuffer.registerAsset(address(daiFake), address(transmuter));
        invariantA1(userList, yieldToken, tokensMinted, tokensBurned, sentToTransmuer);
        alchemist.setYieldTokenEnabled(yieldToken, true);
        invariantA1(userList, yieldToken, tokensMinted, tokensBurned, sentToTransmuer);

        // Make users create CDPs without minting anything
        createCDPs(userList, amountList);

        // Check invariant
        invariantA1(userList, yieldToken, tokensMinted, tokensBurned, sentToTransmuer);

        // Mint some
        tokensMinted += mintSome(userList, amountList, yieldToken);

        // Check invariant
        invariantA1(userList, yieldToken, tokensMinted, tokensBurned, sentToTransmuer);

        // Burn some
        tokensBurned += burnSome(userList);

        // Check invariant
        invariantA1(userList, yieldToken, tokensMinted, tokensBurned, sentToTransmuer);

        creditInTransmuterSystem = getCreditSentToTransmute(userList, tokensClaimed);
        assertEq(creditInTransmuterSystem, 0);

        // Mint some more
        createCDPs(userList, amountList);
        tokensMinted += mintSome(userList, amountList, yieldToken);

        liquidateSome(userList, yieldToken);

        // Increase yieldToken.pricePerShare() by increasing yieldToken.balance()
        // and not yieldToken.totalSupply().
        // Note that by doing this, the shares issued by yieldToken.deposit() will
        // be zero for small deposits, which can lead to malfunctioning tests
        daiFake.mint(alOwner, YearnVaultMock(yieldToken).totalSupply() * 200);
        daiFake.transfer(yieldToken, YearnVaultMock(yieldToken).totalSupply() * 200);
        assertLt(yearnFake.totalSupply(), daiFake.balanceOf(yieldToken));
        assertLt(1e18, YearnVaultMock(yieldToken).pricePerShare());

        cheats.startPrank(alOwner);
        cheats.warp(1000); // Sets block.timestamp
        alchemist.harvest(yieldToken, 1);


        // Poke all users
        for (uint256 i = 0; i < userList.length; i++) {
            cheats.prank(userList[i], userList[i]);
            alchemist.poke(userList[i]);
        }

        creditInTransmuterSystem = getCreditSentToTransmute(userList, tokensClaimed);
        // Should it be 0  tho?
        assertEq(creditInTransmuterSystem, 0);

        // TODO: Arrange things so that it can be minted again
        // Mint some more
        createCDPs(userList, amountList);
        emit log("CDP'd");
        /* tokensMinted += mintSome(userList, amountList, yieldToken); */

    }

    function testInvariantA1Harvest(address caller,
                                  address proxyOwner,
                                  address[] calldata userList,
                                  uint64[]  calldata amountList) public {
        cheats.assume(userList.length <= amountList.length);
        // Enforce that at least be one user, otherwise `harvest` will revert
        // because of no harvestable amount
        cheats.assume(5 < userList.length);
        // Force that at least the first user has some amount
        //cheats.assume(0 < amountList[0]);
        // Force that no user is the zero address
        for (uint256 i; i < userList.length; i++) {
            cheats.assume(userList[i] != address(0));
            cheats.assume(1e18 < amountList[i]);
            for (uint256 j; j < i; j++) {
                cheats.assume(userList[j] != userList[i]);
            }
            cheats.assume(userList[i] != caller);
            cheats.assume(userList[i] != proxyOwner);
        }
        uint256 tokensMinted;
        uint256 tokensBurned;
        uint256 sentToTransmuer;
        uint256 tokensClaimed; // Total amount of tokens claimed from the transmuter
        uint256 creditInTransmuterSystem;

        address yieldToken      = address(yearnFake);
        address underlyingToken = address(daiFake);

        // Deploy contracts, add yield/underlying tokens and activate them
        setScenario(caller, proxyOwner);

        invariantA1(userList, yieldToken, tokensMinted, tokensBurned, sentToTransmuer);

        createCDPs(userList, amountList);

        invariantA1(userList, yieldToken, tokensMinted, tokensBurned, sentToTransmuer);

        tokensMinted += mintSome(userList, amountList, yieldToken);
        require(0 < tokensMinted, "Nothing was minted");

        // Check invariant
        invariantA1(userList, yieldToken, tokensMinted, tokensBurned, sentToTransmuer);

        // Increase yieldToken.pricePerShare() by increasing yieldToken.balance()
        // and not yieldToken.totalSupply().
        // Note that by doing this, the shares issued by yieldToken.deposit() will
        // be zero for small deposits, which can lead to malfunctioning tests
        daiFake.mint(alOwner, yearnFake.totalSupply() * 200);
        daiFake.transfer(yieldToken, yearnFake.totalSupply() * 200);
        assertLt(yearnFake.totalSupply(), daiFake.balanceOf(yieldToken));
        assertLt(1e18, yearnFake.pricePerShare()); //YearnVaultMock(yieldToken)

        cheats.startPrank(alOwner);
        cheats.warp(10); // Sets block.timestamp
        alchemist.harvest(yieldToken, 1);

        // Check invariant
        invariantA1(userList, yieldToken, tokensMinted, tokensBurned, sentToTransmuer);

    }

    function testInvariantA1Repay(address caller,
                                  address proxyOwner,
                                  address[] calldata userList,
                                  uint64[]  calldata amountList) public {
        cheats.assume(userList.length <= amountList.length);
        // Enforce that at least be one user, otherwise `harvest` will revert
        // because of no harvestable amount
        cheats.assume(0 < userList.length);

        uint256 tokensMinted;
        uint256 tokensBurned;
        uint256 sentToTransmuer;
        uint256 tokensClaimed; // Total amount of tokens claimed from the transmuter
        uint256 creditInTransmuterSystem;

        address yieldToken      = address(yearnFake);
        address underlyingToken = address(daiFake);

        // Deploy contracts, add yield/underlying tokens and activate them
        setScenario(caller, proxyOwner);

        // Check invariant
        invariantA1(userList, yieldToken, tokensMinted, tokensBurned, sentToTransmuer);

        // Mint some
        tokensMinted += mintSome(userList, amountList, yieldToken);

        // Check invariant
        invariantA1(userList, yieldToken, tokensMinted, tokensBurned, sentToTransmuer);

        repaySome(userList, underlyingToken);

        // Check invariant
        invariantA1(userList, yieldToken, tokensMinted, tokensBurned, sentToTransmuer);

    }

    /* Invariant A2: The total number of shares of a yield token is equal to the sum */
    /* of the shares of that yield token over all CDPs. */
    function testInvariantA2(address caller,
                             address proxyOwner,
                             address[] calldata userList,
                             uint64[]  calldata amountList) public {
        cheats.assume(userList.length <= amountList.length);

        address yieldToken = address(yearnFake);

        // Deploy contracts, add yield/underlying tokens and activate them
        setScenario(caller, proxyOwner);

        // Check the invariant before any user interacts with the system
        invariantA2(userList, yieldToken);

        // Make users create CDPs
        createCDPs(userList, amountList);

        // Check invariant after user interaction with the system occurs
        invariantA2(userList, yieldToken);
    }

    /* Invariant A3: Let b be the balance and t the total number of shares of a given yield token. */
    /* Then, b ≤ t, and b = 0 if and only if t = 0 */
    function testInvariantA3(address caller,
                             address proxyOwner,
                             address[] calldata userList,
                             uint64[]  calldata amountList) public {
        cheats.assume(userList.length <= amountList.length);
        // Enforce that at least be one user, otherwise `harvest` will revert
        // because of no harvestable amount
        cheats.assume(5 < userList.length);
        // Force that at least the first user has some amount
        cheats.assume(0 < amountList[0]);
        // Force that no user is the zero address
        for (uint256 i; i < userList.length; i++) {
            cheats.assume(userList[i] != address(0));
            cheats.assume(userList[i] != proxyOwner);
        }

        address yieldToken = address(yearnFake);
        ERC20Mock underlyingToken = daiFake;

        // Deploy contracts, add yield/underlying tokens and activate them
        setScenario(caller, proxyOwner);

        // Check the invariant before any user interacts with the system
        invariantA3(userList, yieldToken);

        // Make users create CDPs
        createCDPs(userList, amountList);

        // Check invariant after user interaction with the system occurs
        invariantA3(userList, yieldToken);

        mintSome(userList, amountList, yieldToken);

        invariantA3(userList, yieldToken);

        // Increase yieldToken.pricePerShare() by increasing yieldToken.balance()
        // and not yieldToken.totalSupply().
        // Note that by doing this, the shares issued by yieldToken.deposit() will
        // be zero for small deposits, which can lead to malfunctioning tests
        //createCDPs(userList, amountList);
        daiFake.mint(alOwner, yearnFake.totalSupply() * 200);

        assertTrue(address(daiFake) != address(yearnFake));

        daiFake.transfer(address(yearnFake), yearnFake.totalSupply() * 200 );
        assertLt(yearnFake.totalSupply(), daiFake.balanceOf(address(yearnFake)));
        assertLt(1e18, yearnFake.pricePerShare());

        cheats.startPrank(alOwner);
        cheats.warp(10); // Sets block.timestamp
        alchemist.harvest(address(yearnFake), 1);

        invariantA3(userList, yieldToken);

        burnSome(userList);

        invariantA3(userList, yieldToken);

    }

    /* Invariant A7: Assuming the price of a yield token never drops to 0, the expected value */
    /* of the yield token equals 0 only if its balance equals 0. */
    function testInvariantA7(address caller,
                             address proxyOwner,
                             address[] calldata userList,
                             uint64[]  calldata amountList) public {
        cheats.assume(userList.length <= amountList.length);

        address yieldToken = address(yearnFake);

        // Deploy contracts, add yield/underlying tokens and activate them
        setScenario(caller, proxyOwner);

        // Check the invariant before any user interacts with the system
        emit log("Before user interaction");
        invariantA7(userList, yieldToken);
        emit log("Before user interaction check passed");

        // Make users create CDPs
        createCDPs(userList, amountList);

        // Check invariant after user interaction with the system occurs
        emit log("After user interaction");
        invariantA7 (userList, yieldToken);

    }

    /* Invariant A8: If a yield token or its underlying token is not supported in the protocol, */
    /* then no user has any balance in that yield token. */
    function testInvariantA8(address caller,
                             address proxyOwner,
                             address[] calldata userList,
                             uint64[]  calldata amountList) public {
        cheats.assume(userList.length <= amountList.length);

        // Deploy necessary contracts
        turnOn(caller, proxyOwner);

        address yieldToken        = address(yearnFake);
        address underlyingToken   = address(daiFake);
        address yieldTokenAdapter = address(yearnAdapter);

        // Check invariant
        invariantA8(userList, yieldToken, underlyingToken);

        // Add underlying token but not yield token and check the invariant
        addUnderlyingToken(1,
                           1000,
                           10,
                           1,
                           10000,
                           10);
        invariantA8(userList, yieldToken, underlyingToken);

        // Add yield token and check invariant
        addYieldToken(yieldTokenAdapter, 1, 100000 ether, 1);
        underlyingToken =
            alchemist.getYieldTokenParameters(yieldToken).underlyingToken;
        invariantA8(userList, yieldToken, underlyingToken);

        // Enable and disable the tokens before any user interacts with the system
        alchemist.setUnderlyingTokenEnabled(underlyingToken, true);
        alchemist.setYieldTokenEnabled(yieldToken, true);
        alchemist.setUnderlyingTokenEnabled(underlyingToken, false);
        alchemist.setYieldTokenEnabled(yieldToken, false);
        invariantA8(userList, yieldToken, underlyingToken);

        // Enable the tokens and check the invariant before any user interacts with the system
        alchemist.setUnderlyingTokenEnabled(underlyingToken, true);
        alchemist.setYieldTokenEnabled(yieldToken, true);
        invariantA8(userList, yieldToken, underlyingToken);

        // Make users create CDPs and check invariant
        createCDPs(userList, amountList);
        invariantA8(userList, yieldToken, underlyingToken);

        // Deactivate underlying and yield tokens and check invariant
        alchemist.setUnderlyingTokenEnabled(underlyingToken, false);
        invariantA8(userList, yieldToken, underlyingToken);
        alchemist.setYieldTokenEnabled(yieldToken, false);
        invariantA8(userList, yieldToken, underlyingToken);
    }

}
