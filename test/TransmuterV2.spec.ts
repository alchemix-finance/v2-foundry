import chai from "chai";

import { solidity } from "ethereum-waffle";
import { ethers, upgrades, waffle } from "hardhat";
import {
  BigNumber,
  BigNumberish,
  ContractFactory,
  Signer,
  Wallet,
} from "ethers";
import {
  ERC20Mock,
  TestERC20,
  TransmuterV2,
  TransmuterBufferMock,
  TestYieldToken,
  Whitelist,
  AlchemicTokenV2,
} from "../typechain";
import { parseEther, parseUnits } from "ethers/lib/utils";
import { parseUsdc } from "../utils/helpers";

chai.use(solidity);

const { expect } = chai;

const conversionFactor = BigNumber.from("1000000000000");

interface TokenAdapterFixture {
  underlyingToken: TestERC20;
  underlyingToken6: TestERC20;
  syntheticToken: AlchemicTokenV2;
}

interface TransmuterFixture extends TokenAdapterFixture {
  transmuter: TransmuterV2;
  transmuter6: TransmuterV2;
  transmuterBuffer: TransmuterBufferMock;
}

async function tokenFixture(): Promise<TokenAdapterFixture> {
  const tokenFactory = await ethers.getContractFactory("TestERC20");
  const underlyingToken = (await tokenFactory.deploy(
    BigNumber.from(2).pow(255),
    18
  )) as TestERC20;
  const underlyingToken6 = (await tokenFactory.deploy(
    BigNumber.from(2).pow(255),
    6
  )) as TestERC20;

  const syntheticTokenFactory = await ethers.getContractFactory(
    "AlchemicTokenV2"
  );
  const syntheticToken = (await syntheticTokenFactory.deploy(
    "al TEST",
    "alTEST",
    0
  )) as AlchemicTokenV2;

  return {
    underlyingToken,
    underlyingToken6,
    syntheticToken,
  };
}

async function transmuterFixture([
  deployer,
  caller,
  firstDepositor,
  secondDepositor,
]: Wallet[]): Promise<TransmuterFixture> {
  const { underlyingToken, underlyingToken6, syntheticToken } =
    await tokenFixture();

  const whitelistFactory = await ethers.getContractFactory("Whitelist");
  const whitelist = (await whitelistFactory
    .connect(deployer)
    .deploy()) as Whitelist;

  const transmuterBufferFactory = await ethers.getContractFactory(
    "TransmuterBufferMock"
  );
  const transmuterBuffer = (await transmuterBufferFactory
    .connect(deployer)
    .deploy()) as TransmuterBufferMock;

  const transmuterV2Factory = await ethers.getContractFactory("TransmuterV2");

  const transmuter = (await upgrades.deployProxy(
    transmuterV2Factory,
    [
      syntheticToken.address,
      underlyingToken.address,
      transmuterBuffer.address,
      whitelist.address,
    ],
    { unsafeAllow: ["delegatecall", "constructor"] }
  )) as TransmuterV2;
  await transmuter.deployed();

  const transmuter6 = (await upgrades.deployProxy(
    transmuterV2Factory,
    [
      syntheticToken.address,
      underlyingToken6.address,
      transmuterBuffer.address,
      whitelist.address,
    ],
    { unsafeAllow: ["delegatecall", "constructor"] }
  )) as TransmuterV2;
  await transmuter6.deployed();

  await transmuterBuffer.initialize(
    [underlyingToken.address, underlyingToken6.address],
    [transmuter.address, transmuter6.address]
  );

  await transmuter.grantRole(await transmuter.SENTINEL(), deployer.address);
  await transmuter6.grantRole(await transmuter6.SENTINEL(), deployer.address);
  await transmuter.setPause(false);
  await transmuter6.setPause(false);

  const initAmt = parseEther("100000");
  const initAmt6 = parseUsdc("100000");
  await syntheticToken.connect(caller).approve(transmuter.address, initAmt);
  await syntheticToken.connect(caller).approve(transmuter6.address, initAmt);

  await underlyingToken
    .connect(deployer)
    .approve(transmuterBuffer.address, initAmt);
  await underlyingToken6
    .connect(deployer)
    .approve(transmuterBuffer.address, initAmt6);

  await syntheticToken
    .connect(firstDepositor)
    .approve(transmuter.address, initAmt);
  await syntheticToken
    .connect(firstDepositor)
    .approve(transmuter6.address, initAmt);

  await syntheticToken
    .connect(secondDepositor)
    .approve(transmuter.address, initAmt);
  await syntheticToken
    .connect(secondDepositor)
    .approve(transmuter6.address, initAmt);

  await syntheticToken.setWhitelist(deployer.address, true);

  await underlyingToken.mint(deployer.address, parseEther("1000000"));
  await underlyingToken6.mint(deployer.address, parseUsdc("1000000"));

  await underlyingToken.mint(firstDepositor.address, initAmt);
  await underlyingToken.mint(secondDepositor.address, initAmt);
  await underlyingToken.mint(caller.address, initAmt);

  await underlyingToken6.mint(firstDepositor.address, initAmt6);
  await underlyingToken6.mint(secondDepositor.address, initAmt6);
  await underlyingToken6.mint(caller.address, initAmt6);

  await syntheticToken.mint(firstDepositor.address, initAmt);
  await syntheticToken.mint(secondDepositor.address, initAmt);
  await syntheticToken.mint(caller.address, initAmt);

  return {
    underlyingToken,
    underlyingToken6,
    syntheticToken,
    transmuter,
    transmuter6,
    transmuterBuffer,
  };
}

describe("TransmuterV2", () => {
  let syntheticToken: AlchemicTokenV2;
  let underlyingToken: TestERC20;
  let underlyingToken6: TestERC20;
  let transmuter: TransmuterV2;
  let transmuter6: TransmuterV2;
  let transmuterBuffer: TransmuterBufferMock;

  const initAmt = parseEther("100000");

  let deployer: Wallet;
  let caller: Wallet;
  let firstDepositor: Wallet;
  let secondDepositor: Wallet;

  let loadFixture: ReturnType<typeof waffle.createFixtureLoader>;

  before(async () => {
    [deployer, caller, firstDepositor, secondDepositor] =
      waffle.provider.getWallets();
    loadFixture = waffle.createFixtureLoader([
      deployer,
      caller,
      firstDepositor,
      secondDepositor,
    ]);
  });

  beforeEach(async () => {
    ({
      underlyingToken,
      underlyingToken6,
      syntheticToken,
      transmuter,
      transmuter6,
      transmuterBuffer,
    } = await loadFixture(transmuterFixture));
  });

  describe("deposit", () => {
    context("once", async () => {
      const depositAmount = parseEther("500");

      beforeEach(async () => {
        await syntheticToken
          .connect(deployer)
          .mint(caller.address, depositAmount);
        await syntheticToken
          .connect(caller)
          .approve(transmuter.address, depositAmount);
        await transmuter.connect(caller).deposit(depositAmount, caller.address);
      });

      it("updates unexchanged balance", async () => {
        expect(await transmuter.getUnexchangedBalance(caller.address)).equal(
          depositAmount
        );
      });
    });

    context("twice", () => {
      const firstDepositAmount = parseEther("500");
      const secondDepositAmount = parseEther("250");
      const totalAmount = firstDepositAmount.add(secondDepositAmount);

      beforeEach(async () => {
        await syntheticToken
          .connect(deployer)
          .mint(caller.address, totalAmount);

        await syntheticToken
          .connect(caller)
          .approve(transmuter.address, totalAmount);

        await transmuter
          .connect(caller)
          .deposit(firstDepositAmount, caller.address);
        await transmuter
          .connect(caller)
          .deposit(secondDepositAmount, caller.address);
      });

      it("updates unexchanged balance", async () => {
        expect(await transmuter.getUnexchangedBalance(caller.address)).equal(
          totalAmount
        );
      });

      it("updates total unexchanged", async () => {
        expect(await transmuter.totalUnexchanged()).equal(totalAmount);
      });
    });

    context("deposit 500, exchange 300, deposit 100, exchange 300", () => {
      describe("18 decimals", () => {
        beforeEach(async () => {
          await transmuter
            .connect(caller)
            .deposit(parseEther("500"), caller.address);
          await transmuterBuffer
            .connect(deployer)
            .exchange(underlyingToken.address, parseEther("300"));
          await transmuter
            .connect(caller)
            .deposit(parseEther("100"), caller.address);
          await transmuterBuffer
            .connect(deployer)
            .exchange(underlyingToken.address, parseEther("300"));
        });

        it("updates total unexchanged", async () => {
          expect(await transmuter.totalUnexchanged()).equal(parseEther("0")); // 600
        });

        it("updates unexchanged balance", async () => {
          expect(await transmuter.getUnexchangedBalance(caller.address)).equal(
            parseEther("0")
          ); // 150
        });

        it("updates exchanged balance", async () => {
          expect(await transmuter.getExchangedBalance(caller.address)).equal(
            parseEther("600")
          ); // 450
        });
      });

      describe("6 decimals", () => {
        const firstDepositAmount = parseEther("500");
        const secondDepositAmount = parseEther("100");
        const exchangeAmount = parseUsdc("300");
        beforeEach(async () => {
          await transmuter6
            .connect(caller)
            .deposit(firstDepositAmount, caller.address);
          await transmuterBuffer
            .connect(deployer)
            .exchange(underlyingToken6.address, exchangeAmount);
          await transmuter6
            .connect(caller)
            .deposit(secondDepositAmount, caller.address);
          await transmuterBuffer
            .connect(deployer)
            .exchange(underlyingToken6.address, exchangeAmount);
        });

        it("updates total unexchanged", async () => {
          expect(await transmuter6.totalUnexchanged()).equal(parseEther("0")); // 600
        });

        it("updates unexchanged balance", async () => {
          expect(await transmuter6.getUnexchangedBalance(caller.address)).equal(
            parseEther("0")
          ); // 150
        });

        it("updates exchanged balance", async () => {
          expect(await transmuter6.getExchangedBalance(caller.address)).equal(
            firstDepositAmount.add(secondDepositAmount)
          ); // 450
        });
      });
    });

    context("once before exchange and once after", () => {
      describe("18 decimals", () => {
        const firstDepositAmount = parseEther("500");
        const secondDepositAmount = parseEther("250");
        const exchangeAmount = parseEther("250");
        const totalDeposited = firstDepositAmount.add(secondDepositAmount);
        const expectedUnexchangedAmount = totalDeposited.sub(exchangeAmount);

        beforeEach(async () => {
          await transmuter
            .connect(caller)
            .deposit(firstDepositAmount, caller.address);
          await transmuterBuffer
            .connect(deployer)
            .exchange(underlyingToken.address, exchangeAmount);
          await transmuter
            .connect(caller)
            .deposit(secondDepositAmount, caller.address);
        });

        it("updates total unexchanged", async () => {
          expect(await transmuter.totalUnexchanged()).equal(
            totalDeposited.sub(exchangeAmount)
          );
        });

        it("updates unexchanged balance", async () => {
          expect(await transmuter.getUnexchangedBalance(caller.address)).equal(
            expectedUnexchangedAmount
          );
        });

        it("updates exchanged balance", async () => {
          expect(await transmuter.getExchangedBalance(caller.address)).equal(
            exchangeAmount
          );
        });

        it("claims the correct amount", async () => {
          await transmuter
            .connect(caller)
            .claim(exchangeAmount, caller.address);
          expect(await transmuter.getUnexchangedBalance(caller.address)).equal(
            expectedUnexchangedAmount
          );
          expect(await transmuter.getExchangedBalance(caller.address)).equal(0);
        });
      });

      describe("6 decimals", () => {
        const firstDepositAmount = parseEther("500");
        const secondDepositAmount = parseEther("250");
        const exchangeAmount = parseUsdc("250");
        const totalDeposited = firstDepositAmount.add(secondDepositAmount);
        const expectedUnexchangedAmount = totalDeposited.sub(
          exchangeAmount.mul(conversionFactor)
        );

        beforeEach(async () => {
          await transmuter6
            .connect(caller)
            .deposit(firstDepositAmount, caller.address);
          await transmuterBuffer
            .connect(deployer)
            .exchange(underlyingToken6.address, exchangeAmount);
          await transmuter6
            .connect(caller)
            .deposit(secondDepositAmount, caller.address);
        });

        it("updates total unexchanged", async () => {
          expect(await transmuter6.totalUnexchanged()).equal(
            totalDeposited.sub(exchangeAmount.mul(conversionFactor))
          );
        });

        it("updates unexchanged balance", async () => {
          expect(await transmuter6.getUnexchangedBalance(caller.address)).equal(
            expectedUnexchangedAmount
          );
        });

        it("updates exchanged balance", async () => {
          expect(await transmuter6.getExchangedBalance(caller.address)).equal(
            exchangeAmount.mul(conversionFactor)
          );
        });

        it("claims the correct amount", async () => {
          await transmuter6
            .connect(caller)
            .claim(exchangeAmount, caller.address);
          expect(await transmuter6.getUnexchangedBalance(caller.address)).equal(
            expectedUnexchangedAmount
          );
          expect(await transmuter6.getExchangedBalance(caller.address)).equal(
            0
          );
        });
      });
    });

    context("from multiple callers", () => {
      const firstDepositAmount = parseEther("500");
      const secondDepositAmount = parseEther("250");
      const totalDeposited = firstDepositAmount.add(secondDepositAmount);

      beforeEach(async () => {
        await syntheticToken
          .connect(deployer)
          .mint(firstDepositor.address, firstDepositAmount);
        await syntheticToken
          .connect(deployer)
          .mint(secondDepositor.address, secondDepositAmount);
        await transmuter
          .connect(firstDepositor)
          .deposit(firstDepositAmount, firstDepositor.address);
        await transmuter
          .connect(secondDepositor)
          .deposit(secondDepositAmount, secondDepositor.address);
      });

      it("updates total unexchanged", async () => {
        expect(await transmuter.totalUnexchanged()).equal(totalDeposited);
      });

      it("updates unexchanged balance of first depositor", async () => {
        expect(
          await transmuter.getUnexchangedBalance(firstDepositor.address)
        ).equal(firstDepositAmount);
      });

      it("updates unexchanged balance of second depositor", async () => {
        expect(
          await transmuter.getUnexchangedBalance(secondDepositor.address)
        ).equal(secondDepositAmount);
      });
    });

    it("emits a Deposit event", async () => {
      const depositAmount = parseEther("500");

      await expect(
        await transmuter.connect(caller).deposit(depositAmount, caller.address)
      ).to.emit(transmuter, "Deposit");
    });
  });

  describe("withdraw", () => {
    context("all", () => {
      const depositAmount = parseEther("500");
      const withdrawAmount = parseEther("500");

      beforeEach(async () => {
        await transmuter.connect(caller).deposit(depositAmount, caller.address);
        await transmuter
          .connect(caller)
          .withdraw(withdrawAmount, caller.address);
      });

      it("updates total unexchanged", async () => {
        expect(await transmuter.totalUnexchanged()).equal(0);
      });

      it("updates unexchanged balance", async () => {
        expect(await transmuter.getUnexchangedBalance(caller.address)).equal(0);
      });
    });

    context("all after an exchange", () => {
      const initialDepositorAmount = parseEther("250");
      const exchangeAmount = parseEther("100");
      const depositAmount = parseEther("500");

      let initialDepositorExchanged;

      beforeEach(async () => {
        await transmuter
          .connect(firstDepositor)
          .deposit(initialDepositorAmount, firstDepositor.address);
        await transmuterBuffer
          .connect(deployer)
          .exchange(underlyingToken.address, exchangeAmount);

        initialDepositorExchanged = await transmuter.getExchangedBalance(
          firstDepositor.address
        );

        await transmuter
          .connect(secondDepositor)
          .deposit(depositAmount, secondDepositor.address);
        await transmuter
          .connect(secondDepositor)
          .withdraw(depositAmount, secondDepositor.address);
      });

      it("does not affect the total exchanged of the first depositor", async () => {
        expect(
          await transmuter.getExchangedBalance(firstDepositor.address)
        ).equals(initialDepositorExchanged);
      });
    });

    context("partial", () => {
      describe("18 decimals", () => {
        const depositAmount = parseEther("500");
        const withdrawAmount = parseEther("250");
        const expectedTotalUnexchanged = depositAmount.sub(withdrawAmount);
        const expectedUnexchangedBalance = depositAmount.sub(withdrawAmount);

        beforeEach(async () => {
          await transmuter
            .connect(caller)
            .deposit(depositAmount, caller.address);
          await transmuter
            .connect(caller)
            .withdraw(withdrawAmount, caller.address);
        });

        it("updates total unexchanged", async () => {
          expect(await transmuter.totalUnexchanged()).equal(
            expectedTotalUnexchanged
          );
        });

        it("updates unexchanged balance", async () => {
          expect(await transmuter.getUnexchangedBalance(caller.address)).equal(
            expectedUnexchangedBalance
          );
        });
      });

      describe("6 decimals", () => {
        const depositAmount = parseEther("500");
        const withdrawAmount = parseEther("250");
        const expectedTotalUnexchanged = depositAmount.sub(withdrawAmount);
        const expectedUnexchangedBalance = depositAmount.sub(withdrawAmount);

        beforeEach(async () => {
          await transmuter6
            .connect(caller)
            .deposit(depositAmount, caller.address);
          await transmuter6
            .connect(caller)
            .withdraw(withdrawAmount, caller.address);
        });

        it("updates total unexchanged", async () => {
          expect(await transmuter6.totalUnexchanged()).equal(
            expectedTotalUnexchanged
          );
        });

        it("updates unexchanged balance", async () => {
          expect(await transmuter6.getUnexchangedBalance(caller.address)).equal(
            expectedUnexchangedBalance
          );
        });
      });
    });

    context("attempt to withdraw more than unexchanged balance", () => {
      const initialDepositorAmount = parseEther("250");
      const exchangeAmount = parseEther("100");
      const withdrawAmount = parseEther("151");

      beforeEach(async () => {
        await transmuter
          .connect(firstDepositor)
          .deposit(initialDepositorAmount, firstDepositor.address);
        await transmuterBuffer
          .connect(deployer)
          .exchange(underlyingToken.address, exchangeAmount);
      });

      it("does not affect the total exchanged of the first depositor", async () => {
        await expect(
          transmuter.connect(firstDepositor).withdraw(withdrawAmount, firstDepositor.address)
        ).reverted;
      });
    })

    it("emits a Withdraw event", async () => {
      const depositAmount = parseEther("500");
      const withdrawAmount = parseEther("500");

      await transmuter.connect(caller).deposit(depositAmount, caller.address);

      await expect(
        await transmuter
          .connect(caller)
          .withdraw(withdrawAmount, caller.address)
      ).emit(transmuter, "Withdraw");
    });
  });

  describe("claim", () => {
    context("after under fulfilling a deposit", () => {
      describe("18 decimals", () => {
        const depositAmount = parseEther("500");
        const exchangeAmount = parseEther("250");

        beforeEach(async () => {
          await transmuter
            .connect(caller)
            .deposit(depositAmount, caller.address);
          await transmuterBuffer
            .connect(deployer)
            .exchange(underlyingToken.address, exchangeAmount);
          // claim can be called w/ dummy arguments 3 and 4 b/c they are not used in the TransmuterMock
          await transmuter
            .connect(caller)
            .claim(exchangeAmount, caller.address);
        });

        it("updates unexchanged balance", async () => {
          expect(await transmuter.getUnexchangedBalance(caller.address)).equal(
            depositAmount.sub(exchangeAmount)
          );
        });

        it("updates exchanged balance", async () => {
          expect(await transmuter.getExchangedBalance(caller.address)).equal(0);
        });
      });

      describe("6 decimals", () => {
        const depositAmount = parseEther("500");
        const claimAmount = parseUsdc("250");
        const exchangeAmount = parseUsdc("250");

        beforeEach(async () => {
          await transmuter6
            .connect(caller)
            .deposit(depositAmount, caller.address);
          await transmuterBuffer
            .connect(deployer)
            .exchange(underlyingToken6.address, exchangeAmount);
          await transmuter6.connect(caller).claim(claimAmount, caller.address);
        });

        it("updates unexchanged balance", async () => {
          expect(await transmuter6.getUnexchangedBalance(caller.address)).equal(
            depositAmount.sub(exchangeAmount.mul(conversionFactor))
          );
        });

        it("updates exchanged balance", async () => {
          expect(await transmuter6.getExchangedBalance(caller.address)).equal(
            0
          );
        });
      });
    });

    context("after exactly fulfilling a deposit", () => {
      describe("18 decimals", () => {
        const depositAmount = parseEther("500");
        const exchangeAmount = parseEther("500");

        beforeEach(async () => {
          await transmuter
            .connect(caller)
            .deposit(depositAmount, caller.address);
          await transmuterBuffer
            .connect(deployer)
            .exchange(underlyingToken.address, exchangeAmount);
          // claim can be called w/ dummy arguments 3 and 4 b/c they are not used in the TransmuterMock
          await transmuter.connect(caller).claim(depositAmount, caller.address);
        });

        it("updates unexchanged balance", async () => {
          expect(await transmuter.getUnexchangedBalance(caller.address)).equal(
            0
          );
        });

        it("updates exchanged balance", async () => {
          expect(await transmuter.getExchangedBalance(caller.address)).equal(0);
        });
      });

      describe("6 decimals", () => {
        const depositAmount = parseEther("500");
        const claimAmount = parseUsdc("500");
        const exchangeAmount = parseUsdc("500");

        beforeEach(async () => {
          await transmuter6
            .connect(caller)
            .deposit(depositAmount, caller.address);
          await transmuterBuffer
            .connect(deployer)
            .exchange(underlyingToken6.address, exchangeAmount);
          await transmuter6.connect(caller).claim(claimAmount, caller.address);
        });

        it("updates unexchanged balance", async () => {
          expect(await transmuter6.getUnexchangedBalance(caller.address)).equal(
            0
          );
        });

        it("updates exchanged balance", async () => {
          expect(await transmuter6.getExchangedBalance(caller.address)).equal(
            0
          );
        });
      });
    });

    context("after over fulfilling a deposit", () => {
      describe("18 decimals", () => {
        const depositAmount = parseEther("500");
        const exchangeAmount = parseEther("1000");

        beforeEach(async () => {
          await transmuter
            .connect(caller)
            .deposit(depositAmount, caller.address);
          await transmuterBuffer
            .connect(deployer)
            .exchange(underlyingToken.address, exchangeAmount);
          // claim can be called w/ dummy arguments 3 and 4 b/c they are not used in the TransmuterMock
          await transmuter.connect(caller).claim(depositAmount, caller.address);
        });

        it("updates unexchanged balance", async () => {
          expect(await transmuter.getUnexchangedBalance(caller.address)).equal(
            0
          );
        });

        it("updates exchanged balance", async () => {
          expect(await transmuter.getExchangedBalance(caller.address)).equal(0);
        });
      });

      describe("6 decimals", () => {
        const depositAmount = parseEther("500");
        const claimAmount = parseUsdc("500");
        const exchangeAmount = parseUsdc("1000");

        beforeEach(async () => {
          await transmuter6
            .connect(caller)
            .deposit(depositAmount, caller.address);
          await transmuterBuffer
            .connect(deployer)
            .exchange(underlyingToken6.address, exchangeAmount);
          await transmuter6.connect(caller).claim(claimAmount, caller.address);
        });

        it("updates unexchanged balance", async () => {
          expect(await transmuter6.getUnexchangedBalance(caller.address)).equal(
            0
          );
        });

        it("updates exchanged balance", async () => {
          expect(await transmuter6.getExchangedBalance(caller.address)).equal(
            0
          );
        });
      });
    });

    it("emits a Claim event", async () => {
      const depositAmount = parseEther("500");
      const exchangeAmount = parseEther("1000");

      await transmuter.connect(caller).deposit(depositAmount, caller.address);
      await transmuterBuffer
        .connect(deployer)
        .exchange(underlyingToken.address, exchangeAmount);

      await expect(
        transmuter.connect(caller).claim(depositAmount, caller.address)
      ).emit(transmuter, "Claim");
    });

    it("claims to the recipient", async () => {
      const recipient = "0xdead000000000000000000000000000000000000"
      const depositAmount = parseEther("500");
      const exchangeAmount = parseEther("1000");

      await transmuter.connect(caller).deposit(depositAmount, caller.address);
      await transmuterBuffer
        .connect(deployer)
        .exchange(underlyingToken.address, exchangeAmount);

      await transmuter.connect(caller).claim(depositAmount, recipient);

      const deployerBal = await underlyingToken.balanceOf(recipient);
      expect(deployerBal).equal(depositAmount);
    });
  });

  describe("exchange", () => {
    context("when no deposits have been made", () => {
      const exchangeAmount = parseEther("500");

      beforeEach(async () => {
        await transmuterBuffer
          .connect(deployer)
          .exchange(underlyingToken.address, exchangeAmount);
      });

      it("updates total buffered", async () => {
        expect(await transmuter.totalBuffered()).equal(exchangeAmount);
      });
    });

    context("exactly fulfilling a deposit", () => {
      describe("18 decimals", () => {
        const depositAmount = parseEther("500");
        const exchangeAmount = parseEther("500");

        beforeEach(async () => {
          await transmuter
            .connect(caller)
            .deposit(depositAmount, caller.address);
          await transmuterBuffer
            .connect(deployer)
            .exchange(underlyingToken.address, exchangeAmount);
        });

        it("updates total unexchanged", async () => {
          expect(await transmuter.totalUnexchanged()).equal(0);
        });

        it("does not update total buffered", async () => {
          expect(await transmuter.totalBuffered()).equal(0);
        });

        it("updates unexchanged balance", async () => {
          expect(await transmuter.getUnexchangedBalance(caller.address)).equal(
            0
          );
        });

        it("updates exchanged balance", async () => {
          expect(await transmuter.getExchangedBalance(caller.address)).equal(
            depositAmount
          );
        });
      });

      describe("6 decimals", () => {
        const depositAmount = parseEther("500");
        const exchangeAmount = parseUsdc("500");

        beforeEach(async () => {
          await transmuter6
            .connect(caller)
            .deposit(depositAmount, caller.address);
          await transmuterBuffer
            .connect(deployer)
            .exchange(underlyingToken6.address, exchangeAmount);
        });

        it("updates total unexchanged", async () => {
          expect(await transmuter6.totalUnexchanged()).equal(0);
        });

        it("does not update total buffered", async () => {
          expect(await transmuter6.totalBuffered()).equal(0);
        });

        it("updates unexchanged balance", async () => {
          expect(await transmuter6.getUnexchangedBalance(caller.address)).equal(
            0
          );
        });

        it("updates exchanged balance", async () => {
          expect(await transmuter6.getExchangedBalance(caller.address)).equal(
            depositAmount
          );
        });
      });
    });

    context("over fulfilling a deposit", () => {
      describe("18 decimals", () => {
        const depositAmount = parseEther("500");
        const exchangeAmount = parseEther("1000");
        const expectedTotalBuffered = exchangeAmount.sub(depositAmount);

        beforeEach(async () => {
          await transmuter
            .connect(caller)
            .deposit(depositAmount, caller.address);
          await transmuterBuffer
            .connect(deployer)
            .exchange(underlyingToken.address, exchangeAmount);
        });

        it("updates total unexchanged", async () => {
          expect(await transmuter.totalUnexchanged()).equal(0);
        });

        it("updates total buffered", async () => {
          expect(await transmuter.totalBuffered()).equal(expectedTotalBuffered);
        });

        it("updates unexchanged balance", async () => {
          expect(await transmuter.getUnexchangedBalance(caller.address)).equal(
            0
          );
        });

        it("updates exchanged balance", async () => {
          expect(await transmuter.getExchangedBalance(caller.address)).equal(
            depositAmount
          );
        });
      });

      describe("6 decimals", () => {
        const depositAmount = parseEther("500");
        const exchangeAmount = parseUsdc("1000");
        const expectedTotalBuffered = exchangeAmount
          .mul(conversionFactor)
          .sub(depositAmount);

        beforeEach(async () => {
          await transmuter6
            .connect(caller)
            .deposit(depositAmount, caller.address);
          await transmuterBuffer
            .connect(deployer)
            .exchange(underlyingToken6.address, exchangeAmount);
        });

        it("updates total unexchanged", async () => {
          expect(await transmuter6.totalUnexchanged()).equal(0);
        });

        it("updates total buffered", async () => {
          expect(await transmuter6.totalBuffered()).equal(
            expectedTotalBuffered
          );
        });

        it("updates unexchanged balance", async () => {
          expect(await transmuter6.getUnexchangedBalance(caller.address)).equal(
            0
          );
        });

        it("updates exchanged balance", async () => {
          expect(await transmuter6.getExchangedBalance(caller.address)).equal(
            depositAmount
          );
        });
      });
    });

    context("partially fulfilling multiple deposits", () => {
      describe("18 decimals", () => {
        const firstDepositAmount = parseEther("500");
        const secondDepositAmount = parseEther("500");
        const firstExchangeAmount = parseEther("250");
        const secondExchangeAmount = parseEther("500");

        beforeEach(async () => {
          await syntheticToken
            .connect(deployer)
            .mint(firstDepositor.address, firstDepositAmount);
          await syntheticToken
            .connect(deployer)
            .mint(secondDepositor.address, secondDepositAmount);
          await transmuter
            .connect(firstDepositor)
            .deposit(firstDepositAmount, firstDepositor.address);
          await transmuterBuffer
            .connect(deployer)
            .exchange(underlyingToken.address, firstExchangeAmount);
          await transmuter
            .connect(secondDepositor)
            .deposit(secondDepositAmount, secondDepositor.address);
          await transmuterBuffer
            .connect(deployer)
            .exchange(underlyingToken.address, secondExchangeAmount);
        });

        it("updates total unexchanged", async () => {
          expect(await transmuter.totalUnexchanged()).equal(
            secondDepositAmount
          );
        });

        it("updates unexchanged balance of first depositor", async () => {
          expect(
            await transmuter.getUnexchangedBalance(firstDepositor.address)
          ).equal(0);
        });

        it("updates exchanged balance of first depositor", async () => {
          expect(
            await transmuter.getExchangedBalance(firstDepositor.address)
          ).equal(firstDepositAmount);
        });

        it("updates unexchanged balance of second depositor", async () => {
          expect(
            await transmuter.getUnexchangedBalance(secondDepositor.address)
          ).equal(parseEther("250"));
        });

        it("updates exchanged balance of second depositor", async () => {
          expect(
            await transmuter.getExchangedBalance(secondDepositor.address)
          ).equal(parseEther("250"));
        });
      });

      describe("6 decimals", () => {
        const firstDepositAmount = parseEther("500");
        const secondDepositAmount = parseEther("500");
        const firstExchangeAmount = parseUsdc("250");
        const secondExchangeAmount = parseUsdc("500");

        beforeEach(async () => {
          await syntheticToken
            .connect(deployer)
            .mint(firstDepositor.address, firstDepositAmount);
          await syntheticToken
            .connect(deployer)
            .mint(secondDepositor.address, secondDepositAmount);
          await transmuter6
            .connect(firstDepositor)
            .deposit(firstDepositAmount, firstDepositor.address);
          await transmuterBuffer
            .connect(deployer)
            .exchange(underlyingToken6.address, firstExchangeAmount);
          await transmuter6
            .connect(secondDepositor)
            .deposit(secondDepositAmount, secondDepositor.address);
          await transmuterBuffer
            .connect(deployer)
            .exchange(underlyingToken6.address, secondExchangeAmount);
        });

        it("updates total unexchanged", async () => {
          expect(await transmuter6.totalUnexchanged()).equal(
            secondDepositAmount
          );
        });

        it("updates unexchanged balance of first depositor", async () => {
          expect(
            await transmuter6.getUnexchangedBalance(firstDepositor.address)
          ).equal(0);
        });

        it("updates exchanged balance of first depositor", async () => {
          expect(
            await transmuter6.getExchangedBalance(firstDepositor.address)
          ).equal(firstDepositAmount);
        });

        it("updates unexchanged balance of second depositor", async () => {
          expect(
            await transmuter6.getUnexchangedBalance(secondDepositor.address)
          ).equal(parseEther("250"));
        });

        it("updates exchanged balance of second depositor", async () => {
          expect(
            await transmuter6.getExchangedBalance(secondDepositor.address)
          ).equal(parseEther("250"));
        });
      });
    });

    context(
      "partially fulfilling multiple deposits with an unused tick in between",
      () => {
        describe("18 decimals", () => {
          const firstDepositAmount = parseEther("500");
          const secondDepositAmount = parseEther("500");

          const firstExchangeAmount = parseEther("200");
          const secondExchangeAmount = parseEther("50");
          const thirdExchangeAmount = parseEther("500");

          beforeEach(async () => {
            await syntheticToken
              .connect(deployer)
              .mint(firstDepositor.address, firstDepositAmount);
            await syntheticToken
              .connect(deployer)
              .mint(secondDepositor.address, secondDepositAmount);
            await transmuter
              .connect(firstDepositor)
              .deposit(firstDepositAmount, firstDepositor.address);
            await transmuterBuffer
              .connect(deployer)
              .exchange(underlyingToken.address, firstExchangeAmount);
            await transmuterBuffer
              .connect(deployer)
              .exchange(underlyingToken.address, secondExchangeAmount);
            await transmuter
              .connect(secondDepositor)
              .deposit(secondDepositAmount, secondDepositor.address);
            await transmuterBuffer
              .connect(deployer)
              .exchange(underlyingToken.address, thirdExchangeAmount);
          });

          it("updates total unexchanged", async () => {
            expect(await transmuter.totalUnexchanged()).equal(
              secondDepositAmount
            );
          });

          it("updates unexchanged balance of first depositor", async () => {
            expect(
              await transmuter.getUnexchangedBalance(firstDepositor.address)
            ).equal(0);
          });

          it("updates exchanged balance of first depositor", async () => {
            expect(
              await transmuter.getExchangedBalance(firstDepositor.address)
            ).equal(firstDepositAmount);
          });

          it("updates unexchanged balance of second depositor", async () => {
            expect(
              await transmuter.getUnexchangedBalance(secondDepositor.address)
            ).equal(parseEther("250"));
          });

          it("updates exchanged balance of second depositor", async () => {
            expect(
              await transmuter.getExchangedBalance(secondDepositor.address)
            ).equal(parseEther("250"));
          });
        });

        describe("6 decimals", () => {
          const firstDepositAmount = parseEther("500");
          const secondDepositAmount = parseEther("500");

          const firstExchangeAmount = parseUsdc("200");
          const secondExchangeAmount = parseUsdc("50");
          const thirdExchangeAmount = parseUsdc("500");

          beforeEach(async () => {
            await syntheticToken
              .connect(deployer)
              .mint(firstDepositor.address, firstDepositAmount);
            await syntheticToken
              .connect(deployer)
              .mint(secondDepositor.address, secondDepositAmount);
            await transmuter6
              .connect(firstDepositor)
              .deposit(firstDepositAmount, firstDepositor.address);
            await transmuterBuffer
              .connect(deployer)
              .exchange(underlyingToken6.address, firstExchangeAmount);
            await transmuterBuffer
              .connect(deployer)
              .exchange(underlyingToken6.address, secondExchangeAmount);
            await transmuter6
              .connect(secondDepositor)
              .deposit(secondDepositAmount, secondDepositor.address);
            await transmuterBuffer
              .connect(deployer)
              .exchange(underlyingToken6.address, thirdExchangeAmount);
          });

          it("updates total unexchanged", async () => {
            expect(await transmuter6.totalUnexchanged()).equal(
              secondDepositAmount
            );
          });

          it("updates unexchanged balance of first depositor", async () => {
            expect(
              await transmuter6.getUnexchangedBalance(firstDepositor.address)
            ).equal(0);
          });

          it("updates exchanged balance of first depositor", async () => {
            expect(
              await transmuter6.getExchangedBalance(firstDepositor.address)
            ).equal(firstDepositAmount);
          });

          it("updates unexchanged balance of second depositor", async () => {
            expect(
              await transmuter6.getUnexchangedBalance(secondDepositor.address)
            ).equal(parseEther("250"));
          });

          it("updates exchanged balance of second depositor", async () => {
            expect(
              await transmuter6.getExchangedBalance(secondDepositor.address)
            ).equal(parseEther("250"));
          });

          it("reverts when attempting to claim too much", async () => {
            await expect(
              transmuter6
                .connect(secondDepositor)
                .claim(parseEther("10000"), secondDepositor.address)
            ).reverted;
          });
        });
      }
    );

    it("emits a Exchange event", async () => {
      const depositAmount = parseEther("500");
      const exchangeAmount = parseEther("500");

      await transmuter.connect(caller).deposit(depositAmount, caller.address);

      await expect(
        transmuterBuffer
          .connect(deployer)
          .exchange(underlyingToken.address, exchangeAmount)
      ).emit(transmuter, "Exchange");
    });
  });
});
