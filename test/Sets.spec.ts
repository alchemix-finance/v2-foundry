import { expect } from "chai";
import { Wallet } from "ethers";
import { ethers, waffle } from "hardhat";
import { TestSets } from "../typechain";

describe("Sets", () => {
  let wallet: Wallet;
  let other: Wallet;
  let testSets: TestSets;

  before(async () => {
    [wallet, other] = waffle.provider.getWallets();
  });

  beforeEach(async () => {
    const testSetsFactory = await ethers.getContractFactory("TestSets");
    testSets = (await testSetsFactory.connect(wallet).deploy()) as TestSets;
  });

  describe("add", () => {
    it("adds an item to the set", async () => {
      await testSets.add(wallet.address);
      await testSets.add(other.address);
      const checkWallet = await testSets.contains(wallet.address);
      expect(checkWallet).equals(true);
      const checkOther = await testSets.contains(wallet.address);
      expect(checkOther).equals(true);
    });

    it("cannot add an item to the set if it already exists in the set", async () => {
      await testSets.add(wallet.address);
      await expect(testSets.add(wallet.address)).revertedWith("failed to add");
    });
  });

  describe("remove", () => {
    it("removes an item from the set", async () => {
      await testSets.add(wallet.address);
      await testSets.add(other.address);
      await testSets.remove(wallet.address);
      const checkWallet = await testSets.contains(wallet.address);
      expect(checkWallet).equals(false);
      const checkOther = await testSets.contains(other.address);
      expect(checkOther).equals(true);
    });

    it("cannot remove an item from the set if it does not already exist in the set", async () => {
      await expect(testSets.remove(wallet.address)).revertedWith(
        "failed to remove"
      );
    });
  });
});
