import { expect } from "chai";
import { Wallet } from "ethers";
import { ethers, waffle } from "hardhat";
import {
  TestWhitelisted,
  TestWhitelistedCaller,
  Whitelist,
} from "../typechain";

describe("Whitelist", () => {
  let wallet: Wallet, admin: Wallet;
  let testWhitelisted: TestWhitelisted;
  let whitelist: Whitelist;
  let testWhitelistedCaller: TestWhitelistedCaller;

  before(async () => {
    [wallet, admin] = waffle.provider.getWallets();
  });

  beforeEach(async () => {
    const whitelistFactory = await ethers.getContractFactory("Whitelist");
    whitelist = (await whitelistFactory.connect(admin).deploy()) as Whitelist;
    const testWhitelistedFactory = await ethers.getContractFactory(
      "TestWhitelisted"
    );
    testWhitelisted = (await testWhitelistedFactory
      .connect(admin)
      .deploy(whitelist.address)) as TestWhitelisted;
    const testWhitelistedCallerFactory = await ethers.getContractFactory(
      "TestWhitelistedCaller"
    );
    testWhitelistedCaller = (await testWhitelistedCallerFactory
      .connect(admin)
      .deploy()) as TestWhitelistedCaller;
  });

  describe("admin functions", () => {
    it("reverts if the caller is not the admin", async () => {
      await expect(
        whitelist
          .connect(wallet)
          .add(
            testWhitelistedCaller.address
          )
      ).revertedWith("Unauthorized");
    });

    it("reverts if the caller is not the admin", async () => {
      await expect(
        whitelist
          .connect(wallet)
          .remove(
            testWhitelistedCaller.address
          )
      ).revertedWith("Unauthorized");
    });

    it("reverts if the caller is not the admin", async () => {
      await expect(
        whitelist.connect(wallet).disable()
      ).revertedWith("Unauthorized");
    });

    it("allows the whitelist admin to perform admin functions", async () => {
      await whitelist
        .connect(admin)
        .add(testWhitelistedCaller.address);
      await whitelist
        .connect(admin)
        .remove(
          
          testWhitelistedCaller.address
        );
      await whitelist.connect(admin).disable();
    });
  });

  describe("onlyWhitelisted", () => {
    it("reverts if the caller is a non-whitelisted contract", async () => {
      await expect(
        testWhitelistedCaller.test(testWhitelisted.address)
      ).revertedWith("Unauthorized");
    });

    it("succeeds if the caller is a whitelisted contract", async () => {
      await whitelist
        .connect(admin)
        .add(testWhitelistedCaller.address);
      expect(await testWhitelistedCaller.test(testWhitelisted.address)).emit(
        testWhitelisted,
        "Success"
      );
    });

    it("succeeds if the caller is an EOA", async () => {
      expect(await testWhitelisted.connect(wallet).test()).emit(
        testWhitelisted,
        "Success"
      );
    });
  });
});
