import chai from "chai";
import { solidity } from "ethereum-waffle";
import { ethers, upgrades, waffle } from "hardhat";
import {
  BigNumber,
  BigNumberish,
  ContractFactory,
  Signer,
  utils,
  constants,
  Wallet,
} from "ethers";
import {
  YearnTokenAdapter,
  TestERC20,
  TestYieldToken,
  TestYieldTokenAdapter,
  AlchemicTokenV2,
  Whitelist,
  AlchemistV2,
  ERC20Mock,
  YearnVaultMock,
  TransmuterMock,
  TransmuterBuffer
} from "../typechain";
import {
  mineBlocks,
  parseUsdc,
  setNextBlockTime,
  increaseTime,
} from "../utils/helpers";
import { parseUnits, TransactionDescription } from "ethers/lib/utils";

const { parseEther, formatEther, hexlify } = utils;

chai.use(solidity);

const { expect } = chai;

const { MaxUint256 } = constants;

interface TokenAdapterFixture {
  underlyingToken: TestERC20;
  underlyingToken6: TestERC20;
  yieldToken: TestYieldToken;
  yieldToken_b: TestYieldToken;
  yieldToken6: TestYieldToken;
  tokenAdapter: TestYieldTokenAdapter;
  tokenAdapter_b: TestYieldTokenAdapter;
  tokenAdapter6: TestYieldTokenAdapter;
}

interface AlchemixFixture extends TokenAdapterFixture {
  debtToken: AlchemicTokenV2;
  alchemist: AlchemistV2;
  transmuterDai: TransmuterMock;
  transmuterUsdc: TransmuterMock;
  transmuterBuffer: TransmuterBuffer;
  whitelist: Whitelist;
}

async function tokenAdapterFixture(): Promise<TokenAdapterFixture> {
  const tokenFactory = await ethers.getContractFactory("TestERC20");
  const underlyingToken = (await tokenFactory.deploy(
    BigNumber.from(2).pow(255),
    18
  )) as TestERC20;
  const underlyingToken6 = (await tokenFactory.deploy(
    BigNumber.from(2).pow(255),
    6
  )) as TestERC20;

  const yieldTokenFactory = await ethers.getContractFactory("TestYieldToken");
  const yieldToken = (await yieldTokenFactory.deploy(underlyingToken.address)) as TestYieldToken;
  const yieldToken_b = (await yieldTokenFactory.deploy(underlyingToken.address)) as TestYieldToken;
  const yieldToken6 = (await yieldTokenFactory.deploy(underlyingToken6.address)) as TestYieldToken;

  const yieldTokenAdapterFactory = await ethers.getContractFactory(
    "TestYieldTokenAdapter"
  );
  const tokenAdapter = (await yieldTokenAdapterFactory.deploy(
    yieldToken.address
  )) as TestYieldTokenAdapter;
  const tokenAdapter_b = (await yieldTokenAdapterFactory.deploy(
    yieldToken_b.address
  )) as TestYieldTokenAdapter;
  const tokenAdapter6 = (await yieldTokenAdapterFactory.deploy(
    yieldToken6.address
  )) as TestYieldTokenAdapter;

  return {
    underlyingToken,
    underlyingToken6,
    yieldToken,
    yieldToken_b,
    yieldToken6,
    tokenAdapter,
    tokenAdapter_b,
    tokenAdapter6,
  };
}

async function alchemixFixture([
  deployer,
  admin,
  sentinel,
  rewards,
  minter,
  keeper,
  user,
]: Wallet[]): Promise<AlchemixFixture> {
  const alchemicTokenFactory = await ethers.getContractFactory(
    "AlchemicTokenV2"
  );
  const debtToken = (await alchemicTokenFactory.deploy(
    "AlTestToken",
    "alTEST",
    1000
  )) as AlchemicTokenV2;

  const {
    underlyingToken,
    underlyingToken6,
    yieldToken,
    yieldToken_b,
    yieldToken6,
    tokenAdapter,
    tokenAdapter_b,
    tokenAdapter6,
  } = await tokenAdapterFixture();

  const transmuterBufferFactory = await ethers.getContractFactory(
    "TransmuterBuffer"
  );
  const transmuterBuffer = (await upgrades.deployProxy(
    transmuterBufferFactory,
    [admin.address, debtToken.address],
    { unsafeAllow: ["delegatecall", "constructor"] }
  )) as TransmuterBuffer;
  await transmuterBuffer.deployed();

  await transmuterBuffer
    .connect(admin)
    .grantRole(await transmuterBuffer.KEEPER(), admin.address);

  const whitelistFactory = await ethers.getContractFactory("Whitelist");
  const whitelist = (await whitelistFactory
    .connect(admin)
    .deploy()) as Whitelist;

  const alchemistFactory = await ethers.getContractFactory("AlchemistV2");

  const alchemist = (await upgrades.deployProxy(
    alchemistFactory,
    [
      {
        admin: admin.address,
        debtToken: debtToken.address,
        transmuter: transmuterBuffer.address,
        minimumCollateralization: parseEther("2"),
        protocolFee: "1000",
        protocolFeeReceiver: rewards.address,
        mintingLimitMaximum: parseUnits("1000000", "ether"),
        mintingLimitBlocks: "1000",
        mintingLimitMinimum: parseUnits("100000", "ether"),
        whitelist: whitelist.address,
      },
    ],
    { unsafeAllow: ["delegatecall", "constructor"] }
  )) as AlchemistV2;

  await debtToken.connect(deployer).setWhitelist(alchemist.address, true);

  await whitelist
    .connect(admin)
    .add(transmuterBuffer.address);
  await alchemist.connect(admin).setKeeper(admin.address, true);

  await alchemist.connect(admin).addUnderlyingToken(underlyingToken.address, {
    repayLimitMaximum: parseUnits("1000000", "ether"),
    repayLimitBlocks: 1000,
    repayLimitMinimum: parseUnits("100000", "ether"),
    liquidationLimitMaximum: parseUnits("1000000", "ether"),
    liquidationLimitBlocks: 1000,
    liquidationLimitMinimum: parseUnits("100000", "ether"),
  });
  await alchemist
    .connect(admin)
    .setUnderlyingTokenEnabled(underlyingToken.address, true);
  await alchemist.connect(admin).addUnderlyingToken(underlyingToken6.address, {
    repayLimitMaximum: BigNumber.from(10).pow(6).mul(1000000),
    repayLimitBlocks: 1000,
    repayLimitMinimum: BigNumber.from(10).pow(6).mul(100000),
    liquidationLimitMaximum: BigNumber.from(10).pow(6).mul(1000000),
    liquidationLimitBlocks: 1000,
    liquidationLimitMinimum: BigNumber.from(10).pow(6).mul(100000),
  });
  await alchemist
    .connect(admin)
    .setUnderlyingTokenEnabled(underlyingToken6.address, true);

  await alchemist.connect(admin).addYieldToken(yieldToken.address, {
    adapter: tokenAdapter.address,
    maximumLoss: 1,
    maximumExpectedValue: parseEther("1000000"),
    creditUnlockBlocks: 1,
  });

  await alchemist.connect(admin).setYieldTokenEnabled(yieldToken.address, true);

  await alchemist.connect(admin).addYieldToken(yieldToken_b.address, {
    adapter: tokenAdapter_b.address,
    maximumLoss: 1,
    maximumExpectedValue: parseEther("1000000"),
    creditUnlockBlocks: 1,
  });

  await alchemist
    .connect(admin)
    .setYieldTokenEnabled(yieldToken_b.address, true);

  await alchemist.connect(admin).addYieldToken(yieldToken6.address, {
    adapter: tokenAdapter6.address,
    maximumLoss: 1,
    maximumExpectedValue: parseEther("1000000"),
    creditUnlockBlocks: 1,
  });

  await alchemist
    .connect(admin)
    .setYieldTokenEnabled(yieldToken6.address, true);

  await transmuterBuffer.connect(admin).setAlchemist(alchemist.address);

  const transmuterFactory = await ethers.getContractFactory("TransmuterMock");
  const transmuterDai = (await transmuterFactory
    .connect(deployer)
    .deploy(
      debtToken.address,
      underlyingToken.address,
      transmuterBuffer.address
    )) as TransmuterMock;
  const transmuterUsdc = (await transmuterFactory
    .connect(deployer)
    .deploy(
      debtToken.address,
      underlyingToken6.address,
      transmuterBuffer.address
    )) as TransmuterMock;
  await alchemist.connect(admin).setTransmuter(transmuterBuffer.address);
  await transmuterDai
    .connect(deployer)
    .setWhitelist(transmuterBuffer.address, true);
  await transmuterUsdc
    .connect(deployer)
    .setWhitelist(transmuterBuffer.address, true);

  await transmuterBuffer
    .connect(admin)
    .registerAsset(underlyingToken.address, transmuterDai.address);
  await transmuterBuffer
    .connect(admin)
    .registerAsset(underlyingToken6.address, transmuterUsdc.address);

  await transmuterBuffer.connect(admin).refreshStrategies();

  const initMintAmt = parseEther("10000");
  await underlyingToken.mint(minter.address, initMintAmt);
  await underlyingToken
    .connect(minter)
    .approve(yieldToken.address, initMintAmt);
  await yieldToken.connect(minter).mint(initMintAmt, minter.address);
  await underlyingToken.mint(user.address, initMintAmt);
  await underlyingToken.connect(user).approve(yieldToken.address, initMintAmt);
  await yieldToken.connect(user).mint(initMintAmt, user.address);

  await underlyingToken.mint(minter.address, initMintAmt);
  await underlyingToken
    .connect(minter)
    .approve(yieldToken_b.address, initMintAmt);
  await yieldToken_b.connect(minter).mint(initMintAmt, minter.address);
  await underlyingToken.mint(user.address, initMintAmt);
  await underlyingToken
    .connect(user)
    .approve(yieldToken_b.address, initMintAmt);
  await yieldToken_b.connect(user).mint(initMintAmt, user.address);

  const initMintAmt6 = parseUsdc("10000");
  await underlyingToken6.mint(minter.address, initMintAmt6);
  await underlyingToken6
    .connect(minter)
    .approve(yieldToken6.address, initMintAmt6);
  await yieldToken6.connect(minter).mint(initMintAmt6, minter.address);
  await underlyingToken6.mint(user.address, initMintAmt6);
  await underlyingToken6
    .connect(user)
    .approve(yieldToken6.address, initMintAmt6);
  await yieldToken6.connect(user).mint(initMintAmt6, user.address);

  return {
    underlyingToken,
    underlyingToken6,
    yieldToken,
    yieldToken_b,
    yieldToken6,
    tokenAdapter,
    tokenAdapter_b,
    tokenAdapter6,
    debtToken,
    alchemist,
    transmuterDai,
    transmuterUsdc,
    transmuterBuffer,
    whitelist,
  };
}

describe("Transmuter Buffer", () => {
  let debtToken: AlchemicTokenV2;
  let underlyingToken: TestERC20;
  let yieldToken: TestYieldToken;
  let yieldToken_b: TestYieldToken;
  let tokenAdapter: TestYieldTokenAdapter;
  let tokenAdapter_b: TestYieldTokenAdapter;
  let underlyingToken6: TestERC20;
  let yieldToken6: TestYieldToken;
  let tokenAdapter6: TestYieldTokenAdapter;
  let alchemist: AlchemistV2;
  let transmuterDai: TransmuterMock;
  let transmuterUsdc: TransmuterMock;
  let transmuterBuffer: TransmuterBuffer;
  let whitelist: Whitelist;

  const initAmt = parseEther("10000");
  const cap = parseEther("1000000");

  let loadFixture: ReturnType<typeof waffle.createFixtureLoader>;
  let deployer: Wallet,
    admin: Wallet,
    sentinel: Wallet,
    rewards: Wallet,
    minter: Wallet,
    keeper: Wallet,
    user: Wallet;

  before(async () => {
    [deployer, admin, sentinel, rewards, minter, keeper, user] =
      waffle.provider.getWallets();
    loadFixture = waffle.createFixtureLoader([
      deployer,
      admin,
      sentinel,
      rewards,
      minter,
      keeper,
      user,
    ]);
  });

  beforeEach(async () => {
    ({
      underlyingToken,
      underlyingToken6,
      yieldToken,
      yieldToken_b,
      yieldToken6,
      tokenAdapter,
      tokenAdapter_b,
      tokenAdapter6,
      debtToken,
      alchemist,
      transmuterDai,
      transmuterUsdc,
      transmuterBuffer,
      whitelist,
    } = await loadFixture(alchemixFixture));
  });

  it("correctly refreshes the strategies from the alchemist", async () => {
    await transmuterBuffer.connect(admin).refreshStrategies();
    const daiStrat1 = await transmuterBuffer
      .connect(admin)
      ._yieldTokens(underlyingToken.address, 0);
    expect(daiStrat1).equal(yieldToken.address);
    const daiStrat2 = await transmuterBuffer
      .connect(admin)
      ._yieldTokens(underlyingToken.address, 1);
    expect(daiStrat2).equal(yieldToken_b.address);
    const usdcStrat = await transmuterBuffer
      .connect(admin)
      ._yieldTokens(underlyingToken6.address, 0);
    expect(usdcStrat).equal(yieldToken6.address);
  });

  it("does not register an asset twice", async () => {
    await expect(
      transmuterBuffer
        .connect(admin)
        .registerAsset(underlyingToken.address, transmuterDai.address)
    ).revertedWith("IllegalState");
  });

  it("does not register an asset that is not supported by the Alchemist", async () => {
    const tokenFactory = await ethers.getContractFactory("TestERC20");
    const newUnderlyingToken = (await tokenFactory.deploy(
      BigNumber.from(2).pow(255),
      18
    )) as TestERC20;
    await expect(
      transmuterBuffer
        .connect(admin)
        .registerAsset(newUnderlyingToken.address, transmuterDai.address)
    ).revertedWith("IllegalState");
  });

  describe("setTransmuter()", () => {
    let newTransmuterDai: TransmuterMock;

    beforeEach(async () => {
      const transmuterFactory = await ethers.getContractFactory("TransmuterMock");
      newTransmuterDai = (await transmuterFactory
        .connect(deployer)
        .deploy(
          debtToken.address,
          underlyingToken.address,
          transmuterBuffer.address
        )) as TransmuterMock;
    })

    it("reverts if underlyingToken is not the same underlying token supported by the transmuter", async () => {
      await expect(transmuterBuffer.connect(admin).setTransmuter(underlyingToken6.address, newTransmuterDai.address)).revertedWith("IllegalArgument()")
    })

    it("sets the transmuter", async () => {
      await transmuterBuffer.connect(admin).setTransmuter(underlyingToken.address, newTransmuterDai.address)
      const newTransmuterAddress = await transmuterBuffer.transmuter(underlyingToken.address);
      expect(newTransmuterAddress).equal(newTransmuterDai.address);
    })
  })

  describe("onERC20Received()", () => {
    const depositAmt = parseEther("100");
    const mintAmt = parseEther("50");

    beforeEach(async () => {
      await transmuterBuffer.connect(admin).refreshStrategies();
      await yieldToken.connect(minter).approve(alchemist.address, depositAmt);
      await alchemist
        .connect(minter)
        .deposit(yieldToken.address, depositAmt, minter.address);
      await alchemist.connect(minter).mint(mintAmt, minter.address);
      // flow rate = 1 dai / sec
      await transmuterBuffer
        .connect(admin)
        .setFlowRate(underlyingToken.address, parseEther("1"));
    });

    it("updates the available flow according to the flow rate", async () => {
      // we will check the flow twice here
      // each call to the evm will increment the block.timestamp by 1, so we want to show this
      await increaseTime(waffle.provider, 1);
      const initFlow = await transmuterBuffer.getAvailableFlow(
        underlyingToken.address
      );

      await alchemist
        .connect(minter)
        .liquidate(yieldToken.address, mintAmt.div(2), mintAmt.div(2));
      const midFlow = await transmuterBuffer.getAvailableFlow(
        underlyingToken.address
      );
      expect(midFlow.sub(initFlow)).equal(parseEther("1"));

      await alchemist
        .connect(minter)
        .liquidate(yieldToken.address, mintAmt.div(2), mintAmt.div(2));
      const endFlow = await transmuterBuffer.getAvailableFlow(
        underlyingToken.address
      );
      expect(endFlow.sub(initFlow)).equal(parseEther("2"));
    });

    it("caps the available flow at the buffered amount", async () => {
      await increaseTime(waffle.provider, 1000);
      await alchemist
        .connect(minter)
        .liquidate(yieldToken.address, mintAmt, mintAmt);
      const availableFlow = await transmuterBuffer.getAvailableFlow(
        underlyingToken.address
      );
      expect(availableFlow).equal(mintAmt);
    });

    it("calls exchange on the correct transmuter", async () => {
      await increaseTime(waffle.provider, 1000);
      await alchemist
        .connect(minter)
        .liquidate(yieldToken.address, mintAmt, mintAmt);
      const exchangedAmtDai = await transmuterDai.totalExchanged();
      const exchangedAmtUsdc = await transmuterUsdc.totalExchanged();

      expect(exchangedAmtDai).equal(mintAmt);
      expect(exchangedAmtUsdc).equal(0);
    });

    it("exchanges the correct amount to the transmuter", async () => {
      await increaseTime(waffle.provider, 10);
      await alchemist
        .connect(minter)
        .liquidate(yieldToken.address, mintAmt, mintAmt);
      const exchangedAmtDai = await transmuterDai.totalExchanged();
      expect(exchangedAmtDai).equal(parseEther("10"));
    });

    it("flushes funds to the amo if the flag is set", async () => {
      const receiverFactory = await ethers.getContractFactory("TestErc20Receiver");
      const receiver = await receiverFactory.deploy();
      const startBal = await underlyingToken.balanceOf(receiver.address);
      await transmuterBuffer.connect(admin).setAmo(underlyingToken.address, receiver.address);
      await transmuterBuffer.connect(admin).setDivertToAmo(underlyingToken.address, true);
      await alchemist
        .connect(minter)
        .liquidate(yieldToken.address, mintAmt, mintAmt);
      const exchangedAmtDai = await transmuterDai.totalExchanged();
      expect(exchangedAmtDai).equal(0);
      const endBal = await underlyingToken.balanceOf(receiver.address);
      expect(endBal.sub(startBal)).equal(mintAmt)
    })
  });

  describe("getTotalUnderlyingBuffered()", () => {
    const depositAmtDai1 = parseEther("1000");
    const depositAmtDai2 = parseEther("500");
    const depositAmtUsdc = parseUsdc("200");
    const liqAmtDai1 = parseEther("100");
    const liqAmtDai2 = parseEther("20");
    const liqAmtUsdc = parseUsdc("50");
    const mintAmt = parseEther("200");

    beforeEach(async () => {
      await transmuterBuffer
        .connect(admin)
        .setFlowRate(underlyingToken.address, parseEther("1"));
      await transmuterBuffer
        .connect(admin)
        .setFlowRate(underlyingToken6.address, parseUsdc("1"));

      await transmuterBuffer.connect(admin).refreshStrategies();

      await yieldToken
        .connect(minter)
        .approve(alchemist.address, depositAmtDai1);
      await alchemist
        .connect(minter)
        .deposit(yieldToken.address, depositAmtDai1, minter.address);
      await yieldToken6
        .connect(minter)
        .approve(alchemist.address, depositAmtUsdc);
      await alchemist
        .connect(minter)
        .deposit(yieldToken6.address, depositAmtUsdc, minter.address);
      await yieldToken_b
        .connect(minter)
        .approve(alchemist.address, depositAmtDai2);
      await alchemist
        .connect(minter)
        .deposit(yieldToken_b.address, depositAmtDai2, minter.address);

      await alchemist.connect(minter).mint(mintAmt, minter.address);

      await alchemist
        .connect(minter)
        .liquidate(yieldToken.address, liqAmtDai1, liqAmtDai1);
      await alchemist
        .connect(minter)
        .liquidate(yieldToken6.address, liqAmtUsdc, liqAmtUsdc);
      await alchemist
        .connect(minter)
        .liquidate(yieldToken_b.address, liqAmtDai2, liqAmtDai2);
    });

    it("returns the correct amount", async () => {
      const totalUnderlyingBufferedDai =
        await transmuterBuffer.getTotalUnderlyingBuffered(
          underlyingToken.address
        );
      expect(totalUnderlyingBufferedDai).equal(liqAmtDai1.add(liqAmtDai2));

      const totalUnderlyingBufferedUsdc =
        await transmuterBuffer.getTotalUnderlyingBuffered(
          underlyingToken6.address
        );
      expect(totalUnderlyingBufferedUsdc).equal(liqAmtUsdc);
    });
  });

  describe("withdraw()", () => {
    const depositAmtDai1 = parseEther("1000");
    const depositAmtDai2 = parseEther("500");
    const depositAmtUsdc = parseUsdc("200");
    const liqAmtDai1 = parseEther("80");
    const liqAmtDai2 = parseEther("20");
    const liqAmtUsdc = parseUsdc("50");
    const mintAmt = parseEther("400");
    const claimAmt = parseEther("10");
    const yieldAmtDai = parseEther("50");
    const yieldAmtUsdc = parseUsdc("50");

    beforeEach(async () => {
      await transmuterBuffer
        .connect(admin)
        .setFlowRate(underlyingToken.address, parseEther("1"));
      await transmuterBuffer
        .connect(admin)
        .setFlowRate(underlyingToken6.address, parseUsdc("1"));

      await transmuterBuffer.connect(admin).refreshStrategies();

      await yieldToken
        .connect(minter)
        .approve(alchemist.address, depositAmtDai1);
      await alchemist
        .connect(minter)
        .deposit(yieldToken.address, depositAmtDai1, minter.address);
      await yieldToken6
        .connect(minter)
        .approve(alchemist.address, depositAmtUsdc);
      await alchemist
        .connect(minter)
        .deposit(yieldToken6.address, depositAmtUsdc, minter.address);
      await yieldToken_b
        .connect(minter)
        .approve(alchemist.address, depositAmtDai2);
      await alchemist
        .connect(minter)
        .deposit(yieldToken_b.address, depositAmtDai2, minter.address);

      await alchemist.connect(minter).mint(mintAmt, minter.address);

      await underlyingToken.approve(yieldToken.address, yieldAmtDai);
      await yieldToken.slurp(yieldAmtDai);

      await underlyingToken6.approve(yieldToken6.address, yieldAmtUsdc);
      await yieldToken6.slurp(yieldAmtUsdc);

      const totalSupply = await yieldToken.totalSupply();
      const minAmtOut = yieldAmtDai.mul(depositAmtDai1.add(depositAmtDai2)).div(totalSupply).mul(1).div(10000);
      const totalSupply6 = await yieldToken6.totalSupply();
      const minAmtOut6 = yieldAmtUsdc.mul(depositAmtUsdc).div(totalSupply6).mul(1).div(10000); //

      await alchemist.connect(admin).harvest(yieldToken.address, minAmtOut.sub(minAmtOut.div(10000)));
      await alchemist.connect(admin).harvest(yieldToken6.address, minAmtOut6.sub(minAmtOut6.div(10000)));
    });

    it("reverts if there is not enough flow available", async () => {
      const minAmtDai1 = liqAmtDai1.mul('999999999999999999').div(parseEther('1'))
      await alchemist
        .connect(minter)
        .liquidate(yieldToken.address, liqAmtDai1, minAmtDai1);
      const minAmtUsdc = liqAmtUsdc.mul('999999999999999999').div(parseEther('1'))
      await alchemist
        .connect(minter)
        .liquidate(yieldToken6.address, liqAmtUsdc, minAmtUsdc);
      const minAmtDai2 = liqAmtDai2.mul('999999999999999999').div(parseEther('1'))
      await alchemist
        .connect(minter)
        .liquidate(yieldToken_b.address, liqAmtDai2, minAmtDai2);
      await expect(
        transmuterUsdc.connect(minter).claim(liqAmtUsdc, minter.address)
      ).revertedWith("IllegalArgument()");
    });

    it("reverts if there is not enough buffered collateral available", async () => {
      const minAmtDai1 = liqAmtDai1.mul('999999999999999999').div(parseEther('1'))
      await alchemist
        .connect(minter)
        .liquidate(yieldToken.address, liqAmtDai1, minAmtDai1);
      const minAmtUsdc = liqAmtUsdc.mul('999999999999999999').div(parseEther('1'))
      await alchemist
        .connect(minter)
        .liquidate(yieldToken6.address, liqAmtUsdc, minAmtUsdc);
      const minAmtDai2 = liqAmtDai2.mul('999999999999999999').div(parseEther('1'))
      await alchemist
        .connect(minter)
        .liquidate(yieldToken_b.address, liqAmtDai2, minAmtDai2);
      await increaseTime(waffle.provider, 1000);
      await alchemist
        .connect(minter)
        .liquidate(yieldToken6.address, liqAmtUsdc, minAmtUsdc);
      await expect(
        transmuterUsdc.connect(minter).claim(liqAmtUsdc.mul(10), minter.address)
      ).revertedWith("IllegalArgument()");
    });

    it("pulls the correct amount of underlying tokens", async () => {
      await transmuterBuffer
        .connect(admin)
        .setWeights(
          underlyingToken.address,
          [yieldToken.address, yieldToken_b.address],
          [1, 3]
        );

      await increaseTime(waffle.provider, 10);
      const minAmtDai1 = liqAmtDai1.mul('999999999999999999').div(parseEther('1'))
      await alchemist
        .connect(minter)
        .liquidate(yieldToken.address, liqAmtDai1, minAmtDai1);
      const minAmtUsdc = liqAmtUsdc.mul('999999999999999999').div(parseEther('1'))
      await alchemist
        .connect(minter)
        .liquidate(yieldToken6.address, liqAmtUsdc, minAmtUsdc);
      const minAmtDai2 = liqAmtDai2.mul('999999999999999999').div(parseEther('1'))
      await alchemist
        .connect(minter)
        .liquidate(yieldToken_b.address, liqAmtDai2, minAmtDai2);

      const bal = await underlyingToken.balanceOf(transmuterBuffer.address);
      const exchanged = await transmuterBuffer.currentExchanged(
        underlyingToken.address
      );
      const bal6 = await underlyingToken6.balanceOf(transmuterBuffer.address);
      const exchanged6 = await transmuterBuffer.currentExchanged(
        underlyingToken6.address
      );

      await transmuterBuffer
        .connect(admin)
        .depositFunds(underlyingToken.address, bal.sub(exchanged));
      await transmuterBuffer
        .connect(admin)
        .depositFunds(underlyingToken6.address, bal6.sub(exchanged6));

      const daiBalBefore = await underlyingToken.balanceOf(minter.address);

      await transmuterDai.connect(minter).claim(claimAmt, minter.address);

      const daiBalAfter = await underlyingToken.balanceOf(minter.address);
      expect(daiBalAfter).equal(daiBalBefore.add(claimAmt));
    });

    it("pulls all funds from the buffer directly", async () => {
      await transmuterBuffer
        .connect(admin)
        .setWeights(
          underlyingToken.address,
          [yieldToken.address, yieldToken_b.address],
          [1, 2]
        );

      await increaseTime(waffle.provider, 1000);
      const minAmtDai1 = liqAmtDai1.mul('999999999999999999').div(parseEther('1'))
      await alchemist
        .connect(minter)
        .liquidate(yieldToken.address, liqAmtDai1, minAmtDai1);
      const minAmtUsdc = liqAmtUsdc.mul('999999999999999999').div(parseEther('1'))
      await alchemist
        .connect(minter)
        .liquidate(yieldToken6.address, liqAmtUsdc, minAmtUsdc);
      const minAmtDai2 = liqAmtDai2.mul('999999999999999999').div(parseEther('1'))
      await alchemist
        .connect(minter)
        .liquidate(yieldToken_b.address, liqAmtDai2, minAmtDai2);

      const balBefore = await underlyingToken.balanceOf(
        transmuterBuffer.address
      );

      const yDaiPos1_Before = await alchemist.positions(
        transmuterBuffer.address,
        yieldToken.address
      );
      const yDaiPos2_Before = await alchemist.positions(
        transmuterBuffer.address,
        yieldToken_b.address
      );

      await transmuterDai.connect(minter).claim(claimAmt, minter.address);

      const balAfter = await underlyingToken.balanceOf(
        transmuterBuffer.address
      );

      const yDaiPos1After = await alchemist.positions(
        transmuterBuffer.address,
        yieldToken.address
      );
      const yDaiPos2After = await alchemist.positions(
        transmuterBuffer.address,
        yieldToken_b.address
      );

      expect(yDaiPos1_Before.shares).equal(yDaiPos1After.shares);
      expect(yDaiPos2_Before.shares).equal(yDaiPos2After.shares);
      expect(balAfter).equal(balBefore.sub(claimAmt));
    });
  });

  describe("setFlowRate()", () => {
    const flowRate = parseEther("1");
    const depositAmtDai1 = parseEther("1000");
    const liqAmtDai1 = parseEther("80");
    const mintAmt = parseEther("400");

    beforeEach(async () => {
      await transmuterBuffer.connect(admin).refreshStrategies();
      await transmuterBuffer
        .connect(admin)
        .setFlowRate(underlyingToken.address, flowRate);
    });

    it("updates the flow rate", async () => {
      const initFlowRate = await transmuterBuffer.flowRate(
        underlyingToken.address
      );

      const newFlowRate = parseEther("2");
      await transmuterBuffer
        .connect(admin)
        .setFlowRate(underlyingToken.address, newFlowRate);
      const endFlowRate = await transmuterBuffer.flowRate(
        underlyingToken.address
      );

      expect(initFlowRate).equal(flowRate);
      expect(endFlowRate).equal(newFlowRate);
    });

    describe("calls transmter.exchange()", () => {
      let initExchanged = parseEther("100");

      beforeEach(async () => {
        initExchanged = await transmuterDai.totalExchanged();

        await yieldToken
          .connect(minter)
          .approve(alchemist.address, depositAmtDai1);
        await alchemist
          .connect(minter)
          .deposit(yieldToken.address, depositAmtDai1, minter.address);
        await alchemist.connect(minter).mint(mintAmt, minter.address);
        await alchemist
          .connect(minter)
          .liquidate(yieldToken.address, liqAmtDai1, liqAmtDai1);
        await transmuterBuffer
          .connect(admin)
          .setFlowRate(underlyingToken.address, flowRate);
      });

      it("calls transmuter.exchange() if availableFlow <= totalBuffered", async () => {
        expect(initExchanged).equal(0);
        const endExchanged = await transmuterDai.totalExchanged();
        const bufferExchanged = await transmuterBuffer.currentExchanged(underlyingToken.address);
        // 5 blocks, 5 seconds, 1 token per second
        expect(endExchanged).equal(parseEther("5"));
        // expect(bufferExchanged).equal(parseEther("5"));
      });

      it("exchanges the remaining buffered balance if available flow surpasses buffered balance", async () => {
        await increaseTime(waffle.provider, 1000);
        await transmuterBuffer
          .connect(admin)
          .setFlowRate(underlyingToken.address, flowRate);

        const endExchanged = await transmuterDai.totalExchanged();
        const bufferExchanged = await transmuterBuffer.currentExchanged(underlyingToken.address);
        expect(endExchanged).equal(liqAmtDai1);
        expect(bufferExchanged).equal(liqAmtDai1);
      });
    });

    it("does not call transmuter.exchange() if initialAvailableFlow > totalBuffered", async () => {
      await yieldToken
        .connect(minter)
        .approve(alchemist.address, depositAmtDai1);
      await alchemist
        .connect(minter)
        .deposit(yieldToken.address, depositAmtDai1, minter.address);
      await alchemist.connect(minter).mint(mintAmt, minter.address);
      await increaseTime(waffle.provider, 1000);
      await alchemist
        .connect(minter)
        .liquidate(yieldToken.address, liqAmtDai1, liqAmtDai1);

      const initExchanged = await transmuterDai.totalExchanged();
      await transmuterBuffer
        .connect(admin)
        .setFlowRate(underlyingToken.address, flowRate);

      const endExchanged = await transmuterDai.totalExchanged();
      expect(initExchanged).equal(endExchanged);
    });
  });

  describe("burn credit", () => {
    const depositAmtDai1 = parseEther("1000");
    const depositAmtDai2 = parseEther("500");
    const depositAmtUsdc = parseUsdc("200");
    const profitAmtDai1 = parseEther("100");
    const profitAmtDai2 = parseEther("100");
    const profitAmtUsdc = parseUsdc("100");
    const mintAmt = parseEther("400");
    const claimAmt = parseEther("10");

    beforeEach(async () => {
      await transmuterBuffer
        .connect(admin)
        .setWeights(
          debtToken.address,
          [yieldToken.address, yieldToken_b.address, yieldToken6.address],
          [1, 3, 4]
        );
    });

    it("reverts if there is no credit to burn", async () => {
      await expect(transmuterBuffer.connect(admin).burnCredit()).revertedWith(
        "IllegalState()"
      );
    });

    describe("burns credit", () => {
      beforeEach(async () => {
        await transmuterBuffer
          .connect(admin)
          .setFlowRate(underlyingToken.address, parseEther("1"));
        await transmuterBuffer
          .connect(admin)
          .setFlowRate(underlyingToken6.address, parseUsdc("1"));

        await transmuterBuffer.connect(admin).refreshStrategies();

        await yieldToken
          .connect(minter)
          .approve(alchemist.address, depositAmtDai1.mul(2));
        await yieldToken6
          .connect(minter)
          .approve(alchemist.address, depositAmtUsdc.mul(2));
        await yieldToken_b
          .connect(minter)
          .approve(alchemist.address, depositAmtDai2.mul(2));

        await alchemist
          .connect(minter)
          .deposit(yieldToken.address, depositAmtDai1, minter.address);
        await alchemist
          .connect(minter)
          .deposit(yieldToken6.address, depositAmtUsdc, minter.address);
        await alchemist
          .connect(minter)
          .deposit(yieldToken_b.address, depositAmtDai2, minter.address);

        await alchemist
          .connect(minter)
          .deposit(
            yieldToken.address,
            depositAmtDai1,
            transmuterBuffer.address
          );
        await alchemist
          .connect(minter)
          .deposit(
            yieldToken6.address,
            depositAmtUsdc,
            transmuterBuffer.address
          );
        await alchemist
          .connect(minter)
          .deposit(
            yieldToken_b.address,
            depositAmtDai2,
            transmuterBuffer.address
          );

        await increaseTime(waffle.provider, 1000);

        await underlyingToken.approve(yieldToken.address, profitAmtDai1);
        await yieldToken.slurp(profitAmtDai1);
        await underlyingToken.approve(yieldToken_b.address, profitAmtDai2);
        await yieldToken_b.slurp(profitAmtDai2);
        await underlyingToken6.approve(yieldToken6.address, profitAmtUsdc);
        await yieldToken6.slurp(profitAmtUsdc);

        const totalSupply1 = await yieldToken.totalSupply();
        const totalSupply2 = await yieldToken_b.totalSupply();
        const totalSupply6 = await yieldToken6.totalSupply();

        const minAmtOut1 = depositAmtDai1.div(totalSupply1)
        const minAmtOut2 = depositAmtDai2.div(totalSupply2)
        const minAmtOut6 = depositAmtUsdc.div(totalSupply6)

        await alchemist.connect(admin).harvest(yieldToken.address, minAmtOut1.sub(minAmtOut1.div(10000)));
        await alchemist.connect(admin).harvest(yieldToken_b.address, minAmtOut2.sub(minAmtOut2.div(10000)));
        await alchemist.connect(admin).harvest(yieldToken6.address, minAmtOut6.sub(minAmtOut6.div(10000)));

        await alchemist.connect(admin).poke(transmuterBuffer.address);
      });

      it("burns credit proportional to the set credit weights", async () => {
        const { debt: startingCredit } = await alchemist.accounts(
          transmuterBuffer.address
        );

        await expect(transmuterBuffer.connect(admin).burnCredit())
          .emit(alchemist, "Donate")
          .withArgs(
            transmuterBuffer.address,
            yieldToken.address,
            startingCredit.mul(-1).mul(1).div(8)
          )
          .emit(alchemist, "Donate")
          .withArgs(
            transmuterBuffer.address,
            yieldToken_b.address,
            startingCredit.mul(-1).mul(3).div(8)
          )
          .emit(alchemist, "Donate")
          .withArgs(
            transmuterBuffer.address,
            yieldToken6.address,
            startingCredit.mul(-1).mul(4).div(8)
          );
      });

      it("burns all available credit", async () => {
        await transmuterBuffer.connect(admin).burnCredit();
        const bufferAcct = await alchemist.accounts(transmuterBuffer.address);
        expect(bufferAcct.debt).equal(0);
      });

      it("does not retain any debt token", async () => {
        await transmuterBuffer.connect(admin).burnCredit();
        const debtTokenBal = await debtToken.balanceOf(
          transmuterBuffer.address
        );
        expect(debtTokenBal).equal(0);
      });
    });
  });

  describe("weights", () => {
    it("sets the weights", async () => {
      await transmuterBuffer
        .connect(admin)
        .setWeights(
          debtToken.address,
          [yieldToken.address, yieldToken_b.address, yieldToken6.address],
          [1, 2, 4]
        );
      const dai1CreditWeight = await transmuterBuffer
        .connect(admin)
        .getWeight(debtToken.address, yieldToken.address);
      const dai2CreditWeight = await transmuterBuffer
        .connect(admin)
        .getWeight(debtToken.address, yieldToken_b.address);
      const usdcCreditWeight = await transmuterBuffer
        .connect(admin)
        .getWeight(debtToken.address, yieldToken6.address);
      expect(dai1CreditWeight).equal(1);
      expect(dai2CreditWeight).equal(2);
      expect(usdcCreditWeight).equal(4);
    });

    it("reverts when trying to set a yield token weight for an invalid token", async () => {
      await expect(
        transmuterBuffer
          .connect(admin)
          .setWeights(
            underlyingToken.address,
            [yieldToken.address, yieldToken6.address],
            [1, 2]
          )
      ).revertedWith(`IllegalState()`);
    });
  });

  describe("deposit", () => {
    it("reverts if trying to deposit 0", async () => {
      await expect(
        transmuterBuffer
          .connect(admin)
          .depositFunds(underlyingToken.address, "0")
      ).revertedWith("IllegalArgument()");
    });

    it("reverts if it does not have enough funds to fulfill request", async () => {
      await expect(
        transmuterBuffer
          .connect(admin)
          .depositFunds(underlyingToken.address, "10000")
      ).revertedWith("IllegalArgument()");
    });

    it("reverts if caller is not the keeper", async () => {
      await expect(
        transmuterBuffer
          .connect(minter)
          .depositFunds(underlyingToken.address, "10000")
      ).revertedWith("Unauthorized()");
    });

    it("reverts when trying to deposit funds that have already been exchanged in the transmuter", async () => {
      await transmuterBuffer
        .connect(admin)
        .setFlowRate(underlyingToken.address, parseEther("1"));
      await increaseTime(waffle.provider, 49);
      const depAmt = parseEther("100");
      await underlyingToken.transfer(transmuterBuffer.address, depAmt);
      await transmuterBuffer.connect(admin).exchange(underlyingToken.address);
      await expect(
        transmuterBuffer
          .connect(admin)
          .depositFunds(underlyingToken.address, depAmt)
      ).revertedWith("IllegalState()");
    });

    it("deposits underlying tokens according to defined weighting", async () => {
      const depositAmt = parseEther("300");

      await underlyingToken.mint(minter.address, depositAmt);

      await transmuterBuffer
        .connect(admin)
        .setWeights(
          underlyingToken.address,
          [yieldToken.address, yieldToken_b.address],
          [1, 2]
        );

      await transmuterBuffer
        .connect(admin)
        .setFlowRate(underlyingToken.address, parseEther("1"));
      await transmuterBuffer
        .connect(admin)
        .setFlowRate(underlyingToken6.address, parseUsdc("1"));

      await transmuterBuffer.connect(admin).refreshStrategies();

      await underlyingToken
        .connect(minter)
        .transfer(transmuterBuffer.address, depositAmt);

      const daiBalBefore = await underlyingToken.balanceOf(
        transmuterBuffer.address
      );

      const yieldTokenParams = await alchemist.getYieldTokenParameters(
        yieldToken.address
      );
      const yieldToken_b_Params = await alchemist.getYieldTokenParameters(
        yieldToken.address
      );

      const yDaiPos1 = await alchemist.positions(
        transmuterBuffer.address,
        yieldToken.address
      );
      const tokensPerShare = await alchemist.getUnderlyingTokensPerShare(
        yieldToken.address
      );
      const yDaiPositionBefore1 = yDaiPos1.shares
        .mul(tokensPerShare)
        .div((10 ** yieldTokenParams.decimals).toString());
      // const yDaiPositionBefore1 = await alchemist.getAccountStrategyValue(transmuterBuffer.address, yieldToken.address);
      const yDaiPos2 = await alchemist.positions(
        transmuterBuffer.address,
        yieldToken_b.address
      );
      const tokensPerShareb = await alchemist.getUnderlyingTokensPerShare(
        yieldToken_b.address
      );
      // const yDaiPositionBefore2 = await alchemist.getAccountStrategyValue(transmuterBuffer.address, yieldToken_b.address);
      const yDaiPositionBefore2 = yDaiPos2.shares
        .mul(tokensPerShareb)
        .div((10 ** yieldToken_b_Params.decimals).toString());

      await transmuterBuffer
        .connect(admin)
        .depositFunds(underlyingToken.address, depositAmt);

      const daiBalAfter = await underlyingToken.balanceOf(
        transmuterBuffer.address
      );

      const yDaiPos1After = await alchemist.positions(
        transmuterBuffer.address,
        yieldToken.address
      );
      const tokensPerShareAfter = await alchemist.getUnderlyingTokensPerShare(
        yieldToken.address
      );
      const yDaiPositionAfter1 = yDaiPos1After.shares
        .mul(tokensPerShareAfter)
        .div((10 ** yieldTokenParams.decimals).toString());
      // const yDaiPositionAfter1 = await alchemist.getAccountStrategyValue(transmuterBuffer.address, yieldToken.address);
      const yDaiPos2After = await alchemist.positions(
        transmuterBuffer.address,
        yieldToken_b.address
      );
      const tokensPerSharebAfter = await alchemist.getUnderlyingTokensPerShare(
        yieldToken_b.address
      );
      // const yDaiPositionAfter2 = await alchemist.getAccountStrategyValue(transmuterBuffer.address, yieldToken_b.address);
      const yDaiPositionAfter2 = yDaiPos2After.shares
        .mul(tokensPerSharebAfter)
        .div((10 ** yieldToken_b_Params.decimals).toString());

      expect(daiBalAfter).equal(daiBalBefore.sub(depositAmt));
      expect(yDaiPositionAfter1.sub(yDaiPositionBefore1)).equal(
        yDaiPositionAfter2.sub(yDaiPositionBefore2).div(2)
      );
    });
  });

  describe("withdraw from Alchemist", () => {
    const depositAmt = parseEther("1000");
    const withdrawAmt = parseEther("100");

    beforeEach(async () => {
      await transmuterBuffer.connect(admin).refreshStrategies();
      await yieldToken.connect(minter).approve(alchemist.address, depositAmt);
      await alchemist
        .connect(minter)
        .deposit(yieldToken.address, depositAmt, transmuterBuffer.address);
    });

    it("reverts if caller is not the keeper", async () => {
      await expect(
        transmuterBuffer
          .connect(minter)
          .withdrawFromAlchemist(yieldToken.address, withdrawAmt, withdrawAmt)
      ).revertedWith("Unauthorized()");
    });

    it("withdraws collateral to the transmuter buffer", async () => {
      const balBefore = await underlyingToken.balanceOf(
        transmuterBuffer.address
      );
      await transmuterBuffer
        .connect(admin)
        .withdrawFromAlchemist(yieldToken.address, withdrawAmt, withdrawAmt);
      const balAfter = await underlyingToken.balanceOf(
        transmuterBuffer.address
      );
      expect(balAfter.sub(balBefore)).equal(withdrawAmt);
    });
  });

  describe("sources", () => {
    describe("setSource", () => {
      beforeEach(async () => {
        await transmuterBuffer.connect(admin).setSource(admin.address, true);
      });

      it("sets a source to true", async () => {
        const state = await transmuterBuffer.sources(admin.address);
        expect(state).equal(true);
      });

      it("sets a source to false", async () => {
        await transmuterBuffer.connect(admin).setSource(admin.address, false);
        const state = await transmuterBuffer.sources(admin.address);
        expect(state).equal(false);
      });

      it("reverts when trying to set the source to its current state", async () => {
        await expect(
          transmuterBuffer.connect(admin).setSource(admin.address, true)
        ).revertedWith("IllegalArgument()");
      });
    });

    it("only sources can call onERC20Received", async () => {
      await expect(
        transmuterBuffer
          .connect(admin)
          .onERC20Received(underlyingToken.address, parseEther("1"))
      ).revertedWith("Unauthorized()");
    });
  });

  describe("setAlchemist", () => {
    let oldAlchemistAddress: string;
    let newAlchemist: AlchemistV2;

    beforeEach(async () => {
      oldAlchemistAddress = await transmuterBuffer.alchemist();

      const alchemistFactory = await ethers.getContractFactory("AlchemistV2");

      newAlchemist = (await upgrades.deployProxy(
        alchemistFactory,
        [
          {
            admin: admin.address,
            debtToken: debtToken.address,
            transmuter: transmuterBuffer.address,
            minimumCollateralization: parseEther("2"),
            protocolFee: "1000",
            protocolFeeReceiver: rewards.address,
            mintingLimitMaximum: parseUnits("1000000", "ether"),
            mintingLimitBlocks: "1000",
            mintingLimitMinimum: parseUnits("100000", "ether"),
            whitelist: whitelist.address,
          },
        ],
        { unsafeAllow: ["delegatecall", "constructor"] }
      )) as AlchemistV2;

      await transmuterBuffer.connect(admin).setAlchemist(newAlchemist.address);
    });

    it("sets all underlying approvals to 0 for the old alchemist", async () => {
      const allowance = await underlyingToken.allowance(
        transmuterBuffer.address,
        oldAlchemistAddress
      );
      expect(allowance).equal(0);
    });

    it("sets the debt token approval to 0 for the old alchemist", async () => {
      const allowance = await debtToken.allowance(
        transmuterBuffer.address,
        oldAlchemistAddress
      );
      expect(allowance).equal(0);
    });

    it("sets all underlying approvals to uint256.max for the new alchemist", async () => {
      const allowance = await debtToken.allowance(
        transmuterBuffer.address,
        newAlchemist.address
      );
      expect(allowance).equal(
        "115792089237316195423570985008687907853269984665640564039457584007913129639935"
      );
    });

    it("sets the debt token approval to uint256.max for the new alchemist", async () => {
      const allowance = await debtToken.allowance(
        transmuterBuffer.address,
        newAlchemist.address
      );
      expect(allowance).equal(
        "115792089237316195423570985008687907853269984665640564039457584007913129639935"
      );
    });
  });

  describe("exchange()", () => {
    const depositAmt = parseEther("1000");
    const mintAmt = parseEther("500");

    beforeEach(async () => {
      await transmuterBuffer.connect(admin).refreshStrategies();
      await transmuterBuffer
        .connect(admin)
        .setWeights(underlyingToken.address, [yieldToken.address], [1]);

      await yieldToken.connect(minter).approve(alchemist.address, depositAmt);
      await alchemist
        .connect(minter)
        .deposit(yieldToken.address, depositAmt, minter.address);
      await alchemist.connect(minter).mint(mintAmt, minter.address);
      // flow rate = 1 dai / sec
      await transmuterBuffer
        .connect(admin)
        .setFlowRate(underlyingToken.address, parseEther("1"));
    });

    it("reverts if the caller is not a keeper", async () => {
      await expect(
        transmuterBuffer.connect(deployer).exchange(underlyingToken.address)
      ).revertedWith("Unauthorized()");
    });

    it("does not increase currentExchanged if there is nothing to exchange", async () => {
      const cExBefore = await transmuterBuffer.currentExchanged(
        underlyingToken.address
      );
      await transmuterBuffer.connect(admin).exchange(underlyingToken.address);
      const cExAfter = await transmuterBuffer.currentExchanged(
        underlyingToken.address
      );
      expect(cExBefore).equal(cExAfter);
    });

    describe("local balance > available flow", () => {
      let beforeBal;

      beforeEach(async () => {
        await increaseTime(waffle.provider, 49);
        await alchemist.connect(minter).liquidate(yieldToken.address, mintAmt, mintAmt);
        beforeBal = await underlyingToken.balanceOf(transmuterBuffer.address);
        await transmuterBuffer.connect(admin).exchange(underlyingToken.address);
      });

      it("exchanges less funds than the local balance if the available flow is lower than the local balance", async () => {
        const afterBal = await underlyingToken.balanceOf(
          transmuterBuffer.address
        );
        expect(afterBal).equal(beforeBal);
      });

      it("updates the currentExchanged", async () => {
        const cExAfter = await transmuterBuffer.currentExchanged(
          underlyingToken.address
        );
        expect(cExAfter).equal(parseEther("50"));
      });
    });

    describe("local balance < available flow", () => {
      const transferAmt = parseEther("100");
      let beforeBal;

      beforeEach(async () => {
        await increaseTime(waffle.provider, 20);
        await alchemist.connect(minter).liquidate(yieldToken.address, transferAmt, transferAmt);
        await transmuterBuffer
          .connect(admin)
          .depositFunds(underlyingToken.address, transferAmt.div(2));
        await increaseTime(waffle.provider, 150);
        beforeBal = await underlyingToken.balanceOf(transmuterBuffer.address);
      });

      it("pulls some funds from the alchemist", async () => {
        await underlyingToken.transfer(
          transmuterBuffer.address,
          transferAmt.mul(5)
        );
        await transmuterBuffer
          .connect(admin)
          .depositFunds(underlyingToken.address, transferAmt.mul(5));
        await transmuterBuffer.connect(admin).exchange(underlyingToken.address);
        const afterBal = await underlyingToken.balanceOf(
          transmuterBuffer.address
        );
        const currentExchanged = await transmuterBuffer.currentExchanged(
          underlyingToken.address
        );
        const pos = await alchemist.positions(
          transmuterBuffer.address,
          yieldToken.address
        );
        expect(afterBal).equal(currentExchanged);
        // shares are 1:1 with underlying in these tests, since no yield has been harvested by the alchemist
        expect(pos.shares).equal(parseEther("600").sub(afterBal));
      });

      it("pulls all funds from the alchemist", async () => {
        await transmuterBuffer.connect(admin).exchange(underlyingToken.address);
        const afterBal = await underlyingToken.balanceOf(
          transmuterBuffer.address
        );
        const currentExchanged = await transmuterBuffer.currentExchanged(
          underlyingToken.address
        );
        const pos = await alchemist.positions(
          transmuterBuffer.address,
          underlyingToken.address
        );
        expect(afterBal).equal(currentExchanged);
        expect(afterBal.gt(beforeBal)).equal(true);
        expect(pos.shares).equal(0);
      });

      it("has no funds left to pull in the alchemist", async () => {
        const posBefore = await alchemist.positions(
          transmuterBuffer.address,
          yieldToken.address
        );
        await transmuterBuffer
          .connect(admin)
          .withdrawFromAlchemist(yieldToken.address, posBefore.shares, posBefore.shares);
        beforeBal = await underlyingToken.balanceOf(transmuterBuffer.address);
        await transmuterBuffer.connect(admin).exchange(underlyingToken.address);
        const afterBal = await underlyingToken.balanceOf(
          transmuterBuffer.address
        );
        const currentExchanged = await transmuterBuffer.currentExchanged(
          underlyingToken.address
        );
        const pos = await alchemist.positions(
          transmuterBuffer.address,
          underlyingToken.address
        );
        expect(afterBal).equal(currentExchanged);
        expect(afterBal).equal(beforeBal);
        expect(pos.shares).equal(0);
      });

      it("updates the currentExchanged", async () => {
        await transmuterBuffer.connect(admin).exchange(underlyingToken.address);
        const cExAfter = await transmuterBuffer.currentExchanged(
          underlyingToken.address
        );
        expect(cExAfter).equal(parseEther("100"));
      });
    });
  });
});
