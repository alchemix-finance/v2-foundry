import { expect } from "chai";
import { BigNumber, BigNumberish, Wallet } from "ethers";
import { network, ethers, waffle, upgrades } from "hardhat";
import {
  AlchemistV2,
  TestERC20,
  TestTransmuter,
  TestYieldToken,
  TestYieldTokenAdapter,
  AlchemicTokenV2,
  Whitelist,
} from "../typechain";
import {
  defaultAbiCoder,
  keccak256,
  hexlify,
  parseUnits,
  formatEther,
  parseEther,
  formatUnits,
  solidityPack,
} from "ethers/lib/utils";
import { ecsign } from "ethereumjs-util";
import { mineBlocks } from "../utils/helpers";

interface TokenAdapterFixture {
  underlyingToken: TestERC20;
  underlyingToken6: TestERC20;
  rewardToken: TestERC20;
  yieldToken: TestYieldToken;
  yieldToken6: TestYieldToken;
  tokenAdapter: TestYieldTokenAdapter;
  tokenAdapter6: TestYieldTokenAdapter;
}

interface AlchemistFixture extends TokenAdapterFixture {
  debtToken: AlchemicTokenV2;
  transmuter: TestTransmuter;
  alchemist: AlchemistV2;
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
  const rewardToken = (await tokenFactory.deploy(
    BigNumber.from(2).pow(255),
    6
  )) as TestERC20;

  const yieldTokenFactory = await ethers.getContractFactory("TestYieldToken");
  const yieldToken = (await yieldTokenFactory.deploy(underlyingToken.address)) as TestYieldToken;
  const yieldToken6 = (await yieldTokenFactory.deploy(underlyingToken6.address)) as TestYieldToken;

  const yieldTokenAdapterFactory = await ethers.getContractFactory(
    "TestYieldTokenAdapter"
  );
  const tokenAdapter = (await yieldTokenAdapterFactory.deploy(
    yieldToken.address
  )) as TestYieldTokenAdapter;
  const tokenAdapter6 = (await yieldTokenAdapterFactory.deploy(
    yieldToken6.address
  )) as TestYieldTokenAdapter;

  return {
    underlyingToken,
    underlyingToken6,
    yieldToken,
    yieldToken6,
    rewardToken,
    tokenAdapter,
    tokenAdapter6,
  };
}

async function alchemistFixture([
  wallet,
  other,
  admin,
]: Wallet[]): Promise<AlchemistFixture> {
  const tokenFactory = await ethers.getContractFactory("AlchemicTokenV2");
  const debtToken = (await tokenFactory.deploy(
    "alDebt",
    "ALDEBT",
    0
  )) as AlchemicTokenV2;

  const {
    underlyingToken,
    underlyingToken6,
    yieldToken,
    yieldToken6,
    rewardToken,
    tokenAdapter,
    tokenAdapter6,
  } = await tokenAdapterFixture();

  const transmuterFactory = await ethers.getContractFactory("TestTransmuter");
  const transmuter = (await transmuterFactory.deploy()) as TestTransmuter;

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
        transmuter: transmuter.address,
        minimumCollateralization: BigNumber.from(10).pow(18).mul(2),
        protocolFee: 1000,
        protocolFeeReceiver: admin.address,
        mintingLimitMaximum: parseUnits("1000000", "ether"),
        mintingLimitBlocks: 100,
        mintingLimitMinimum: parseUnits("1000", "ether"),
        whitelist: whitelist.address,
      },
    ],
    { unsafeAllow: ["delegatecall"] }
  )) as AlchemistV2;

  await alchemist.connect(admin).setKeeper(admin.address, true);

  await alchemist.connect(admin).addUnderlyingToken(underlyingToken.address, {
    repayLimitMaximum: parseUnits("1000000", "ether"),
    repayLimitBlocks: 100,
    repayLimitMinimum: parseUnits("1000", "ether"),
    liquidationLimitMaximum: parseUnits("1000000", "ether"),
    liquidationLimitBlocks: 100,
    liquidationLimitMinimum: parseUnits("1000", "ether"),
  });

  await alchemist.connect(admin).addUnderlyingToken(underlyingToken6.address, {
    repayLimitMaximum: BigNumber.from(10).pow(6).mul(1000000),
    repayLimitBlocks: 100,
    repayLimitMinimum: BigNumber.from(10).pow(6).mul(1000),
    liquidationLimitMaximum: BigNumber.from(10).pow(6).mul(1000000),
    liquidationLimitBlocks: 100,
    liquidationLimitMinimum: BigNumber.from(10).pow(6).mul(1000),
  });

  await alchemist.connect(admin).addYieldToken(yieldToken.address, {
    adapter: tokenAdapter.address,
    maximumLoss: 1,
    maximumExpectedValue: parseUnits("100000", "ether"),
    creditUnlockBlocks: 1,
  });

  await alchemist.connect(admin).addYieldToken(yieldToken6.address, {
    adapter: tokenAdapter6.address,
    maximumLoss: 1,
    maximumExpectedValue: BigNumber.from(10).pow(6).mul(1000000),
    creditUnlockBlocks: 1,
  });

  await alchemist
    .connect(admin)
    .setUnderlyingTokenEnabled(underlyingToken.address, true);
  await alchemist
    .connect(admin)
    .setUnderlyingTokenEnabled(underlyingToken6.address, true);

  await alchemist.connect(admin).setYieldTokenEnabled(yieldToken.address, true);
  await alchemist
    .connect(admin)
    .setYieldTokenEnabled(yieldToken6.address, true);

  await debtToken.setWhitelist(alchemist.address, true);

  const initMintAmt = parseUnits("10000", "ether");
  await underlyingToken.approve(yieldToken.address, initMintAmt);
  await yieldToken.mint(initMintAmt, wallet.address);

  const initMintAmt6 = parseUnits("10000", "mwei");
  await underlyingToken6.approve(yieldToken6.address, initMintAmt6);
  await yieldToken6.mint(initMintAmt6, wallet.address);
  await underlyingToken6.mint(other.address, initMintAmt6);
  await underlyingToken6
    .connect(other)
    .approve(yieldToken6.address, initMintAmt6);

  return {
    debtToken,
    underlyingToken,
    underlyingToken6,
    yieldToken,
    yieldToken6,
    rewardToken,
    tokenAdapter,
    tokenAdapter6,
    transmuter,
    alchemist,
    whitelist,
  };
}

describe("AlchemistV2", () => {
  let wallet: Wallet, other: Wallet, admin: Wallet, sentinel: Wallet;

  let debtToken: AlchemicTokenV2;
  let underlyingToken: TestERC20;
  let yieldToken: TestYieldToken;
  let tokenAdapter: TestYieldTokenAdapter;
  let underlyingToken6: TestERC20;
  let yieldToken6: TestYieldToken;
  let rewardToken: TestERC20;
  let tokenAdapter6: TestYieldTokenAdapter;
  let transmuter: TestTransmuter;
  let alchemist: AlchemistV2;
  let whitelist: Whitelist;

  let loadFixture: ReturnType<typeof waffle.createFixtureLoader>;

  before(async () => {
    [wallet, other, admin, sentinel] = waffle.provider.getWallets();
    loadFixture = waffle.createFixtureLoader([wallet, other, admin]);
  });

  beforeEach(async () => {
    ({
      underlyingToken,
      yieldToken,
      rewardToken,
      tokenAdapter,
      debtToken,
      transmuter,
      alchemist,
      yieldToken6,
      underlyingToken6,
      tokenAdapter6,
      whitelist,
    } = await loadFixture(alchemistFixture));
  });

  describe("initialize", () => {
    it("reverts if the protocol fee is too large", async () => {
      const alchemistFactory = await ethers.getContractFactory("AlchemistV2");
      await expect(
        upgrades.deployProxy(
          alchemistFactory,
          [
            {
              admin: admin.address,
              debtToken: debtToken.address,
              transmuter: transmuter.address,
              minimumCollateralization: BigNumber.from(10).pow(18).mul(2),
              protocolFee: 10001,
              protocolFeeReceiver: admin.address,
              mintingLimitMaximum: parseUnits("1000000", "ether"),
              mintingLimitBlocks: 1000,
              mintingLimitMinimum: parseUnits("100000", "ether"),
              whitelist: whitelist.address,
            },
          ],
          { unsafeAllow: ["delegatecall"] }
        )
      ).revertedWith("IllegalArgument()");
    });
  });

  describe("supportedUnderlyingTokens", () => {
    it("includes the underlying token", async () => {
      expect(await alchemist.getSupportedUnderlyingTokens()).includes(
        underlyingToken.address
      );
      expect(await alchemist.getSupportedUnderlyingTokens()).includes(
        underlyingToken6.address
      );
    });
  });

  describe("supportedYieldTokens", () => {
    it("includes the yield token", async () => {
      expect(await alchemist.getSupportedYieldTokens()).includes(
        yieldToken.address
      );
      expect(await alchemist.getSupportedYieldTokens()).includes(
        yieldToken6.address
      );
    });
  });

  describe("isSupportedYieldToken", async () => {
    it("indicates the yield token is supported", async () => {
      expect(await alchemist.isSupportedYieldToken(yieldToken.address)).equals(
        true
      );
      expect(await alchemist.isSupportedYieldToken(yieldToken6.address)).equals(
        true
      );
    });
  });

  describe("isSupportedUnderlyingToken", async () => {
    it("indicates the underlying token is supported", async () => {
      expect(
        await alchemist.isSupportedUnderlyingToken(underlyingToken.address)
      ).equals(true);
      expect(
        await alchemist.isSupportedUnderlyingToken(underlyingToken6.address)
      ).equals(true);
    });
  });

  describe("addYieldToken", () => {
    it("reverts if maximum loss is greater than maximum supported value", async () => {
      const maximumValue = await alchemist.BPS();

      await expect(
        alchemist.connect(admin).addYieldToken(yieldToken.address, {
          adapter: tokenAdapter.address,
          maximumLoss: maximumValue.add(1),
          maximumExpectedValue: 1,
          creditUnlockBlocks: 1,
        })
      ).revertedWith("'IllegalArgument()");
    });

    it("reverts if the token has already been added", async () => {
      await expect(
        alchemist.connect(admin).addYieldToken(yieldToken.address, {
          adapter: tokenAdapter.address,
          maximumLoss: 1,
          maximumExpectedValue: 1,
          creditUnlockBlocks: 1,
        })
      ).revertedWith("IllegalState()");
    });

    it("reverts if the tokens mismatch", async () => {
      await expect(
        alchemist.connect(admin).addYieldToken(yieldToken6.address, {
          adapter: tokenAdapter.address,
          maximumLoss: 1,
          maximumExpectedValue: 1,
          creditUnlockBlocks: 1,
        })
      ).revertedWith("IllegalState()");
    });

    it("reverts if the underlying token is not yet supported", async () => {
      const tokenFactory = await ethers.getContractFactory("TestERC20");
      const underlyingToken_unsupported = (await tokenFactory.deploy(
        BigNumber.from(2).pow(255),
        18
      )) as TestERC20;

      const yieldTokenFactory = await ethers.getContractFactory(
        "TestYieldToken"
      );
      const yieldToken_new = await yieldTokenFactory.deploy(
        underlyingToken_unsupported.address
      );

      const yieldTokenAdapterFactory = await ethers.getContractFactory(
        "TestYieldTokenAdapter"
      );
      const tokenAdapter_new = await yieldTokenAdapterFactory.deploy(
        yieldToken_new.address
      );

      await expect(
        alchemist.connect(admin).addYieldToken(yieldToken_new.address, {
          adapter: tokenAdapter_new.address,
          maximumLoss: 1,
          maximumExpectedValue: 1,
          creditUnlockBlocks: 1,
        })
      ).revertedWith(
        `UnsupportedToken(\"${underlyingToken_unsupported.address}\")`
      );
    });
  });

  describe("addUnderlyingToken", () => {
    let dummyToken: TestERC20;

    beforeEach(async () => {
      const tokenFactory = await ethers.getContractFactory("TestERC20");
      dummyToken = (await tokenFactory.deploy(
        BigNumber.from(2).pow(255),
        18
      )) as TestERC20;
    });

    it("reverts if the token has already been added", async () => {
      const params = {
        repayLimitMaximum: parseUnits("1000000", "ether"),
        repayLimitBlocks: 1000,
        repayLimitMinimum: parseUnits("100000", "ether"),
        liquidationLimitMaximum: parseUnits("1000000", "ether"),
        liquidationLimitBlocks: 1000,
        liquidationLimitMinimum: parseUnits("100000", "ether"),
      };
      await expect(
        alchemist
          .connect(admin)
          .addUnderlyingToken(underlyingToken.address, params)
      ).revertedWith("IllegalState()");
    });

    it("reverts if the token has too many decimals", async () => {
      const tokenFactory = await ethers.getContractFactory("TestERC20");
      const bigDecimalToken = (await tokenFactory.deploy(
        BigNumber.from(2).pow(255),
        27
      )) as TestERC20;
      const params = {
        repayLimitMaximum: parseUnits("1000000", "ether"),
        repayLimitBlocks: 1000,
        repayLimitMinimum: parseUnits("100000", "ether"),
        liquidationLimitMaximum: parseUnits("1000000", "ether"),
        liquidationLimitBlocks: 1000,
        liquidationLimitMinimum: parseUnits("100000", "ether"),
      };
      await expect(
        alchemist
          .connect(admin)
          .addUnderlyingToken(bigDecimalToken.address, params)
      ).revertedWith("IllegalArgument()");
    });

    it("reverts if the block cooldown is above the hardcoded limit", async () => {
      const params = {
        repayLimitMaximum: parseUnits("1000000", "ether"),
        repayLimitBlocks: 10000000000000,
        repayLimitMinimum: parseUnits("100000", "ether"),
        liquidationLimitMaximum: parseUnits("1000000", "ether"),
        liquidationLimitBlocks: 1000,
        liquidationLimitMinimum: parseUnits("100000", "ether"),
      };
      await expect(
        alchemist.connect(admin).addUnderlyingToken(dummyToken.address, params)
      ).revertedWith(`IllegalArgument()`);
    });

    it("reverts if the limit is below the hardcoded limit", async () => {
      const params = {
        repayLimitMaximum: parseUnits("10", "ether"),
        repayLimitBlocks: 10000000000000,
        repayLimitMinimum: parseUnits("100000", "ether"),
        liquidationLimitMaximum: parseUnits("1000000", "ether"),
        liquidationLimitBlocks: 1000,
        liquidationLimitMinimum: parseUnits("100000", "ether"),
      };
      await expect(
        alchemist.connect(admin).addUnderlyingToken(dummyToken.address, params)
      ).revertedWith(`IllegalArgument()`);
    });
  });

  describe("setPendingAdmin", () => {
    it("sets the pending admin", async () => {
      await alchemist.connect(admin).setPendingAdmin(other.address);
      expect(await alchemist.pendingAdmin()).equals(other.address);
    });

    it("emits a PendingAdminUpdated event", async () => {
      await expect(alchemist.connect(admin).setPendingAdmin(other.address))
        .to.emit(alchemist, "PendingAdminUpdated")
        .withArgs(other.address);
    });
  });

  describe("setProtocolFee", () => {
    it("sets the protocol fee", async () => {
      await alchemist.connect(admin).setProtocolFee(420);
      const fee = await alchemist.protocolFee();
      expect(fee).equal(420);
    });

    it("reverts if the protocol fee is too high", async () => {
      await expect(alchemist.connect(admin).setProtocolFee(10001)).revertedWith(
        "IllegalArgument()"
      );
    });
  });

  describe("acceptAdmin", () => {
    it("reverts if the pending admin is not set", async () => {
      await expect(alchemist.connect(other).acceptAdmin()).revertedWith(
        "IllegalState()"
      );
    });

    it("reverts if the pending admin is not the caller", async () => {
      await alchemist.connect(admin).setPendingAdmin(other.address);
      await expect(alchemist.connect(admin).acceptAdmin()).revertedWith(
        "Unauthorized()"
      );
    });

    it("sets the admin", async () => {
      await alchemist.connect(admin).setPendingAdmin(other.address);
      await alchemist.connect(other).acceptAdmin();

      expect(await alchemist.admin()).equals(other.address);
    });

    it("resets the pending admin", async () => {
      await alchemist.connect(admin).setPendingAdmin(other.address);
      await alchemist.connect(other).acceptAdmin();

      expect(await alchemist.pendingAdmin()).equals(
        ethers.utils.getAddress("0x0000000000000000000000000000000000000000")
      );
    });

    it("emits a AdminUpdated event", async () => {
      await alchemist.connect(admin).setPendingAdmin(other.address);
      await expect(alchemist.connect(other).acceptAdmin())
        .to.emit(alchemist, "AdminUpdated")
        .withArgs(other.address);
    });

    it("emits a PendingAdminUpdated event", async () => {
      await alchemist.connect(admin).setPendingAdmin(other.address);
      await expect(alchemist.connect(other).acceptAdmin())
        .to.emit(alchemist, "PendingAdminUpdated")
        .withArgs("0x0000000000000000000000000000000000000000");
    });
  });

  describe("setTransmuter", () => {
    it("reverts if the recipient is the 0 address", async () => {
      await expect(
        alchemist
          .connect(admin)
          .setTransmuter("0x0000000000000000000000000000000000000000")
      ).revertedWith("IllegalArgument()");
    });

    it("sets the transmuter address", async () => {
      const value = ethers.utils.getAddress(
        "0x3967E56e1106E5926a21F0EA78ef00A26ed411f1"
      );
      await alchemist.connect(admin).setTransmuter(value);
      expect(await alchemist.transmuter()).equals(value);
    });

    it("emits a TransmuterUpdated event", async () => {
      const value = ethers.utils.getAddress(
        "0x3967e56e1106e5926a21f0ea78ef00a26ed411f1"
      );
      await expect(alchemist.connect(admin).setTransmuter(value))
        .to.emit(alchemist, "TransmuterUpdated")
        .withArgs(value);
    });
  });

  describe("setMinimumCollateralization", () => {
    it("sets the minimum collateralization", async () => {
      const value = BigNumber.from(10).pow(18).mul(3);
      await alchemist.connect(admin).setMinimumCollateralization(value);
      expect(await alchemist.minimumCollateralization()).equals(value);
    });

    it("emits a MinimumCollateralizationUpdated event", async () => {
      const value = BigNumber.from(10).pow(18).mul(3);
      await expect(alchemist.connect(admin).setMinimumCollateralization(value))
        .to.emit(alchemist, "MinimumCollateralizationUpdated")
        .withArgs(value);
    });
  });

  describe("setMaximumLoss", () => {
    it("sets the maximum loss", async () => {
      const value = 5000;
      await alchemist.connect(admin).setMaximumLoss(yieldToken.address, value);
      const { maximumLoss } = await alchemist.getYieldTokenParameters(
        yieldToken.address
      );
      expect(maximumLoss).equals(value);
    });

    it("reverts if not a supported yield token", async () => {
      const value = 5000;
      await expect(
        alchemist.connect(admin).setMaximumLoss(underlyingToken.address, value)
      ).revertedWith('UnsupportedToken("' + underlyingToken.address + '")');
    });

    it("reverts if greater than maximum supported value", async () => {
      const maximumValue = await alchemist.BPS();
      await expect(
        alchemist
          .connect(admin)
          .setMaximumLoss(yieldToken.address, maximumValue.add(1))
      ).revertedWith("IllegalArgument()");
    });

    it("emits a MaximumLossUpdated event", async () => {
      const value = 5000;
      await expect(
        alchemist.connect(admin).setMaximumLoss(yieldToken.address, value)
      )
        .to.emit(alchemist, "MaximumLossUpdated")
        .withArgs(yieldToken.address, value);
    });
  });

  describe("setProtocolFeeReceiver", () => {
    it("reverts if called by anyone but the admin", async () => {
      await expect(alchemist.connect(wallet).setProtocolFeeReceiver(wallet.address)).revertedWith("Unauthorized()")
    })

    it("reverts if the receiver is the 0 address", async () => {
      await expect(alchemist.connect(admin).setProtocolFeeReceiver("0x0000000000000000000000000000000000000000")).revertedWith("IllegalArgument()")
    })

    it("sets the protocol fee receiver", async () => {
      await alchemist.connect(admin).setProtocolFeeReceiver(wallet.address);
      const protocolFeeReceiver = await alchemist.protocolFeeReceiver();
      expect(protocolFeeReceiver).equals(wallet.address)
    })
  })

  describe("setMaximumExpectedValue", () => {
    const maxValue = parseEther("420");

    it("reverts if called by anyone but the admin", async () => {
      await expect(alchemist.connect(wallet).setMaximumExpectedValue(yieldToken.address, maxValue)).revertedWith("Unauthorized()")
    })

    it("reverts if the yieldToken is not supported", async () => {
      const yieldTokenFactory = await ethers.getContractFactory("TestYieldToken");
      const yieldTokenNew = await yieldTokenFactory.deploy(underlyingToken.address);
      await expect(alchemist.connect(admin).setMaximumExpectedValue(yieldTokenNew.address, maxValue)).revertedWith(`UnsupportedToken("${yieldTokenNew.address}")`)
    })

    it("sets the maximumExpectedValue for the specified yieldToken", async () => {
      await alchemist.connect(admin).setMaximumExpectedValue(yieldToken.address, maxValue);
      const yieldTokenParams = await alchemist.getYieldTokenParameters(yieldToken.address);
      expect(yieldTokenParams.maximumExpectedValue).equals(maxValue)
    })
  })

  describe("setTokenAdapter", () => {
    let newAdapter: TestYieldTokenAdapter;

    beforeEach(async () => {
      const yieldTokenAdapterFactory = await ethers.getContractFactory(
        "TestYieldTokenAdapter"
      );
      newAdapter = (await yieldTokenAdapterFactory.deploy(
        yieldToken.address
      )) as TestYieldTokenAdapter;
    })

    it("reverts if called by anyone but the admin", async () => {
      await expect(alchemist.connect(wallet).setTokenAdapter(yieldToken.address, newAdapter.address)).revertedWith("Unauthorized()")
    })

    it("reverts if the adapter does not have the given yieldToken as its token", async () => {
      await expect(alchemist.connect(admin).setTokenAdapter(yieldToken6.address, newAdapter.address)).revertedWith("IllegalState()")
    })

    it("reverts if the yieldToken is not supported", async () => {
      const yieldTokenFactory = await ethers.getContractFactory("TestYieldToken");
      const yieldTokenNew = await yieldTokenFactory.deploy(underlyingToken.address);
      const yieldTokenAdapterFactory = await ethers.getContractFactory(
        "TestYieldTokenAdapter"
      );
      const badAdapter = await yieldTokenAdapterFactory.deploy(
        yieldTokenNew.address
      );
      await expect(alchemist.connect(admin).setTokenAdapter(yieldTokenNew.address, badAdapter.address)).revertedWith(`UnsupportedToken("${yieldTokenNew.address}")`)
    })

    it("sets the adapter for the specified yieldToken", async () => {
      await alchemist.connect(admin).setTokenAdapter(yieldToken.address, newAdapter.address)
      const yieldTokenParams = await alchemist.getYieldTokenParameters(yieldToken.address);
      expect(yieldTokenParams.adapter).equals(newAdapter.address)
    })
  })

  describe("snap", () => {
    it("sets the expected value", async () => {
      const depositAmount = parseUnits("10000", "ether");
      const loss = parseUnits("1", "ether");
      const value = depositAmount.sub(loss);

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await yieldToken.siphon(loss);

      await alchemist.connect(admin).snap(yieldToken.address);
      const { expectedValue } = await alchemist.getYieldTokenParameters(
        yieldToken.address
      );

      expect(expectedValue).equals(value);
    });

    it("reverts if not a supported yield token", async () => {
      await expect(
        alchemist.connect(admin).snap(underlyingToken.address)
      ).revertedWith('UnsupportedToken("' + underlyingToken.address + '")');
    });
  });

  describe("sweep", () => {
    const sweepAmount = parseUnits("10000", "ether");

    beforeEach(async () => {
      await rewardToken.mint(alchemist.address, sweepAmount);
      await rewardToken.approve(alchemist.address, sweepAmount);
    });

    it("emits SweepTokens event", async() => {
      await expect(
        alchemist.connect(admin).sweepTokens(rewardToken.address, 100)
      ).to.emit(alchemist, "SweepTokens")
      .withArgs(rewardToken.address, 100);
    });

    it("reverts if the token is an underlyingToken", async() => {
      await expect(
        alchemist.connect(admin).sweepTokens(underlyingToken.address, 100)
      ).revertedWith('UnsupportedToken("' + underlyingToken.address + '")');
    });

    it("reverts if token is a yield token", async() => {
      await expect(
        alchemist.connect(admin).sweepTokens(yieldToken.address, 100)
      ).revertedWith('UnsupportedToken("' + yieldToken.address + '")');
    });

    it("reverts if caller is not the admin", async() => {
      await expect(
        alchemist.connect(sentinel).sweepTokens(yieldToken.address, 100)
      ).revertedWith('Unauthorized()');
    });    
  })

  describe("approveMint", () => {
    it("sets the mint allowance", async () => {
      const amount = parseUnits("500", "ether");
      await alchemist.approveMint(other.address, amount);
      expect(
        await alchemist.mintAllowance(wallet.address, other.address)
      ).equals(amount);
    });

    it("emits a ApproveMint event", async () => {
      const amount = parseUnits("500", "ether");
      expect(alchemist.approveMint(other.address, amount))
        .to.emit(alchemist, "ApproveMint")
        .withArgs(wallet.address, other.address, amount);
    });
  });

  describe("approveWithdraw", () => {
    it("sets the withdraw allowance", async () => {
      const amount = parseUnits("500", "ether");
      await alchemist.approveWithdraw(
        other.address,
        yieldToken.address,
        amount
      );
      expect(
        await alchemist.withdrawAllowance(
          wallet.address,
          other.address,
          yieldToken.address
        )
      ).equals(amount);
    });

    it("emits a ApproveWithdraw event", async () => {
      const amount = parseUnits("500", "ether");
      expect(
        alchemist.approveWithdraw(other.address, yieldToken.address, amount)
      )
        .to.emit(alchemist, "ApproveWithdraw")
        .withArgs(wallet.address, other.address, yieldToken.address, amount);
    });
  });

  describe("poke", () => {
    let profit: BigNumber,
      profit6: BigNumber,
      startingDebt: BigNumber,
      delta: BigNumber,
      expectedRepayment: BigNumber,
      expectedRepayment6: BigNumber;
    const depositAmount = parseUnits("10000", "ether");
    const depositAmount6 = parseUnits("10000", "mwei");

    beforeEach(async () => {
      profit = parseUnits("1000", "ether");
      profit6 = parseUnits("500", "mwei");
      delta = parseUnits("10000", "wei");

      const fee = profit
        .mul(await alchemist.protocolFee())
        .div(await alchemist.BPS());
      expectedRepayment = profit.sub(fee);

      const fee6 = profit6
        .mul(await alchemist.protocolFee())
        .div(await alchemist.BPS());
      expectedRepayment6 = profit6.sub(fee6).mul("1000000000000"); // normalization

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await yieldToken6.approve(alchemist.address, depositAmount6);
      await alchemist.deposit(
        yieldToken6.address,
        depositAmount6,
        wallet.address
      );

      await underlyingToken.approve(yieldToken.address, profit);
      await yieldToken.slurp(profit);
    });

    it("decreases the debt when yield is earned", async () => {
      const totalSupply = await yieldToken.totalSupply();
      const minAmtOut = profit.mul(depositAmount).div(totalSupply).mul(1).div(10000); // 1bps slippage allowed
      await alchemist.connect(admin).harvest(yieldToken.address, minAmtOut);

      const account = await alchemist.accounts(wallet.address);
      startingDebt = account.debt;
      await alchemist.poke(wallet.address);

      const { debt: endingDebt } = await alchemist.accounts(wallet.address);
      const repaidDebt = startingDebt.sub(endingDebt);

      expect(repaidDebt).closeTo(expectedRepayment, delta.toNumber());
    });

    it("decreases the debt when yield is earned (2 unique-decimal collaterals)", async () => {
      await underlyingToken6.approve(yieldToken6.address, profit6);
      await yieldToken6.slurp(profit6);

      const { debt: startingDebt } = await alchemist.accounts(wallet.address);

      await alchemist.connect(admin).harvest(yieldToken.address, 0);
      await alchemist.connect(admin).harvest(yieldToken6.address, 0);

      await alchemist.poke(wallet.address);

      const { debt: endingDebt } = await alchemist.accounts(wallet.address);
      const repaidDebt = startingDebt.sub(endingDebt);

      expect(repaidDebt).closeTo(
        expectedRepayment.add(expectedRepayment6),
        delta.toNumber()
      );
    });

    it("preharvests any tokens that have earned yield", async () => {
      await alchemist.poke(wallet.address);

      const yToken = await alchemist.getYieldTokenParameters(
        yieldToken.address
      );
      const price = await tokenAdapter.price();
      const expectedBuffer = profit.mul(parseUnits("1", "ether")).div(price);
      expect(yToken.harvestableBalance).equal(expectedBuffer);
      expect(yToken.activeBalance).equal(depositAmount.sub(expectedBuffer));
    });

    it("does NOT preharvest any tokens that have NOT earned yield", async () => {
      await alchemist.poke(wallet.address);

      const yToken = await alchemist.getYieldTokenParameters(
        yieldToken6.address
      );
      expect(yToken.harvestableBalance).equal(0);
      expect(yToken.activeBalance).equal(depositAmount6);
    });
  });

  describe("harvest", () => {
    const depositAmount = parseUnits("10000", "ether");
    const profit = parseUnits("100", "ether");
    const depositAmount6 = parseUnits("10000", "mwei");
    const profit6 = parseUnits("50", "mwei");

    const mintAmt = parseUnits("400", "ether");
    let expectedRepayment: BigNumber, expectedRepayment6: BigNumber;

    beforeEach(async () => {
      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await underlyingToken.approve(yieldToken.address, profit);
      await yieldToken.slurp(profit);

      await yieldToken6.approve(alchemist.address, depositAmount6);
      await alchemist.deposit(
        yieldToken6.address,
        depositAmount6,
        wallet.address
      );

      await underlyingToken6.approve(yieldToken6.address, profit6);
      await yieldToken6.slurp(profit6);

      const fee = profit
        .mul(await alchemist.protocolFee())
        .div(await alchemist.BPS());
      expectedRepayment = profit.sub(fee);

      const fee6 = profit6
        .mul(await alchemist.protocolFee())
        .div(await alchemist.BPS());
      expectedRepayment6 = profit6.sub(fee6).mul("1000000000000"); // normalization

      await alchemist.mint(mintAmt, wallet.address);
    });

    it("emits a Harvest event", async () => {
      const totalSupply = await yieldToken.totalSupply();
      const minAmtOut = profit.mul(depositAmount).div(totalSupply).mul(1).div(10000); // 1bps slippage allowed
      await expect(alchemist.connect(admin).harvest(yieldToken.address, minAmtOut))
        .emit(alchemist, "Harvest")
        .withArgs(yieldToken.address, minAmtOut, "99999999999999999999", "90000000000000000000");
    });

    it("reverts when harvestable balance is zero", async () => {
      const totalSupply = await yieldToken.totalSupply();
      const minAmtOut = profit.mul(depositAmount).div(totalSupply).mul(1).div(10000); // 1bps slippage allowed
      await alchemist.connect(admin).harvest(yieldToken.address, minAmtOut);
      await expect(
        alchemist.connect(admin).harvest(yieldToken.address, minAmtOut)
      ).revertedWith("IllegalState()");
    });

    it("pays off the correct amount of debt", async () => {
      const acctBefore = await alchemist.accounts(wallet.address);

      const totalSupply = await yieldToken.totalSupply();
      const minAmtOut = profit.mul(depositAmount).div(totalSupply).mul(1).div(10000); // 1bps slippage allowed
      const totalSupply6 = await yieldToken6.totalSupply();
      const minAmtOut6 = profit6.mul(depositAmount6).div(totalSupply6).mul(1).div(10000); // 1bps slippage allowed

      await alchemist.connect(admin).harvest(yieldToken.address, minAmtOut);
      await alchemist.connect(admin).harvest(yieldToken6.address, minAmtOut6);
      await alchemist.poke(wallet.address);
      const acctAfter = await alchemist.accounts(wallet.address);
      expect(acctAfter.debt).equal(
        acctBefore.debt.sub(expectedRepayment).sub(expectedRepayment6)
      );
    });

    it("sends the fee to the fee receiver", async () => {
      const balBefore = await underlyingToken.balanceOf(admin.address);
      const totalSupply = await yieldToken.totalSupply();
      const minAmtOut = profit.mul(depositAmount).div(totalSupply).mul(1).div(10000); // 1bps slippage allowed
      await alchemist.connect(admin).harvest(yieldToken.address, minAmtOut);
      const balAfter = await underlyingToken.balanceOf(admin.address);
      const fee = profit
        .mul(await alchemist.protocolFee())
        .div(await alchemist.BPS());
      expect(balAfter).closeTo(balBefore.add(fee), 100);
    });

    it("sends the harvested yield to the transmuter", async () => {
      const balBefore = await underlyingToken.balanceOf(transmuter.address);
      const totalSupply = await yieldToken.totalSupply();
      const minAmtOut = profit.mul(depositAmount).div(totalSupply).mul(1).div(10000); // 1bps slippage allowed
      await alchemist.connect(admin).harvest(yieldToken.address, minAmtOut);
      const balAfter = await underlyingToken.balanceOf(transmuter.address);
      expect(balAfter).equal(balBefore.add(expectedRepayment));
    });

    it("sets the yieldToken.harvestableBalance to 0", async () => {
      const totalSupply = await yieldToken.totalSupply();
      const minAmtOut = profit.mul(depositAmount).div(totalSupply).mul(1).div(10000); // 1bps slippage allowed
      await alchemist.connect(admin).harvest(yieldToken.address, minAmtOut);
      const token = await alchemist.getYieldTokenParameters(yieldToken.address);
      expect(token.harvestableBalance).equal(0);
    });
  });

  describe("slippage", () => {
    const depositAmount = parseEther("100");

    beforeEach(async () => {
      await underlyingToken.approve(alchemist.address, depositAmount)
    })

    it("reverts on depositUnderlying() if slippage is exceeded", async () => {
      await yieldToken.setSlippage(1000);
      await expect(alchemist.depositUnderlying(yieldToken.address, depositAmount, wallet.address, depositAmount)).revertedWith("SlippageExceeded(90000000000000000000, 100000000000000000000)")
    })

    it("reverts on withdrawUnderlying() if slippage is exceeded", async () => {
      await alchemist.depositUnderlying(yieldToken.address, depositAmount, wallet.address, depositAmount);
      await yieldToken.setSlippage(1000);
      await expect(alchemist.withdrawUnderlying(yieldToken.address, depositAmount, wallet.address, depositAmount)).revertedWith("SlippageExceeded(90000000000000000000, 100000000000000000000)");
    })

    it("reverts on liquidate() if slippage is exceeded", async () => {
      await alchemist.depositUnderlying(yieldToken.address, depositAmount, wallet.address, depositAmount);
      await alchemist.mint(depositAmount.div(2), wallet.address);
      await yieldToken.setSlippage(1000);
      await expect(alchemist.liquidate(yieldToken.address, depositAmount.div(2), depositAmount.div(2))).revertedWith("SlippageExceeded(45000000000000000000, 50000000000000000000)");
    })

    it("reverts on harvest() if slippage is exceeded", async () => {
      const yieldAmount = parseEther("100")
      await alchemist.depositUnderlying(yieldToken.address, depositAmount, wallet.address, depositAmount);
      await underlyingToken.approve(yieldToken.address, yieldAmount)
      await yieldToken.slurp(yieldAmount)
      await yieldToken.setSlippage(1000);
      await expect(alchemist.connect(admin).harvest(yieldToken.address, depositAmount)).revertedWith("SlippageExceeded(891089108910891000, 100000000000000000000)");
    })
  })

  describe("deposit", () => {
    it("reverts if the recipient is the 0 address", async () => {
      await expect(
        alchemist.deposit(
          yieldToken.address,
          parseUnits("100", "ether"),
          "0x0000000000000000000000000000000000000000"
        )
      ).revertedWith("IllegalArgument()");
    });

    it("transfers tokens from the sender", async () => {
      const depositAmount = parseUnits("500", "ether");

      const startingBalance = await yieldToken.balanceOf(wallet.address);

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const endingBalance = await yieldToken.balanceOf(wallet.address);
      const transferred = startingBalance.sub(endingBalance);

      expect(transferred).equals(depositAmount);
    });

    it("issues shares to the recipient", async () => {
      const depositAmount = parseUnits("500", "ether");

      const { shares: startingShares } = await alchemist.positions(
        wallet.address,
        yieldToken.address
      );

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const { shares: endingShares } = await alchemist.positions(
        wallet.address,
        yieldToken.address
      );
      const issued = endingShares.sub(startingShares);

      expect(issued).equals(depositAmount);
    });

    it("issues shares to the recipient (after a successful harvest)", async () => {
      const depositAmount = parseUnits("500", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const profit = parseEther("100");
      await underlyingToken.approve(yieldToken.address, profit);
      await yieldToken.slurp(profit);

      const totalSupply = await yieldToken.totalSupply();
      const minAmtOut = profit.mul(depositAmount).div(totalSupply).mul(1).div(10000); // 1bps slippage allowed

      await alchemist.connect(admin).harvest(yieldToken.address, minAmtOut);

      const price = await alchemist.getYieldTokensPerShare(yieldToken.address);

      const { shares: startingShares } = await alchemist.positions(
        wallet.address,
        yieldToken.address
      );

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const { shares: endingShares } = await alchemist.positions(
        wallet.address,
        yieldToken.address
      );
      const issued = endingShares.sub(startingShares);

      expect(issued).closeTo(depositAmount.mul(parseEther("1")).div(price), 10);
    });

    it("adds the token to the accounts deposited tokens", async () => {
      const depositAmount = parseUnits("500", "ether");

      const { depositedTokens: startingDepositedTokens } =
        await alchemist.accounts(wallet.address);
      expect(startingDepositedTokens).does.not.include(yieldToken.address);

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const { depositedTokens } = await alchemist.accounts(wallet.address);

      expect(depositedTokens).includes(yieldToken.address);
    });

    it("reverts if maximum loss is exceeded", async () => {
      const firstDepositAmount = parseUnits("500", "ether");
      const secondDepositAmount = parseUnits("500", "ether");
      const loss = parseUnits("2", "ether");

      await yieldToken.approve(alchemist.address, firstDepositAmount);
      await alchemist.deposit(
        yieldToken.address,
        firstDepositAmount,
        wallet.address
      );

      await yieldToken.siphon(loss);

      await yieldToken.approve(alchemist.address, secondDepositAmount);
      await expect(
        alchemist.deposit(
          yieldToken.address,
          secondDepositAmount,
          wallet.address
        )
      ).revertedWith('LossExceeded("' + yieldToken.address + '", 2, 1)');
    });

    it("reverts if not a supported yield token", async () => {
      const depositAmount = parseUnits("500", "ether");

      await underlyingToken.approve(alchemist.address, depositAmount);
      await expect(
        alchemist.deposit(
          underlyingToken.address,
          depositAmount,
          wallet.address
        )
      ).revertedWith('UnsupportedToken("' + underlyingToken.address + '")');
    });

    it("emits a Deposit event", async () => {
      const depositAmount = parseUnits("500", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await expect(
        alchemist.deposit(yieldToken.address, depositAmount, wallet.address)
      )
        .to.emit(alchemist, "Deposit")
        .withArgs(
          wallet.address,
          yieldToken.address,
          depositAmount,
          wallet.address
        );
    });

    it("handles multiple user deposits", async () => {
      await underlyingToken.mint(
        other.address,
        BigNumber.from(10).pow(18).mul(10000)
      );
      await underlyingToken
        .connect(other)
        .approve(yieldToken.address, BigNumber.from(10).pow(18).mul(10000));
      await yieldToken
        .connect(other)
        .mint(BigNumber.from(10).pow(18).mul(10000), other.address);

      const depositAmount1 = parseUnits("500", "ether");
      const depositAmount2 = parseUnits("600", "ether");

      const { shares: startingShares1 } = await alchemist.positions(
        wallet.address,
        yieldToken.address
      );
      const { shares: startingShares2 } = await alchemist.positions(
        other.address,
        yieldToken.address
      );

      await yieldToken
        .connect(wallet)
        .approve(alchemist.address, depositAmount1);
      await alchemist
        .connect(wallet)
        .deposit(yieldToken.address, depositAmount1, wallet.address);

      const profit = parseUnits("10", "ether");
      await underlyingToken.approve(yieldToken.address, profit);
      await yieldToken.slurp(profit);
      const totalSupply = await yieldToken.totalSupply();
      const minAmtOut = profit.mul(depositAmount1).div(totalSupply).mul(1).div(10000); // 1bps slippage allowed
      await alchemist.connect(admin).harvest(yieldToken.address, minAmtOut);

      const { shares: endingShares1 } = await alchemist.positions(
        wallet.address,
        yieldToken.address
      );

      const tokenData = await alchemist.getYieldTokenParameters(
        yieldToken.address
      );
      const expectedIssued2 = depositAmount2
        .mul(tokenData.totalShares)
        .div(tokenData.activeBalance);

      await yieldToken
        .connect(other)
        .approve(alchemist.address, depositAmount2);
      await alchemist
        .connect(other)
        .deposit(yieldToken.address, depositAmount2, other.address);

      const { shares: endingShares2 } = await alchemist.positions(
        other.address,
        yieldToken.address
      );

      const issued1 = endingShares1.sub(startingShares1);
      const issued2 = endingShares2.sub(startingShares2);

      expect(issued1).equals(depositAmount1);
      expect(issued2).equals(expectedIssued2);
    });
  });

  describe("depositUnderlying", () => {
    it("reverts if the recipient is the 0 address", async () => {
      await expect(
        alchemist.depositUnderlying(
          yieldToken.address,
          parseUnits("100", "ether"),
          "0x0000000000000000000000000000000000000000",
          parseUnits("100", "ether")
        )
      ).revertedWith("IllegalArgument()");
    });

    it("transfers tokens from the sender", async () => {
      const depositAmount = parseUnits("500", "ether");

      const startingBalance = await underlyingToken.balanceOf(wallet.address);

      await underlyingToken.approve(alchemist.address, depositAmount);
      await alchemist.depositUnderlying(
        yieldToken.address,
        depositAmount,
        wallet.address,
        depositAmount
      );

      const endingBalance = await underlyingToken.balanceOf(wallet.address);
      const transferred = startingBalance.sub(endingBalance);

      expect(transferred).equals(depositAmount);
    });

    it("issues shares to the recipient", async () => {
      const depositAmount = parseUnits("500", "ether");

      const { shares: startingShares } = await alchemist.positions(
        wallet.address,
        yieldToken.address
      );

      await underlyingToken.approve(alchemist.address, depositAmount);
      await alchemist.depositUnderlying(
        yieldToken.address,
        depositAmount,
        wallet.address,
        depositAmount
      );

      const { shares: endingShares } = await alchemist.positions(
        wallet.address,
        yieldToken.address
      );
      const issued = endingShares.sub(startingShares);

      expect(issued).equals(depositAmount);
    });

    it("issues shares to the recipient (after a successful harvest)", async () => {
      const depositAmount = parseUnits("500", "ether");

      await underlyingToken.approve(alchemist.address, depositAmount);
      const pps = await yieldToken.price();
      await alchemist.depositUnderlying(
        yieldToken.address,
        depositAmount,
        wallet.address,
        depositAmount.mul(parseEther("1")).div(pps)
      );

      const { shares: startingShares } = await alchemist.positions(
        wallet.address,
        yieldToken.address
      );
      
      const profit = parseEther("100");
      await underlyingToken.approve(yieldToken.address, profit);
      await yieldToken.slurp(profit);
      
      const totalSupply = await yieldToken.totalSupply();
      const yTokensPerShare = await alchemist.getYieldTokensPerShare(yieldToken.address);
      const minAmtOut = profit.mul(startingShares.mul(yTokensPerShare).div(parseEther("1"))).div(totalSupply).mul(1).div(10000); // 1bps slippage allowed
      await alchemist.connect(admin).harvest(yieldToken.address, minAmtOut);

      const price = await alchemist.getUnderlyingTokensPerShare(
        yieldToken.address
      );
      const expectedIssued = depositAmount.mul(parseEther("1")).div(price);
      const pps2 = await yieldToken.price();
      await underlyingToken.approve(alchemist.address, depositAmount);
      await alchemist.depositUnderlying(
        yieldToken.address,
        depositAmount,
        wallet.address,
        depositAmount.mul(parseEther("1")).div(pps2).div(10000)
      );

      const { shares: endingShares } = await alchemist.positions(
        wallet.address,
        yieldToken.address
      );
      const issued = endingShares.sub(startingShares);

      expect(issued).closeTo(expectedIssued, 1000);
    });

    it("reverts if maximum loss is exceeded", async () => {
      const firstDepositAmount = parseUnits("500", "ether");
      const secondDepositAmount = parseUnits("500", "ether");
      const loss = parseUnits("2", "ether");

      await yieldToken.approve(alchemist.address, firstDepositAmount);
      await alchemist.deposit(
        yieldToken.address,
        firstDepositAmount,
        wallet.address
      );

      await yieldToken.siphon(loss);

      await underlyingToken.approve(alchemist.address, secondDepositAmount);
      await expect(
        alchemist.depositUnderlying(
          yieldToken.address,
          secondDepositAmount,
          wallet.address,
          secondDepositAmount
        )
      ).revertedWith('LossExceeded("' + yieldToken.address + '", 2, 1)');
    });

    it("reverts if not a supported yield token", async () => {
      const depositAmount = parseUnits("500", "ether");

      await underlyingToken.approve(alchemist.address, depositAmount);
      await expect(
        alchemist.depositUnderlying(
          underlyingToken.address,
          depositAmount,
          wallet.address,
          depositAmount
        )
      ).revertedWith('UnsupportedToken("' + underlyingToken.address + '")');
    });

    it("emits a Deposit event", async () => {
      const depositAmount = parseUnits("500", "ether");

      await underlyingToken.approve(alchemist.address, depositAmount);
      await expect(
        alchemist.depositUnderlying(
          yieldToken.address,
          depositAmount,
          wallet.address,
          depositAmount
        )
      ).emit(alchemist, "Deposit");
    });
  });

  describe("withdraw", () => {
    it("reverts if the recipient is the 0 address", async () => {
      await expect(
        alchemist.deposit(
          yieldToken.address,
          parseUnits("100", "ether"),
          "0x0000000000000000000000000000000000000000"
        )
      ).revertedWith("IllegalArgument()");
    });

    it("transfers tokens to the recipient", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const startingBalance = await yieldToken.balanceOf(wallet.address);

      await alchemist.withdraw(
        yieldToken.address,
        withdrawAmount,
        wallet.address
      );

      const endingBalance = await yieldToken.balanceOf(wallet.address);
      const transferred = endingBalance.sub(startingBalance);

      expect(transferred).equals(withdrawAmount);
    });

    it("burns shares from the sender", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const { shares: startingShares } = await alchemist.positions(
        wallet.address,
        yieldToken.address
      );

      await alchemist.withdraw(
        yieldToken.address,
        withdrawAmount,
        wallet.address
      );

      const { shares: endingShares } = await alchemist.positions(
        wallet.address,
        yieldToken.address
      );
      const burned = startingShares.sub(endingShares);

      expect(burned).equals(withdrawAmount);
    });

    it("preharvests any tokens held by the target account", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");
      const profit = parseUnits("100", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const { harvestableBalance: startingBuffer } =
        await alchemist.getYieldTokenParameters(yieldToken.address);

      await underlyingToken.approve(yieldToken.address, profit);
      await yieldToken.slurp(profit);

      await alchemist.withdraw(
        yieldToken.address,
        withdrawAmount,
        wallet.address
      );

      const { harvestableBalance: endingBuffer, expectedValue: endExpect } =
        await alchemist.getYieldTokenParameters(yieldToken.address);
      const buffered = endingBuffer.sub(startingBuffer);
      const price = await yieldToken.price();
      const alchProfit = profit.div(20); // 10000 total underlying held by yield token, 500 by alchemist
      expect(buffered).equals(alchProfit.mul(parseEther("1")).div(price));
    });

    it("removes the token from the accounts deposit tokens when balance goes to 0", async () => {
      const depositAmount = parseUnits("500", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const { depositedTokens: startingDepositedTokens } =
        await alchemist.accounts(wallet.address);
      expect(startingDepositedTokens).includes(yieldToken.address);

      await alchemist.withdraw(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const { depositedTokens } = await alchemist.accounts(wallet.address);
      expect(depositedTokens).does.not.include(yieldToken.address);
    });

    it("reverts when undercollateralized", async () => {
      const depositAmount = parseUnits("500", "ether");
      const mintAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await alchemist.mint(mintAmount, wallet.address);

      await expect(
        alchemist.withdraw(yieldToken.address, 1, wallet.address)
      ).revertedWith("Undercollateralized()");
    });

    it("reverts if not a supported yield token", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await underlyingToken.approve(alchemist.address, withdrawAmount);
      await expect(
        alchemist.withdraw(
          underlyingToken.address,
          withdrawAmount,
          wallet.address
        )
      ).revertedWith('UnsupportedToken("' + underlyingToken.address + '")');
    });

    it("emits a Withdraw event", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await expect(
        alchemist.withdraw(yieldToken.address, withdrawAmount, wallet.address)
      )
        .to.emit(alchemist, "Withdraw")
        .withArgs(
          wallet.address,
          yieldToken.address,
          withdrawAmount,
          wallet.address
        );
    });
  });

  describe("withdrawUnderlying", () => {
    it("reverts if the recipient is the 0 address", async () => {
      await expect(
        alchemist.deposit(
          yieldToken.address,
          parseUnits("100", "ether"),
          "0x0000000000000000000000000000000000000000"
        )
      ).revertedWith("IllegalArgument()");
    });

    it("transfers tokens to the recipient", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const startingBalance = await underlyingToken.balanceOf(wallet.address);

      await alchemist.withdrawUnderlying(
        yieldToken.address,
        withdrawAmount,
        wallet.address,
        withdrawAmount
      );

      const endingBalance = await underlyingToken.balanceOf(wallet.address);
      const transferred = endingBalance.sub(startingBalance);

      expect(transferred).equals(withdrawAmount);
    });

    it("burns shares from the sender", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const { shares: startingShares } = await alchemist.positions(
        wallet.address,
        yieldToken.address
      );

      await alchemist.withdrawUnderlying(
        yieldToken.address,
        withdrawAmount,
        wallet.address,
        withdrawAmount
      );

      const { shares: endingShares } = await alchemist.positions(
        wallet.address,
        yieldToken.address
      );
      const burned = startingShares.sub(endingShares);

      expect(burned).equals(withdrawAmount);
    });

    it("preharvests any tokens held by the target account", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");
      const profit = parseUnits("100", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const { harvestableBalance: startingBuffer } =
        await alchemist.getYieldTokenParameters(yieldToken.address);

      await underlyingToken.approve(yieldToken.address, profit);
      await yieldToken.slurp(profit);

      await alchemist.withdrawUnderlying(
        yieldToken.address,
        withdrawAmount,
        wallet.address,
        withdrawAmount.mul(1).div(10000)
      );

      const { harvestableBalance: endingBuffer, expectedValue: endExpect } =
        await alchemist.getYieldTokenParameters(yieldToken.address);
      const buffered = endingBuffer.sub(startingBuffer);
      const price = await yieldToken.price();
      const alchProfit = profit.div(20); // 10000 total underlying held by yield token, 500 by alchemist
      expect(buffered).equals(alchProfit.mul(parseEther("1")).div(price));
    });

    it("removes the token from the accounts deposit tokens when balance goes to 0", async () => {
      const depositAmount = parseUnits("500", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const { depositedTokens: startingDepositedTokens } =
        await alchemist.accounts(wallet.address);
      expect(startingDepositedTokens).includes(yieldToken.address);

      await alchemist.withdraw(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const { depositedTokens } = await alchemist.accounts(wallet.address);
      expect(depositedTokens).does.not.include(yieldToken.address);
    });

    it("reverts when undercollateralized", async () => {
      const depositAmount = parseUnits("500", "ether");
      const mintAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await alchemist.mint(mintAmount, wallet.address);

      await expect(
        alchemist.withdrawUnderlying(yieldToken.address, 1, wallet.address, 1)
      ).revertedWith("Undercollateralized()");
    });

    it("reverts if not a supported yield token", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await underlyingToken.approve(alchemist.address, withdrawAmount);
      await expect(
        alchemist.withdrawUnderlying(
          underlyingToken.address,
          withdrawAmount,
          wallet.address,
          withdrawAmount
        )
      ).revertedWith('UnsupportedToken("' + underlyingToken.address + '")');
    });

    it("emits a Withdraw event", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await expect(
        alchemist.withdrawUnderlying(
          yieldToken.address,
          withdrawAmount,
          wallet.address,
          withdrawAmount
        )
      ).emit(alchemist, "Withdraw");
    });

    it("reverts if maximum loss is exceeded", async () => {
      const firstDepositAmount = parseUnits("500", "ether");
      const secondDepositAmount = parseUnits("500", "ether");
      const loss = parseUnits("2", "ether");

      await yieldToken.approve(alchemist.address, firstDepositAmount);
      await alchemist.deposit(
        yieldToken.address,
        firstDepositAmount,
        wallet.address
      );

      await yieldToken.siphon(loss);

      await yieldToken.approve(alchemist.address, secondDepositAmount);
      await expect(
        alchemist.withdrawUnderlying(
          yieldToken.address,
          secondDepositAmount,
          wallet.address,
          secondDepositAmount
        )
      ).revertedWith('LossExceeded("' + yieldToken.address + '", 2, 1)');
    });
  });

  describe("withdrawFrom", () => {
    it("reverts if the recipient is the 0 address", async () => {
      await expect(
        alchemist.deposit(
          yieldToken.address,
          parseUnits("100", "ether"),
          "0x0000000000000000000000000000000000000000"
        )
      ).revertedWith("IllegalArgument()");
    });

    it("transfers tokens to the recipient", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const startingBalance = await yieldToken.balanceOf(other.address);

      await alchemist.approveWithdraw(
        other.address,
        yieldToken.address,
        withdrawAmount
      );
      await alchemist
        .connect(other)
        .withdrawFrom(
          wallet.address,
          yieldToken.address,
          withdrawAmount,
          other.address
        );

      const endingBalance = await yieldToken.balanceOf(other.address);
      const transferred = endingBalance.sub(startingBalance);

      expect(transferred).equals(withdrawAmount);
    });

    it("burns shares from the owner", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const { shares: startingShares } = await alchemist.positions(
        wallet.address,
        yieldToken.address
      );

      await alchemist.approveWithdraw(
        other.address,
        yieldToken.address,
        withdrawAmount
      );
      await alchemist
        .connect(other)
        .withdrawFrom(
          wallet.address,
          yieldToken.address,
          withdrawAmount,
          other.address
        );

      const { shares: endingShares } = await alchemist.positions(
        wallet.address,
        yieldToken.address
      );
      const burned = startingShares.sub(endingShares);

      expect(burned).equals(withdrawAmount);
    });

    it("preharvests any tokens held by the target account", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");
      const profit = parseUnits("100", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const { harvestableBalance: startingBuffer } =
        await alchemist.getYieldTokenParameters(yieldToken.address);

      await underlyingToken.approve(yieldToken.address, profit);
      await yieldToken.slurp(profit);

      await alchemist.approveWithdraw(
        other.address,
        yieldToken.address,
        withdrawAmount
      );
      await alchemist
        .connect(other)
        .withdrawFrom(
          wallet.address,
          yieldToken.address,
          withdrawAmount,
          other.address
        );

      const { harvestableBalance: endingBuffer, expectedValue: endExpect } =
        await alchemist.getYieldTokenParameters(yieldToken.address);
      const buffered = endingBuffer.sub(startingBuffer);
      const price = await yieldToken.price();
      const alchProfit = profit.div(20); // 10000 total underlying held by yield token, 500 by alchemist
      expect(buffered).equals(alchProfit.mul(parseEther("1")).div(price));
    });

    it("removes the token from the accounts deposit tokens when balance goes to 0", async () => {
      const depositAmount = parseUnits("500", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const { depositedTokens: startingDepositedTokens } =
        await alchemist.accounts(wallet.address);
      expect(startingDepositedTokens).includes(yieldToken.address);

      await alchemist.approveWithdraw(
        other.address,
        yieldToken.address,
        depositAmount
      );
      await alchemist
        .connect(other)
        .withdrawFrom(
          wallet.address,
          yieldToken.address,
          depositAmount,
          other.address
        );

      const { depositedTokens } = await alchemist.accounts(wallet.address);
      expect(depositedTokens).does.not.include(yieldToken.address);
    });

    it("reverts when undercollateralized", async () => {
      const depositAmount = parseUnits("500", "ether");
      const mintAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await alchemist.mint(mintAmount, wallet.address);

      await alchemist.approveWithdraw(other.address, yieldToken.address, 1);
      await expect(
        alchemist
          .connect(other)
          .withdrawFrom(wallet.address, yieldToken.address, 1, other.address)
      ).revertedWith("Undercollateralized()");
    });

    it("reverts if not a supported yield token", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await alchemist.approveWithdraw(
        other.address,
        yieldToken.address,
        withdrawAmount
      );
      await underlyingToken.approve(alchemist.address, withdrawAmount);
      await expect(
        alchemist
          .connect(other)
          .withdrawFrom(
            wallet.address,
            underlyingToken.address,
            withdrawAmount,
            other.address
          )
      ).revertedWith('UnsupportedToken("' + underlyingToken.address + '")');
    });

    it("reverts if withdraw amount > approved amount", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await alchemist.approveWithdraw(
        other.address,
        yieldToken.address,
        withdrawAmount.div(2)
      );
      await expect(
        alchemist
          .connect(other)
          .withdrawFrom(
            wallet.address,
            yieldToken.address,
            withdrawAmount,
            other.address
          )
      ).revertedWith(
        "panic code 0x11 (Arithmetic operation underflowed or overflowed outside of an unchecked block)"
      );
    });

    it("emits a Withdraw event", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await alchemist.approveWithdraw(
        other.address,
        yieldToken.address,
        withdrawAmount
      );
      await expect(
        alchemist
          .connect(other)
          .withdrawFrom(
            wallet.address,
            yieldToken.address,
            withdrawAmount,
            other.address
          )
      )
        .to.emit(alchemist, "Withdraw")
        .withArgs(
          wallet.address,
          yieldToken.address,
          withdrawAmount,
          other.address
        );
    });
  });

  describe("withdrawUnderlyingFrom", () => {
    it("reverts if the recipient is the 0 address", async () => {
      await expect(
        alchemist.deposit(
          yieldToken.address,
          parseUnits("100", "ether"),
          "0x0000000000000000000000000000000000000000"
        )
      ).revertedWith("IllegalArgument()");
    });

    it("transfers tokens to the recipient", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const startingBalance = await underlyingToken.balanceOf(other.address);

      await alchemist.approveWithdraw(
        other.address,
        yieldToken.address,
        withdrawAmount
      );
      await alchemist
        .connect(other)
        .withdrawUnderlyingFrom(
          wallet.address,
          yieldToken.address,
          withdrawAmount,
          other.address,
          withdrawAmount
        );

      const endingBalance = await underlyingToken.balanceOf(other.address);
      const transferred = endingBalance.sub(startingBalance);

      expect(transferred).equals(withdrawAmount);
    });

    it("burns shares from the owner", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const { shares: startingShares } = await alchemist.positions(
        wallet.address,
        yieldToken.address
      );

      await alchemist.approveWithdraw(
        other.address,
        yieldToken.address,
        withdrawAmount
      );
      await alchemist
        .connect(other)
        .withdrawUnderlyingFrom(
          wallet.address,
          yieldToken.address,
          withdrawAmount,
          other.address,
          withdrawAmount
        );

      const { shares: endingShares } = await alchemist.positions(
        wallet.address,
        yieldToken.address
      );
      const burned = startingShares.sub(endingShares);

      expect(burned).equals(withdrawAmount);
    });

    it("preharvests any tokens held by the target account", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");
      const profit = parseUnits("100", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const { harvestableBalance: startingBuffer } =
        await alchemist.getYieldTokenParameters(yieldToken.address);

      await underlyingToken.approve(yieldToken.address, profit);
      await yieldToken.slurp(profit);

      await alchemist.approveWithdraw(
        other.address,
        yieldToken.address,
        withdrawAmount
      );
      await alchemist
        .connect(other)
        .withdrawUnderlyingFrom(
          wallet.address,
          yieldToken.address,
          withdrawAmount,
          other.address,
          withdrawAmount.mul(1).div(10000)
        );

      const { harvestableBalance: endingBuffer } =
        await alchemist.getYieldTokenParameters(yieldToken.address);
      const buffered = endingBuffer.sub(startingBuffer);
      const price = await yieldToken.price();
      const alchProfit = profit.div(20); // 10000 total underlying held by yield token, 500 by alchemist
      expect(buffered).equals(alchProfit.mul(parseEther("1")).div(price));
    });

    it("removes the token from the accounts deposit tokens when balance goes to 0", async () => {
      const depositAmount = parseUnits("500", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const { depositedTokens: startingDepositedTokens } =
        await alchemist.accounts(wallet.address);
      expect(startingDepositedTokens).includes(yieldToken.address);

      await alchemist.approveWithdraw(
        other.address,
        yieldToken.address,
        depositAmount
      );
      await alchemist
        .connect(other)
        .withdrawUnderlyingFrom(
          wallet.address,
          yieldToken.address,
          depositAmount,
          other.address,
          depositAmount
        );

      const { depositedTokens } = await alchemist.accounts(wallet.address);
      expect(depositedTokens).does.not.include(yieldToken.address);
    });

    it("reverts when undercollateralized", async () => {
      const depositAmount = parseUnits("500", "ether");
      const mintAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await alchemist.mint(mintAmount, wallet.address);

      await alchemist.approveWithdraw(other.address, yieldToken.address, 1);
      await expect(
        alchemist
          .connect(other)
          .withdrawUnderlyingFrom(
            wallet.address,
            yieldToken.address,
            1,
            other.address,
            1
          )
      ).revertedWith("Undercollateralized()");
    });

    it("reverts if withdraw amount > approved amount", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await alchemist.approveWithdraw(
        other.address,
        yieldToken.address,
        withdrawAmount.div(2)
      );
      await expect(
        alchemist
          .connect(other)
          .withdrawUnderlyingFrom(
            wallet.address,
            yieldToken.address,
            withdrawAmount,
            other.address,
            withdrawAmount
          )
      ).revertedWith(
        "panic code 0x11 (Arithmetic operation underflowed or overflowed outside of an unchecked block)"
      );
    });

    it("reverts if not a supported yield token", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await underlyingToken.approve(alchemist.address, withdrawAmount);
      await alchemist.approveWithdraw(
        other.address,
        yieldToken.address,
        withdrawAmount
      );
      await expect(
        alchemist
          .connect(other)
          .withdrawUnderlyingFrom(
            wallet.address,
            underlyingToken.address,
            withdrawAmount,
            wallet.address,
            withdrawAmount
          )
      ).revertedWith('UnsupportedToken("' + underlyingToken.address + '")');
    });

    it("emits a Withdraw event", async () => {
      const depositAmount = parseUnits("500", "ether");
      const withdrawAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await alchemist.approveWithdraw(
        other.address,
        yieldToken.address,
        withdrawAmount
      );
      await expect(
        alchemist
          .connect(other)
          .withdrawUnderlyingFrom(
            wallet.address,
            yieldToken.address,
            withdrawAmount,
            wallet.address,
            withdrawAmount
          )
      ).emit(alchemist, "Withdraw");
    });
  });

  describe("mint", () => {
    it("reverts if the recipient is the 0 address", async () => {
      await expect(
        alchemist.deposit(
          yieldToken.address,
          parseUnits("100", "ether"),
          "0x0000000000000000000000000000000000000000"
        )
      ).revertedWith("IllegalArgument()");
    });

    it("increases the debt of the sender", async () => {
      const depositAmount = parseUnits("500", "ether");
      const mintAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const { debt: startingDebt } = await alchemist.accounts(wallet.address);

      await alchemist.mint(mintAmount, wallet.address);

      const { debt: endingDebt } = await alchemist.accounts(wallet.address);
      const delta = endingDebt.sub(startingDebt);

      expect(delta).equals(mintAmount);
    });

    it("mints debt tokens to the recipient", async () => {
      const depositAmount = parseUnits("500", "ether");
      const mintAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const startingBalance = await debtToken.balanceOf(wallet.address);

      await alchemist.mint(mintAmount, wallet.address);

      const endingBalance = await debtToken.balanceOf(wallet.address);
      const minted = endingBalance.sub(startingBalance);

      expect(minted).equals(mintAmount);
    });

    it("reverts when undercollateralized", async () => {
      const depositAmount = parseUnits("500", "ether");
      const mintAmount = parseUnits("250.000000000000000001", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await expect(alchemist.mint(mintAmount, wallet.address)).revertedWith(
        "Undercollateralized()"
      );
    });

    it("emits a Mint event", async () => {
      const depositAmount = parseUnits("500", "ether");
      const mintAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await expect(alchemist.mint(mintAmount, wallet.address))
        .to.emit(alchemist, "Mint")
        .withArgs(wallet.address, mintAmount, wallet.address);
    });

    it("mints on 2 collateral types", async () => {
      const depositAmount18 = parseUnits("500", "ether");
      const depositAmount6 = parseUnits("500", "mwei");
      const mintAmount = parseUnits("500", "ether");

      await yieldToken.approve(alchemist.address, depositAmount18);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount18,
        wallet.address
      );

      await yieldToken6.approve(alchemist.address, depositAmount6);
      await alchemist.deposit(
        yieldToken6.address,
        depositAmount6,
        wallet.address
      );

      await expect(alchemist.mint(mintAmount, wallet.address))
        .to.emit(alchemist, "Mint")
        .withArgs(wallet.address, mintAmount, wallet.address);
    });

    it("mints on 2 collateral types after a successful harvest", async () => {
      const depositAmount18 = parseUnits("500", "ether");
      const depositAmount6 = parseUnits("500", "mwei");
      const mintAmount = parseUnits("500", "ether");

      await yieldToken.approve(alchemist.address, depositAmount18);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount18,
        wallet.address
      );

      await yieldToken6.approve(alchemist.address, depositAmount6);
      await alchemist.deposit(
        yieldToken6.address,
        depositAmount6,
        wallet.address
      );

      const profit18 = parseUnits("100", "ether");
      await underlyingToken.approve(yieldToken.address, profit18);
      await yieldToken.slurp(profit18);
      const profit6 = parseUnits("50", "mwei");
      await underlyingToken6.approve(yieldToken6.address, profit6);
      await yieldToken6.slurp(profit6);

      const totalSupply18 = await yieldToken.totalSupply();
      const minAmtOut18 = profit18.mul(depositAmount18).div(totalSupply18).mul(1).div(10000); // 1bps slippage allowed
      const totalSupply6 = await yieldToken.totalSupply();
      const minAmtOut6 = profit6.mul(depositAmount6).div(totalSupply6).mul(1).div(10000); // 1bps slippage allowed

      await alchemist.connect(admin).harvest(yieldToken.address, minAmtOut18);
      await alchemist.connect(admin).harvest(yieldToken6.address, minAmtOut6);

      await alchemist.poke(wallet.address);
      const acctBefore = await alchemist.accounts(wallet.address);
      const balBefore = await debtToken.balanceOf(wallet.address);
      await alchemist.mint(mintAmount, wallet.address);
      const acctAfter = await alchemist.accounts(wallet.address);
      const balAfter = await debtToken.balanceOf(wallet.address);
      expect(balAfter.sub(balBefore)).equal(mintAmount);
      expect(acctAfter.debt.sub(acctBefore.debt)).equal(mintAmount);
    });

    it("preharvests the tokens held by the minter", async () => {
      await yieldToken6
        .connect(other)
        .mint(parseUnits("10000", "mwei"), other.address);

      const depositAmount18 = parseUnits("500", "ether");
      const depositAmount6 = parseUnits("500", "mwei");
      const mintAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount18);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount18,
        wallet.address
      );

      await yieldToken6
        .connect(other)
        .approve(alchemist.address, depositAmount6);
      await alchemist
        .connect(other)
        .deposit(yieldToken6.address, depositAmount6, other.address);

      const profit18 = parseUnits("100", "ether");
      await underlyingToken.approve(yieldToken.address, profit18);
      await yieldToken.slurp(profit18);
      const profit6 = parseUnits("50", "mwei");
      await underlyingToken6.approve(yieldToken6.address, profit6);
      await yieldToken6.slurp(profit6);

      const tokenBefore = await alchemist.getYieldTokenParameters(
        yieldToken.address
      );
      const tokenBefore6 = await alchemist.getYieldTokenParameters(
        yieldToken6.address
      );
      await alchemist.mint(mintAmount, wallet.address);
      const tokenAfter = await alchemist.getYieldTokenParameters(
        yieldToken.address
      );
      const tokenAfter6 = await alchemist.getYieldTokenParameters(
        yieldToken6.address
      );
      const price = await yieldToken.price();
      const alchProfit = profit18.div(20); // 10000 total underlying held by yield token, 500 by alchemist
      expect(
        tokenAfter.harvestableBalance.sub(tokenBefore.harvestableBalance)
      ).equal(alchProfit.mul(parseEther("1")).div(price));
      expect(
        tokenAfter6.harvestableBalance.sub(tokenBefore6.harvestableBalance)
      ).equal(0);
    });
  });

  describe("mintFrom", () => {
    it("reverts if the recipient is the 0 address", async () => {
      await expect(
        alchemist.deposit(
          yieldToken.address,
          parseUnits("100", "ether"),
          "0x0000000000000000000000000000000000000000"
        )
      ).revertedWith("IllegalArgument()");
    });

    it("decreases the mint allowance of spender", async () => {
      const depositAmount = parseUnits("500", "ether");
      const approveAmount = parseUnits("500", "ether");
      const mintAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await alchemist.approveMint(other.address, approveAmount);
      await alchemist
        .connect(other)
        .mintFrom(wallet.address, mintAmount, other.address);

      const allowance = await alchemist.mintAllowance(
        wallet.address,
        other.address
      );

      expect(allowance).equals(approveAmount.sub(mintAmount));
    });

    it("increases the debt of the sender", async () => {
      const depositAmount = parseUnits("500", "ether");
      const approveAmount = parseUnits("500", "ether");
      const mintAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const { debt: startingDebt } = await alchemist.accounts(wallet.address);

      await alchemist.approveMint(other.address, approveAmount);
      await alchemist
        .connect(other)
        .mintFrom(wallet.address, mintAmount, other.address);

      const { debt: endingDebt } = await alchemist.accounts(wallet.address);
      const delta = endingDebt.sub(startingDebt);

      expect(delta).equals(mintAmount);
    });

    it("mints debt tokens to the recipient", async () => {
      const depositAmount = parseUnits("500", "ether");
      const approveAmount = parseUnits("500", "ether");
      const mintAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      const startingBalance = await debtToken.balanceOf(other.address);

      await alchemist.approveMint(other.address, approveAmount);
      await alchemist
        .connect(other)
        .mintFrom(wallet.address, mintAmount, other.address);

      const endingBalance = await debtToken.balanceOf(other.address);
      const minted = endingBalance.sub(startingBalance);

      expect(minted).equals(mintAmount);
    });

    it("reverts when undercollateralized", async () => {
      const depositAmount = parseUnits("500", "ether");
      const approveAmount = parseUnits("500", "ether");
      const mintAmount = parseUnits("250.000000000000000001", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await alchemist.approveMint(other.address, approveAmount);
      await expect(
        alchemist
          .connect(other)
          .mintFrom(wallet.address, mintAmount, other.address)
      ).revertedWith("Undercollateralized()");
    });

    it("emits a Mint event", async () => {
      const depositAmount = parseUnits("500", "ether");
      const approveAmount = parseUnits("500", "ether");
      const mintAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await alchemist.approveMint(other.address, approveAmount);

      await expect(
        alchemist
          .connect(other)
          .mintFrom(wallet.address, mintAmount, other.address)
      )
        .to.emit(alchemist, "Mint")
        .withArgs(wallet.address, mintAmount, other.address);
    });

    it("mints on 2 collateral types", async () => {
      const approveAmount = parseUnits("500", "ether");
      const depositAmount18 = parseUnits("500", "ether");
      const depositAmount6 = parseUnits("500", "mwei");
      const mintAmount = parseUnits("500", "ether");

      await yieldToken.approve(alchemist.address, depositAmount18);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount18,
        wallet.address
      );

      await yieldToken6.approve(alchemist.address, depositAmount6);
      await alchemist.deposit(
        yieldToken6.address,
        depositAmount6,
        wallet.address
      );

      await alchemist.approveMint(other.address, approveAmount);
      await expect(
        alchemist
          .connect(other)
          .mintFrom(wallet.address, mintAmount, other.address)
      )
        .to.emit(alchemist, "Mint")
        .withArgs(wallet.address, mintAmount, other.address);
    });

    it("mints on 2 collateral types after a successful harvest", async () => {
      const approveAmount = parseUnits("500", "ether");
      const depositAmount18 = parseUnits("500", "ether");
      const depositAmount6 = parseUnits("500", "mwei");
      const mintAmount = parseUnits("500", "ether");

      await yieldToken.approve(alchemist.address, depositAmount18);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount18,
        wallet.address
      );

      await yieldToken6.approve(alchemist.address, depositAmount6);
      await alchemist.deposit(
        yieldToken6.address,
        depositAmount6,
        wallet.address
      );

      const profit18 = parseUnits("100", "ether");
      await underlyingToken.approve(yieldToken.address, profit18);
      await yieldToken.slurp(profit18);
      const profit6 = parseUnits("50", "mwei");
      await underlyingToken6.approve(yieldToken6.address, profit6);
      await yieldToken6.slurp(profit6);

      const totalSupply18 = await yieldToken.totalSupply();
      const minAmtOut18 = profit18.mul(depositAmount18).div(totalSupply18).mul(1).div(10000); // 1bps slippage allowed
      const totalSupply6 = await yieldToken.totalSupply();
      const minAmtOut6 = profit6.mul(depositAmount6).div(totalSupply6).mul(1).div(10000); // 1bps slippage allowed

      await alchemist.connect(admin).harvest(yieldToken.address, minAmtOut18);
      await alchemist.connect(admin).harvest(yieldToken6.address, minAmtOut6);

      await alchemist.approveMint(other.address, approveAmount);

      await alchemist.poke(wallet.address);
      const acctBefore = await alchemist.accounts(wallet.address);
      const balBefore = await debtToken.balanceOf(other.address);
      await alchemist
        .connect(other)
        .mintFrom(wallet.address, mintAmount, other.address);
      const acctAfter = await alchemist.accounts(wallet.address);
      const balAfter = await debtToken.balanceOf(other.address);
      expect(balAfter.sub(balBefore)).equal(mintAmount);
      expect(acctAfter.debt.sub(acctBefore.debt)).equal(mintAmount);
    });

    it("preharvests the tokens held by the minter", async () => {
      await yieldToken6
        .connect(other)
        .mint(parseUnits("10000", "mwei"), other.address);

      const approveAmount = parseUnits("500", "ether");
      const depositAmount18 = parseUnits("500", "ether");
      const depositAmount6 = parseUnits("500", "mwei");
      const mintAmount = parseUnits("250", "ether");

      await yieldToken.approve(alchemist.address, depositAmount18);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount18,
        wallet.address
      );

      await yieldToken6
        .connect(other)
        .approve(alchemist.address, depositAmount6);
      await alchemist
        .connect(other)
        .deposit(yieldToken6.address, depositAmount6, other.address);

      const profit18 = parseUnits("100", "ether");
      await underlyingToken.approve(yieldToken.address, profit18);
      await yieldToken.slurp(profit18);
      const profit6 = parseUnits("50", "mwei");
      await underlyingToken6.approve(yieldToken6.address, profit6);
      await yieldToken6.slurp(profit6);

      await alchemist.approveMint(other.address, approveAmount);

      const tokenBefore = await alchemist.getYieldTokenParameters(
        yieldToken.address
      );
      const tokenBefore6 = await alchemist.getYieldTokenParameters(
        yieldToken6.address
      );
      await alchemist
        .connect(other)
        .mintFrom(wallet.address, mintAmount, other.address);
      const tokenAfter = await alchemist.getYieldTokenParameters(
        yieldToken.address
      );
      const tokenAfter6 = await alchemist.getYieldTokenParameters(
        yieldToken6.address
      );
      const price = await yieldToken.price();
      const alchProfit = profit18.div(20); // 10000 total underlying held by yield token, 500 by alchemist
      expect(
        tokenAfter.harvestableBalance.sub(tokenBefore.harvestableBalance)
      ).equal(alchProfit.mul(parseEther("1")).div(price));
      expect(
        tokenAfter6.harvestableBalance.sub(tokenBefore6.harvestableBalance)
      ).equal(0);
    });
  });

  describe("burn", () => {
    const depositAmount = parseUnits("500", "ether");
    const mintAmount = parseUnits("250", "ether");
    const burnAmount = parseUnits("125", "ether");

    beforeEach(async () => {
      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );
      await alchemist.mint(mintAmount, wallet.address);
      await debtToken.approve(alchemist.address, burnAmount);
    });

    it("transfers tokens from the sender", async () => {
      const startingBalance = await debtToken.balanceOf(wallet.address);

      await alchemist.burn(burnAmount, wallet.address);

      const endingBalance = await debtToken.balanceOf(wallet.address);
      const transferred = startingBalance.sub(endingBalance);

      expect(transferred).equals(burnAmount);
    });

    it("decreases the debt of the sender", async () => {
      const { debt: startingDebt } = await alchemist.accounts(wallet.address);

      await alchemist.burn(burnAmount, wallet.address);

      const { debt: endingDebt } = await alchemist.accounts(wallet.address);
      const delta = startingDebt.sub(endingDebt);

      expect(delta).equals(burnAmount);
    });

    it("emits a Burn event", async () => {
      await expect(alchemist.burn(burnAmount, wallet.address))
        .to.emit(alchemist, "Burn")
        .withArgs(wallet.address, burnAmount, wallet.address);
    });

    it("limits burned amount to the current debt", async () => {
      const slurpAmt = parseEther("100");
      await underlyingToken
        .connect(wallet)
        .approve(yieldToken.address, slurpAmt);
      await yieldToken.connect(wallet).slurp(slurpAmt);
      const totalSupply = await yieldToken.totalSupply();
      const minAmtOut = slurpAmt.mul(depositAmount).div(totalSupply).mul(1).div(10000); // 1bps slippage allowed
      await alchemist.connect(admin).harvest(yieldToken.address, minAmtOut);

      const { debt: startingDebt } = await alchemist.accounts(wallet.address);
      await debtToken.approve(alchemist.address, startingDebt.mul(2));
      await alchemist.burn(startingDebt.mul(2), wallet.address);
      const { debt: endingDebt } = await alchemist.accounts(wallet.address);
      expect(endingDebt).equal(0);
    });
    
    it("reverts with an IllegalState error when debt is equal to or less than zero", async () => {
      const slurpAmount = parseEther("5575");
      await underlyingToken
        .connect(wallet)
        .approve(yieldToken.address, slurpAmount);
      await yieldToken.connect(wallet).slurp(slurpAmount);
      const totalSupply = await yieldToken.totalSupply();
      const minAmtOut = slurpAmount.mul(depositAmount).div(totalSupply).mul(1).div(10000); // 1bps slippage allowed
      await alchemist.connect(admin).harvest(yieldToken.address, minAmtOut);
      await alchemist.connect(admin).poke(wallet.address);

      await expect(alchemist.burn(1, wallet.address)).revertedWith(
        `IllegalState()`
      );
    });
  });

  describe("repay", () => {
    const depositAmount = parseUnits("500", "ether");
    const mintAmount = parseUnits("250", "ether");
    const repayAmount = parseUnits("250", "ether");

    beforeEach(async () => {
      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await alchemist.mint(mintAmount, wallet.address);

      await underlyingToken.approve(alchemist.address, repayAmount);
    });

    it("transfers tokens from the sender", async () => {
      const startingBalance = await underlyingToken.balanceOf(wallet.address);

      await alchemist.repay(
        underlyingToken.address,
        repayAmount,
        wallet.address
      );

      const endingBalance = await underlyingToken.balanceOf(wallet.address);
      const transferred = startingBalance.sub(endingBalance);

      expect(transferred).equals(repayAmount);
    });

    it("decreases the debt of the recipient", async () => {
      const { debt: startingDebt } = await alchemist.accounts(wallet.address);

      await alchemist.repay(
        underlyingToken.address,
        repayAmount,
        wallet.address
      );

      const { debt: endingDebt } = await alchemist.accounts(wallet.address);
      const delta = startingDebt.sub(endingDebt);

      expect(delta).equals(repayAmount);
    });

    it("reverts if not a supported underlying token", async () => {
      await expect(
        alchemist.repay(yieldToken.address, repayAmount, wallet.address)
      ).revertedWith('UnsupportedToken("' + yieldToken.address + '")');
    });

    it("reverts if underlying token is disabled", async () => {
      await alchemist
        .connect(admin)
        .setUnderlyingTokenEnabled(underlyingToken.address, false);
      await expect(
        alchemist.repay(underlyingToken.address, repayAmount, wallet.address)
      ).revertedWith('TokenDisabled("' + underlyingToken.address + '")');
    });

    it("emits a Repay event", async () => {
      await expect(
        alchemist.repay(underlyingToken.address, repayAmount, wallet.address)
      )
        .to.emit(alchemist, "Repay")
        .withArgs(
          wallet.address,
          underlyingToken.address,
          repayAmount,
          wallet.address,
          repayAmount
        );
    });

    it("caps repay amount to account debt", async () => {
      const { debt: startingDebt } = await alchemist.accounts(wallet.address);

      await alchemist.repay(
        underlyingToken.address,
        startingDebt.mul(2),
        wallet.address
      );

      const acct = await alchemist.accounts(wallet.address);
      expect(acct.debt).equals(0);
    });

    it("transfers tokens to the transmuter", async () => {
      const startingBalance = await underlyingToken.balanceOf(
        transmuter.address
      );

      await alchemist.repay(
        underlyingToken.address,
        repayAmount,
        wallet.address
      );

      const endingBalance = await underlyingToken.balanceOf(transmuter.address);
      const transferred = endingBalance.sub(startingBalance);

      expect(transferred).equals(repayAmount);
    });
  });

  describe("liquidate", () => {
    const depositAmount = parseUnits("500", "ether");
    const mintAmount = parseUnits("250", "ether");
    const liquidateAmount = parseUnits("125", "ether");

    beforeEach(async () => {
      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await alchemist.mint(mintAmount, wallet.address);
    });

    it("decreases the debt of the sender", async () => {
      const { debt: startingDebt } = await alchemist.accounts(wallet.address);

      await alchemist.liquidate(yieldToken.address, liquidateAmount, liquidateAmount);

      const { debt: endingDebt } = await alchemist.accounts(wallet.address);
      const delta = startingDebt.sub(endingDebt);

      expect(delta).equals(liquidateAmount);
    });

    it("burns shares from the sender", async () => {
      const profit = parseEther("100");
      await underlyingToken.approve(yieldToken.address, profit);
      await yieldToken.slurp(profit);
      const totalSupply = await yieldToken.totalSupply();
      const minAmtOut = profit.mul(depositAmount).div(totalSupply).mul(1).div(10000); // 1bps slippage allowed
      await alchemist.connect(admin).harvest(yieldToken.address, minAmtOut);


      await alchemist.poke(wallet.address);
      const { shares: startingShares } = await alchemist.positions(
        wallet.address,
        yieldToken.address
      );
      const minimumAmountOut = liquidateAmount.mul('999999999999999999').div(parseEther('1'))
      await alchemist.liquidate(yieldToken.address, liquidateAmount, minimumAmountOut);

      const { shares: endingShares } = await alchemist.positions(
        wallet.address,
        yieldToken.address
      );

      const burned = startingShares.sub(endingShares);
      expect(burned).equals(liquidateAmount);
    });

    it("reverts if not a supported yield token", async () => {
      await expect(
        alchemist.liquidate(underlyingToken.address, liquidateAmount, liquidateAmount)
      ).revertedWith('UnsupportedToken("' + underlyingToken.address + '")');
    });

    it("emits a Liquidate event", async () => {
      await expect(alchemist.liquidate(yieldToken.address, liquidateAmount, liquidateAmount))
        .to.emit(alchemist, "Liquidate")
        .withArgs(wallet.address, yieldToken.address, underlyingToken.address, liquidateAmount, liquidateAmount);
    });

    it("caps liquidation amount to account debt", async () => {
      const { debt: startingDebt } = await alchemist.accounts(wallet.address);
      await alchemist.liquidate(yieldToken.address, startingDebt.mul(2), startingDebt.mul(1).div(10000));

      const acct = await alchemist.accounts(wallet.address);
      expect(acct.debt).equals(0);
    });

    it("reverts if maximum loss is exceeded", async () => {
      const firstDepositAmount = parseUnits("500", "ether");
      const loss = parseUnits("2", "ether");

      await yieldToken.approve(alchemist.address, firstDepositAmount);
      await alchemist.deposit(
        yieldToken.address,
        firstDepositAmount,
        wallet.address
      );

      await yieldToken.siphon(loss);

      await expect(
        alchemist.liquidate(yieldToken.address, liquidateAmount, liquidateAmount)
      ).revertedWith('LossExceeded("' + yieldToken.address + '", 2, 1)');
    });

    it("transfers tokens to the transmuter", async () => {
      const startingBalance = await underlyingToken.balanceOf(
        transmuter.address
      );

      await alchemist.liquidate(yieldToken.address, liquidateAmount, liquidateAmount);

      const endingBalance = await underlyingToken.balanceOf(transmuter.address);
      const transferred = endingBalance.sub(startingBalance);

      expect(transferred).equals(liquidateAmount);
    });

    it("preharvests the tokens held by the minter", async () => {
      await yieldToken6
        .connect(other)
        .mint(parseUnits("10000", "mwei"), other.address);

      const depositAmount6 = parseUnits("500", "mwei");

      await yieldToken6
        .connect(other)
        .approve(alchemist.address, depositAmount6);
      await alchemist
        .connect(other)
        .deposit(yieldToken6.address, depositAmount6, other.address);

      const profit18 = parseUnits("100", "ether");
      await underlyingToken.approve(yieldToken.address, profit18);
      await yieldToken.slurp(profit18);
      const profit6 = parseUnits("50", "mwei");
      await underlyingToken6.approve(yieldToken6.address, profit6);
      await yieldToken6.slurp(profit6);

      const tokenBefore = await alchemist.getYieldTokenParameters(
        yieldToken.address
      );
      const tokenBefore6 = await alchemist.getYieldTokenParameters(
        yieldToken6.address
      );
      const minimumAmountOut = liquidateAmount.mul('999999999999999999').div(parseEther('1'))
      await alchemist.liquidate(yieldToken.address, liquidateAmount, minimumAmountOut);
      const tokenAfter = await alchemist.getYieldTokenParameters(
        yieldToken.address
      );
      const tokenAfter6 = await alchemist.getYieldTokenParameters(
        yieldToken6.address
      );
      const price = await yieldToken.price();
      const alchProfit = profit18.div(20); // 10000 total underlying held by yield token, 500 by alchemist
      expect(
        tokenAfter.harvestableBalance.sub(tokenBefore.harvestableBalance)
      ).equal(alchProfit.mul(parseEther("1")).div(price));
      expect(
        tokenAfter6.harvestableBalance.sub(tokenBefore6.harvestableBalance)
      ).equal(0);
    });
  });

  describe("donate", async () => {
    const depositAmount = parseUnits("500", "ether");
    const donateAmount = parseUnits("250", "ether");

    beforeEach(async () => {
      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(
        yieldToken.address,
        depositAmount,
        wallet.address
      );

      await yieldToken.approve(alchemist.address, depositAmount);
      await alchemist.deposit(yieldToken.address, depositAmount, other.address);

      await alchemist.mint(donateAmount, wallet.address);
      await debtToken.approve(alchemist.address, donateAmount);
    });

    it("grant credit to other depositors", async () => {
      const { debt: startingDebt } = await alchemist.accounts(other.address);

      await alchemist.donate(yieldToken.address, donateAmount);
      await alchemist.poke(other.address);

      const { debt: endingDebt } = await alchemist.accounts(other.address);

      expect(startingDebt.sub(endingDebt)).equals(donateAmount);
    });

    it("does not grant credit to the donor", async () => {
      const { debt: startingDebt } = await alchemist.accounts(wallet.address);

      await alchemist.donate(yieldToken.address, donateAmount);
      await alchemist.poke(wallet.address);

      const { debt: endingDebt } = await alchemist.accounts(wallet.address);

      expect(endingDebt).equals(startingDebt);
    });

    it("burns tokens from the donor", async () => {
      const startingBalance = await debtToken.balanceOf(wallet.address);

      await alchemist.donate(yieldToken.address, donateAmount);

      const endingBalance = await debtToken.balanceOf(wallet.address);
      const burned = startingBalance.sub(endingBalance);

      expect(burned).equals(donateAmount);
    });

    it("emits a Donate event", async () => {
      await expect(alchemist.donate(yieldToken.address, donateAmount))
        .to.emit(alchemist, "Donate")
        .withArgs(wallet.address, yieldToken.address, donateAmount);
    });
  });

  describe("minting limit", () => {
    const depositAmt = parseUnits("3000", "ether");
    beforeEach(async () => {
      await alchemist
        .connect(admin)
        .configureMintingLimit(parseUnits("1000", "ether"), 100);
      // await underlyingToken.mint(wallet.address, parseUnits('10000000', 'ether'))
      // await underlyingToken.connect(wallet).approve(yieldToken.address, parseUnits('10000000', 'ether'))
      // await yieldToken.mint(parseUnits('10000000', 'ether'), wallet.address);
      await yieldToken.connect(wallet).approve(alchemist.address, depositAmt);
      await alchemist
        .connect(wallet)
        .deposit(yieldToken.address, depositAmt, wallet.address);
    });

    it("does not stop a user from minting up to the limit", async () => {
      await alchemist
        .connect(wallet)
        .mint(parseUnits("1000", "ether"), wallet.address);
    });

    it("reverts if the minting limit is breached", async () => {
      await expect(
        alchemist
          .connect(wallet)
          .mint(parseUnits("1001", "ether"), wallet.address)
      ).revertedWith(
        "MintingLimitExceeded(1001000000000000000000, 1000000000000000000000)"
      );
    });

    it("allows the user to mint more if enough cooldown time has passed", async () => {
      await alchemist
        .connect(wallet)
        .mint(parseUnits("1000", "ether"), wallet.address);
      await mineBlocks(waffle.provider, 500);
      await alchemist
        .connect(wallet)
        .mint(parseUnits("500", "ether"), wallet.address);
    });

    it("reverts if the limit is below the set minimum", async () => {
      await expect(
        alchemist
          .connect(admin)
          .configureMintingLimit(parseUnits("1", "ether"), 100)
      ).revertedWith(`IllegalArgument()`);
    });

    it("reverts if the cooldown is above the set maximum", async () => {
      await expect(
        alchemist
          .connect(admin)
          .configureMintingLimit(parseUnits("1000000", "ether"), 10000000000)
      ).revertedWith(`IllegalArgument()`);
    });
  });

  describe("credit unlock rate", () => {
    it("sets the credit unlock rate", async () => {
      await alchemist
        .connect(admin)
        .configureCreditUnlockRate(yieldToken.address, 2);

      const { creditUnlockRate } = await alchemist.getYieldTokenParameters(
        yieldToken.address
      );

      expect(creditUnlockRate).equals(BigNumber.from(10).pow(18).div(2));
    });

    it("reverts if yield token is unsupported", async () => {
      await expect(
        alchemist
          .connect(admin)
          .configureCreditUnlockRate(underlyingToken.address, 1)
      ).revertedWith(`UnsupportedToken(\"${underlyingToken.address}\")`);
    });

    it("reverts if blocks is not greater than zero", async () => {
      await expect(
        alchemist
          .connect(admin)
          .configureCreditUnlockRate(yieldToken.address, 0)
      ).revertedWith("IllegalArgument()");
    });
  });

  describe("repay limit", () => {
    const depositAmt = parseUnits("4000", "ether");
    beforeEach(async () => {
      await alchemist
        .connect(admin)
        .configureRepayLimit(
          underlyingToken.address,
          parseUnits("1000", "ether"),
          100
        );
      // await underlyingToken.mint(wallet.address, parseUnits('10000', 'ether'))
      // await underlyingToken.connect(wallet).approve(yieldToken.address, parseUnits('10000', 'ether'))
      // await yieldToken.mint(parseUnits('10000', 'ether'), wallet.address);
      await yieldToken.connect(wallet).approve(alchemist.address, depositAmt);
      await alchemist
        .connect(wallet)
        .deposit(yieldToken.address, depositAmt, wallet.address);
      await alchemist
        .connect(wallet)
        .mint(parseUnits("1000", "ether"), wallet.address);
      await underlyingToken
        .connect(wallet)
        .approve(alchemist.address, parseUnits("10000", "ether"));
    });

    it("does not stop a user from repaying up to the limit", async () => {
      await alchemist
        .connect(wallet)
        .repay(
          underlyingToken.address,
          parseUnits("1000", "ether"),
          wallet.address
        );
    });

    it("reverts if the repayment limit is breached", async () => {
      await alchemist
        .connect(wallet)
        .mint(parseUnits("1000", "ether"), wallet.address);
      await expect(
        alchemist
          .connect(wallet)
          .repay(
            underlyingToken.address,
            parseUnits("1001", "ether"),
            wallet.address
          )
      ).revertedWith(
        `RepayLimitExceeded("${underlyingToken.address}", 1001000000000000000000, 1000000000000000000000)`
      );
    });

    it("allows the user to repay more if enough cooldown time has passed", async () => {
      await mineBlocks(waffle.provider, 1000);
      await alchemist
        .connect(wallet)
        .mint(parseUnits("1000", "ether"), wallet.address);
      await alchemist
        .connect(wallet)
        .repay(
          underlyingToken.address,
          parseUnits("1000", "ether"),
          wallet.address
        );
      await mineBlocks(waffle.provider, 500);
      await alchemist
        .connect(wallet)
        .repay(
          underlyingToken.address,
          parseUnits("500", "ether"),
          wallet.address
        );
    });
  });

  describe("liquidate limit", () => {
    const depositAmt = parseUnits("4000", "ether");
    beforeEach(async () => {
      await alchemist
        .connect(admin)
        .configureLiquidationLimit(
          underlyingToken.address,
          parseUnits("1000", "ether"),
          100
        );
      // await underlyingToken.mint(wallet.address, parseUnits('10000', 'ether'))
      // await underlyingToken.connect(wallet).approve(yieldToken.address, parseUnits('10000', 'ether'))
      // await yieldToken.mint(parseUnits('10000', 'ether'), wallet.address);
      await yieldToken.connect(wallet).approve(alchemist.address, depositAmt);
      await alchemist
        .connect(wallet)
        .deposit(yieldToken.address, depositAmt, wallet.address);
      await alchemist
        .connect(wallet)
        .mint(parseUnits("1000", "ether"), wallet.address);
    });

    it("does not stop a user from liquidating up to the limit", async () => {
      await alchemist
        .connect(wallet)
        .liquidate(yieldToken.address, parseUnits("1000", "ether"), parseUnits("1000", "ether"));
    });

    it("reverts if the liquidation limit is breached", async () => {
      await alchemist
        .connect(admin)
        .configureLiquidationLimit(
          underlyingToken.address,
          parseUnits("1000", "ether"),
          100
        );
      await alchemist
        .connect(wallet)
        .mint(parseUnits("1000", "ether"), wallet.address);
      await expect(
        alchemist
          .connect(wallet)
          .liquidate(yieldToken.address, parseUnits("1001", "ether"), parseUnits("1001", "ether"))
      ).revertedWith(
        `LiquidationLimitExceeded("${underlyingToken.address}", 1001000000000000000000, 1000000000000000000000)`
      );
    });

    it("allows the user to liquidate more if enough cooldown time has passed", async () => {
      await mineBlocks(waffle.provider, 1000);
      await alchemist
        .connect(wallet)
        .mint(parseUnits("1000", "ether"), wallet.address);
      await alchemist
        .connect(wallet)
        .liquidate(yieldToken.address, parseUnits("1000", "ether"), parseUnits("1000", "ether"));
      await mineBlocks(waffle.provider, 500);
      await alchemist
        .connect(wallet)
        .liquidate(yieldToken.address, parseUnits("500", "ether"), parseUnits("500", "ether"));
    });
  });

  describe("sentinel", () => {
    beforeEach(async () => {
      await alchemist.connect(admin).setSentinel(sentinel.address, true);
    });

    describe("add/remove", () => {
      it("adds a sentinel", async () => {
        const exists = await alchemist.sentinels(sentinel.address);
        expect(exists).equals(true);
      });

      it("removes a sentinel", async () => {
        await alchemist.connect(admin).setSentinel(sentinel.address, false);
        const exists = await alchemist.sentinels(sentinel.address);
        expect(exists).equals(false);
      });
    });

    describe("access", () => {
      it("can disable an underlying token", async () => {
        await alchemist
          .connect(sentinel)
          .setUnderlyingTokenEnabled(underlyingToken.address, false);
        await expect(
          alchemist
            .connect(wallet)
            .deposit(yieldToken.address, "1", wallet.address)
        ).revertedWith(`TokenDisabled("${underlyingToken.address}")`);
      });

      it("can disable a yield token", async () => {
        await alchemist
          .connect(sentinel)
          .setYieldTokenEnabled(yieldToken.address, false);
        await expect(
          alchemist
            .connect(wallet)
            .deposit(yieldToken.address, "1", wallet.address)
        ).revertedWith(`TokenDisabled("${yieldToken.address}")`);
      });
    });
  });
});
