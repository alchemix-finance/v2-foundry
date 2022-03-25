// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "ds-test/test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {CheatCodes} from "./Cheatcodes.sol";

import {AlchemistV2} from "../../AlchemistV2.sol";
import {AlchemicTokenV2} from "../../AlchemicTokenV2.sol";
import {TransmuterV2} from  "../../TransmuterV2.sol";
import {TransmuterBuffer} from "../../TransmuterBuffer.sol";

import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {YearnVaultMock} from "./mocks/yearn/YearnVaultMock.sol";
import {YearnTokenAdapter} from "../../adapters/yearn/YearnTokenAdapter.sol";
import {Whitelist} from "../../utils/Whitelist.sol";

import {IAlchemistV2AdminActions} from "../../interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {IAlchemistV2} from "../../interfaces/IAlchemistV2.sol";

contract Functionalities is DSTest {

    // Callable contract variables
    AlchemistV2      alchemist;
    TransmuterV2     transmuter;
    TransmuterBuffer transmuterBuffer;

    // Proxy variables
    TransparentUpgradeableProxy proxyAlchemist;
    TransparentUpgradeableProxy proxyTransmuter;
    TransparentUpgradeableProxy proxyTransmuterBuffer;

    // Contract variables
    CheatCodes        cheats = CheatCodes(HEVM_ADDRESS);
    AlchemistV2       alchemistLogic;
    AlchemicTokenV2   alToken;
    YearnTokenAdapter yearnAdapter;
    TransmuterV2      transmuterLogic;
    TransmuterBuffer  transmuterBufferLogic;
    ERC20Mock         daiFake;
    YearnVaultMock    yearnFake;
    Whitelist         whitelist;

    // Parameters for AlchemicTokenV2
    string  public _name;
    string  public _symbol;
    uint256 public _flashFee;

    address public alOwner;
    address public protocolFeeReceiver = address(10);

    function turnOn(address caller, address proxyOwner) public {
        cheats.assume(caller     != address(0));
        cheats.assume(proxyOwner != address(0));
        cheats.assume(caller     != proxyOwner);
        cheats.startPrank(caller);

        // Fake tokens
        daiFake   = new ERC20Mock("fakeDAI", "fDAI", 18);
        yearnFake = new YearnVaultMock(address(daiFake));

        // Contracts and logic contracts
        alOwner               = caller;
        alToken               = new AlchemicTokenV2(_name, _symbol, _flashFee);
        yearnAdapter          = new YearnTokenAdapter(address(yearnFake), address(daiFake));
        transmuterBufferLogic = new TransmuterBuffer();
        transmuterLogic       = new TransmuterV2();
        alchemistLogic        = new AlchemistV2();
        whitelist             = new Whitelist();

        // Proxy contracts
        // TransmuterBuffer proxy
        bytes memory transBufParams = abi.encodeWithSelector(TransmuterBuffer.initialize.selector,
                                                             alOwner,
                                                             address(alToken));

        proxyTransmuterBuffer = new TransparentUpgradeableProxy(address(transmuterBufferLogic),
                                                           proxyOwner,
                                                           transBufParams);

        transmuterBuffer = TransmuterBuffer(address(proxyTransmuterBuffer));

        // TransmuterV2 proxy
        bytes memory transParams = abi.encodeWithSelector(TransmuterV2.initialize.selector,
                                                          address(alToken),
                                                          address(daiFake),
                                                          address(transmuterBuffer),
                                                          whitelist);

        proxyTransmuter = new TransparentUpgradeableProxy(address(transmuterLogic),
                                                     proxyOwner,
                                                     transParams);

        transmuter = TransmuterV2(address(proxyTransmuter));

        // AlchemistV2 proxy
        IAlchemistV2AdminActions.InitializationParams memory params =
            IAlchemistV2AdminActions.InitializationParams({
                admin                    : alOwner,
                debtToken                : address(alToken),
                transmuter               : address(transmuterBuffer),
                minimumCollateralization : 1, //2*10**18,
                protocolFee              : 1000,
                protocolFeeReceiver      : protocolFeeReceiver,
                mintingLimitMinimum      : 1,
                mintingLimitMaximum      : uint256(type(uint160).max),//100000,
                mintingLimitBlocks       : 300,
                whitelist                : address(whitelist)
                });

        bytes memory alchemParams = abi.encodeWithSelector(AlchemistV2.initialize.selector, params);

        proxyAlchemist = new TransparentUpgradeableProxy(address(alchemistLogic), proxyOwner, alchemParams);

        alchemist = AlchemistV2(address(proxyAlchemist));

        // Whitelist alchemist proxy for minting tokens
        alToken.setWhitelist(address(proxyAlchemist), true);
        // Set the alchemist for the transmuterBuffer
        transmuterBuffer.setAlchemist(address(proxyAlchemist));
        // Set the transmuter buffer's transmuter
        transmuterBuffer.setTransmuter(address(daiFake), address(transmuter));
        // Set alOwner as a keeper
        alchemist.setKeeper(alOwner, true);
        // Set flow rate for transmuter buffer
        transmuterBuffer.setFlowRate(address(daiFake), 325e18);

        // Address labels
        cheats.label(alOwner, "Owner address");
        cheats.label(address(yearnAdapter), "yearn adapter");
        cheats.label(address(yearnFake), "yearn token");
        cheats.label(address(daiFake), "dai token");
        cheats.label(address(whitelist), "whitelist contract");
        cheats.label(address(alchemist), "alchemist proxy");
        cheats.label(address(alchemistLogic), "alchemist logic");
        cheats.label(address(transmuterBuffer), "transmuter buffer");
        cheats.label(address(transmuter), "transmuter");
    }

    function addYieldToken (
                     address adapter,
                     uint256 maximumLoss,
                     uint256 maximumExpectedValue,
                     uint256 creditUnlockBlocks) public {

        IAlchemistV2AdminActions.YieldTokenConfig memory config =
            IAlchemistV2AdminActions.YieldTokenConfig({
            adapter              : adapter,
            maximumLoss          : maximumLoss,
            maximumExpectedValue : maximumExpectedValue,
            creditUnlockBlocks   : creditUnlockBlocks
        });

        alchemist.addYieldToken(address(yearnFake), config);
    }

    function addUnderlyingToken (
                                      uint256 repayLimitMinimum,
                                      uint256 repayLimitMaximum,
                                      uint256 repayLimitBlocks,
                                      uint256 liquidationLimitMinimum,
                                      uint256 liquidationLimitMaximum,
                                      uint256 liquidationLimitBlocks
                                      ) public {

        IAlchemistV2AdminActions.UnderlyingTokenConfig memory config =
            IAlchemistV2AdminActions.UnderlyingTokenConfig({
                repayLimitMinimum       : repayLimitMinimum,
                repayLimitMaximum       : repayLimitMaximum,
                repayLimitBlocks        : repayLimitBlocks,
                liquidationLimitMinimum : liquidationLimitMinimum,
                liquidationLimitMaximum : liquidationLimitMaximum,
                liquidationLimitBlocks  : liquidationLimitBlocks
                });

        alchemist.addUnderlyingToken(address(daiFake), config);
    }

    /* After deploying the necessary contracts, `setScenario` adds the yearn yield token */
    /* and the DAI token as its underlying token */
    function setScenario(address caller, address proxyOwner) public {
        turnOn(caller, proxyOwner);

        cheats.startPrank(alOwner);

        addUnderlyingToken(1,
                           1000,
                           10,
                           1,
                           1000,
                           7200);
        alchemist.setUnderlyingTokenEnabled(address(daiFake), true);
        addYieldToken(address(yearnAdapter), 1, 100000e18, 1);
        // Register underlying token for transmuter buffer
        transmuterBuffer.registerAsset(address(daiFake), address(transmuter));
        alchemist.setYieldTokenEnabled(address(yearnFake), true);
    }

    function createCDPs(address[] calldata userList,
                        uint64[]  calldata amountList) public {
        uint256 newMint;
        uint256 balanceOfUser;
        uint256 yearnShares;

        for (uint8 i = 0; i < userList.length; i++) {
            // Restore calls to the owner address
            cheats.startPrank(alOwner);
            cheats.label(userList[i], "user i");

            // Calculate the amount of yearn shares to be minted
            // If 0 shares are to be minted, continue to the next user in the list
            if (amountList[i] == 0) {
                continue;
            } else if (yearnFake.balance() != 0) {
                yearnShares = (amountList[i] * yearnFake.totalSupply()) / yearnFake.balance();
                if (yearnShares == 0) {
                    continue;
                }
            }

            // Start prank with tx.origin = msg.sender
            cheats.startPrank(userList[i], userList[i]);

            daiFake.mint(userList[i], amountList[i]);
            daiFake.increaseAllowance(address(yearnFake), amountList[i]);

            yearnFake.deposit(amountList[i]);
            yearnFake.increaseAllowance(address(alchemist), amountList[i]);

            balanceOfUser = yearnFake.balanceOf(userList[i]);
            emit log_named_uint("balanceOfUser", balanceOfUser);
            alchemist.deposit(address(yearnFake), balanceOfUser, userList[i]);

        }

        cheats.startPrank(alOwner);
    }

    /* Mints some */
    /* TODO: abstract away the yieldToken parameter */
    function mintSome(address[] calldata userList,
                      uint64[]  calldata amountList,
                      address yieldToken) public returns (uint256 totalMinted) {
        uint256 mintAmount;
        uint256 shares;

        for (uint256 i = 0; i < userList.length; i++) {
            // Make sure not to try to mint 0 tokens
            (shares, ) = alchemist.positions(userList[i], yieldToken);
            if (shares == 0) {
                continue;
            }
            totalMinted +=shares;
            // msg.sender = tx.origin
            cheats.startPrank(userList[i], userList[i]);
            emit log_named_uint("amount to mint", shares);
            alchemist.mint(shares, userList[i]);
            alToken.approve(address(alchemist), shares);
        }
        cheats.startPrank(alOwner);
    }

    /* Burns some */
    function burnSome(address[] calldata userList) public returns (uint256 totalBurned) {
        uint256 burnAmount;
        int256 debt;

        for (uint256 i = 0; i < userList.length; i++) {
            (debt, ) = alchemist.accounts(userList[i]);

            // Make sure not to try to burn 0 tokens
            if (debt <= 0) {
                continue;
            }
            assertEq(uint256(debt), alToken.balanceOf(userList[i]));
            // msg.sender = tx.origin
            cheats.startPrank(userList[i], userList[i]);
            totalBurned += alchemist.burn(uint256(debt), userList[i]);
        }
        cheats.startPrank(alOwner);
    }

    /* Liquidates some */
    function liquidateSome(address [] calldata userList,
                           address yieldToken) public returns (uint256 totalLiquidated) {
        uint256 shares;
        uint256 currentLimit;
        uint256 rate;
        int256  debt;
        address underlyingToken = yearnAdapter.underlyingToken();

        for (uint256 i; i < userList.length; i++) {

            // Check if the unrealized debt is 0 or less, in which case we do nothing
            (debt, ) = alchemist.accounts(userList[i]);
            if (debt <= 0) {
                continue;
            }

            cheats.startPrank(userList[i], userList[i]);
            (shares, ) = alchemist.positions(userList[i], yieldToken);
            (currentLimit, rate, ) = alchemist.getLiquidationLimitInfo(underlyingToken);
            cheats.roll(i * rate + 1); // Set block number
            emit log_named_uint("current limit", currentLimit);
            if /* (i == 1) */ (currentLimit <= 0) {
                continue;
            }
            emit log_named_uint("current loop", i);
            emit log_named_uint("userList length", userList.length);
            alchemist.liquidate(yieldToken, currentLimit, 1);
        }

        cheats.startPrank(alOwner);
    }

    /* Repays some */
    function repaySome(address [] calldata userList,
                       address underlyingToken) public returns (uint256 totalRepayed) {
        uint256 currentLimit;
        uint256 rate;
        int256  debt;

        for (uint256 i; i < userList.length; i++) {

            // Check if the unrealized debt is 0 or less, in which case we do nothing
            (debt, ) = alchemist.accounts(userList[i]);
            if (debt <= 0) {
                continue;
            }

            cheats.startPrank(userList[i], userList[i]);
            (currentLimit, rate, ) = alchemist.getRepayLimitInfo(underlyingToken);
            cheats.roll(i * rate + 1); // Set block number
            emit log_named_uint("current limit", currentLimit);
            if /* (i == 1) */ (currentLimit <= 0) {
                continue;
            }
            emit log_named_uint("current loop", i);
            emit log_named_uint("userList length", userList.length);
            alchemist.repay(underlyingToken, currentLimit, userList[i]);
        }

        cheats.startPrank(alOwner);
    }

    function getCreditSentToTransmute(address[] calldata userList,
                                      uint256 claimedBalance) public returns (uint256 credit){
        uint256 unexchangedBalance;
        uint256 exchangedBalance;

        for (uint256 i = 0; i < userList.length; i++) {
            unexchangedBalance += transmuter.getUnexchangedBalance(userList[i]);
            exchangedBalance += transmuter.getExchangedBalance(userList[i]);
        }

        credit = unexchangedBalance +
                 exchangedBalance +
                 transmuterBuffer.getTotalCredit() +
                 claimedBalance;
        //credit = transmuter.totalUnexchanged() + transmuter.totalBuffered - claimedAmount;
        //credit = transmuterBuffer.getTotalCredit() - claimedAmount;
    }
}
