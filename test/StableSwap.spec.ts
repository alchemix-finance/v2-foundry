import { expect } from "chai";
import { Wallet } from "ethers";
import { ethers, waffle, upgrades } from "hardhat";
import { CrossChainCanonicalAlchemicTokenV2, ERC20Mock } from "../typechain";

describe("StableSwap", () => {
  let wallet: Wallet, admin: Wallet;
  let alchemicToken: CrossChainCanonicalAlchemicTokenV2;
  let bridgeToken: ERC20Mock, bridgeToken2: ERC20Mock;

  before(async () => {
    [wallet, admin] = waffle.provider.getWallets();
  });

  beforeEach(async () => {
    const bridgeTokenFactory = await ethers.getContractFactory("ERC20MockDecimals");
    bridgeToken = (await bridgeTokenFactory
      .connect(admin)
      .deploy("", "", 18)) as ERC20Mock;
    bridgeToken2 = (await bridgeTokenFactory
      .connect(admin)
      .deploy("", "", 18)) as ERC20Mock;

    const crossChainCanonicalAlchemicTokenV2Factory =
      await ethers.getContractFactory("CrossChainCanonicalAlchemicTokenV2");
    alchemicToken = (await upgrades.deployProxy(
      crossChainCanonicalAlchemicTokenV2Factory.connect(admin),
      [
        "alchemix TEST", 
        "alTEST", 
        [ bridgeToken.address ], 
        [ ethers.utils.parseEther("1000000") ]
      ],
      { unsafeAllow: ["delegatecall"] }
    )) as CrossChainCanonicalAlchemicTokenV2;
  });

  describe("stableswap", () => {
    it("add bridge token and return list", async () => {
      // Add bridge token
      await alchemicToken.connect(admin).addBridgeToken(bridgeToken2.address);
      // Check the current listings
      const tokens = await alchemicToken.allBridgeTokens();
      expect(tokens[0]).equal(bridgeToken.address);
      expect(tokens[1]).equal(bridgeToken2.address);
    });
    it("exchanges old for canonical", async () => {
      const tokenAmount = ethers.utils.parseUnits("1", "ether");
      // Mint bridge tokens
      await bridgeToken.connect(admin).mint(wallet.address, tokenAmount);
      // Approve bridge tokens
      await bridgeToken
        .connect(wallet)
        .approve(alchemicToken.address, tokenAmount);
      // Do the exchange
      await alchemicToken
        .connect(wallet)
        .exchangeOldForCanonical(bridgeToken.address, tokenAmount);
      // Check that user sent tokens
      const bridgeBalance = await bridgeToken.balanceOf(alchemicToken.address);
      expect(bridgeBalance).equal(tokenAmount);
      // Check that user received tokens, minus swap fee
      const userBalance = await alchemicToken.balanceOf(wallet.address);
      const swapFeeIn = await alchemicToken.swapFees(bridgeToken.address, "0");
      const feeAmount = swapFeeIn.mul(tokenAmount).div("1000000");
      // console.log(`swapFeeIn: ${swapFeeIn}, feeAmount: ${feeAmount}`);
      expect(userBalance).equal(tokenAmount.sub(feeAmount));
    });
    it("exchanges canonical for old", async () => {
      const tokenAmount = ethers.utils.parseUnits("1", "ether");
      // Mint bridge tokens
      await bridgeToken.connect(admin).mint(wallet.address, tokenAmount);
      // Approve bridge tokens
      await bridgeToken
        .connect(wallet)
        .approve(alchemicToken.address, tokenAmount);
      // Do the exchange
      await alchemicToken
        .connect(wallet)
        .exchangeOldForCanonical(bridgeToken.address, tokenAmount);

      // Now swap back
      const userBalance = await alchemicToken.balanceOf(wallet.address);
      await alchemicToken
        .connect(wallet)
        .exchangeCanonicalForOld(bridgeToken.address, userBalance);

      const swapFeeOut = await alchemicToken.swapFees(bridgeToken.address, "1");
      const feeAmount = swapFeeOut.mul(userBalance).div("1000000");
      const userOldBalance = await bridgeToken.balanceOf(wallet.address);
      expect(userOldBalance).equal(userBalance.sub(feeAmount));
    });
    it("reverts on exchangeCanonicalForOld if no liquidity", async () => {
      const tokenAmount = ethers.utils.parseUnits("1", "ether");
      await expect(
        alchemicToken.exchangeCanonicalForOld(bridgeToken.address, tokenAmount)
      ).revertedWith("ERC20: burn amount exceeds balance");
    });
    it("reverts on exchangeOldForCanonical if exchangesPaused", async () => {
      const tokenAmount = ethers.utils.parseUnits("1", "ether");
      // Mint bridge tokens
      await bridgeToken.connect(admin).mint(wallet.address, tokenAmount);
      // Approve bridge tokens
      await bridgeToken
        .connect(wallet)
        .approve(alchemicToken.address, tokenAmount);
      // Pause exchanges
      await alchemicToken.connect(admin).toggleExchanges();
      // Attempt the exchange
      await expect(
        alchemicToken
          .connect(wallet)
          .exchangeOldForCanonical(bridgeToken.address, tokenAmount)
      ).revertedWith("IllegalState()");
      // Now unpause
      await alchemicToken.connect(admin).toggleExchanges();
      // Attempt again and don't revert
      await alchemicToken
        .connect(wallet)
        .exchangeOldForCanonical(bridgeToken.address, tokenAmount);
    });
    it("reverts on exchangeOldForCanonical if bridgeToken paused", async () => {
      const tokenAmount = ethers.utils.parseUnits("1", "ether");
      // Mint bridge tokens
      await bridgeToken.connect(admin).mint(wallet.address, tokenAmount);
      // Approve bridge tokens
      await bridgeToken
        .connect(wallet)
        .approve(alchemicToken.address, tokenAmount);
      // Pause exchanges
      await alchemicToken
        .connect(admin)
        .toggleBridgeToken(bridgeToken.address, false);
      // Attempt the exchange
      await expect(
        alchemicToken
          .connect(wallet)
          .exchangeOldForCanonical(bridgeToken.address, tokenAmount)
      ).revertedWith("IllegalState()");
      // Now unpause
      await alchemicToken
        .connect(admin)
        .toggleBridgeToken(bridgeToken.address, true);
      // Attempt again and don't revert
      await alchemicToken
        .connect(wallet)
        .exchangeOldForCanonical(bridgeToken.address, tokenAmount);
    });
    it("recovers ERC20s in the token contract", async () => {
      const tokenAmount = ethers.utils.parseUnits("1", "ether");
      // Mint bridge tokens
      await bridgeToken.connect(admin).mint(wallet.address, tokenAmount);
      // Send to token contract
      await bridgeToken
        .connect(wallet)
        .transfer(alchemicToken.address, tokenAmount);
      // Fail to retrieve because it's a bridge token
      await expect(
        alchemicToken
          .connect(admin)
          .recoverERC20(bridgeToken.address, tokenAmount)
      ).revertedWith("IllegalState()");
      // Disable token as bridge token
      await alchemicToken
        .connect(admin)
        .toggleBridgeToken(bridgeToken.address, false);
      // Succeed at withdrawing
      await alchemicToken
        .connect(admin)
        .recoverERC20(bridgeToken.address, tokenAmount);
      // Check balance
      const tokenBalance = await bridgeToken.balanceOf(admin.address);
      expect(tokenBalance).equal(tokenAmount);
    });
    it("changes swap fees for a bridgeToken", async () => {
      const newSwapFee = ethers.BigNumber.from("500");
      await alchemicToken
        .connect(admin)
        .setSwapFees(bridgeToken.address, newSwapFee, newSwapFee);

      const tokenAmount = ethers.utils.parseUnits("1", "ether");
      // Mint bridge tokens
      await bridgeToken.connect(admin).mint(wallet.address, tokenAmount);
      // Approve bridge tokens
      await bridgeToken
        .connect(wallet)
        .approve(alchemicToken.address, tokenAmount);
      // Do the exchange
      await alchemicToken
        .connect(wallet)
        .exchangeOldForCanonical(bridgeToken.address, tokenAmount);
      // Check that user sent tokens
      const bridgeBalance = await bridgeToken.balanceOf(alchemicToken.address);
      expect(bridgeBalance).equal(tokenAmount);
      // Check that user received tokens, minus new swap fee
      const userBalance = await alchemicToken.balanceOf(wallet.address);
      const feeAmount = newSwapFee.mul(tokenAmount).div("1000000");
      expect(userBalance).equal(tokenAmount.sub(feeAmount));
    });
    it("doesn't charge swap fees for a fee-exempt address", async () => {
      await alchemicToken.connect(admin).toggleFeesForAddress(wallet.address);

      const tokenAmount = ethers.utils.parseUnits("1", "ether");
      // Mint bridge tokens
      await bridgeToken.connect(admin).mint(wallet.address, tokenAmount);
      // Approve bridge tokens
      await bridgeToken
        .connect(wallet)
        .approve(alchemicToken.address, tokenAmount);
      // Do the exchange
      await alchemicToken
        .connect(wallet)
        .exchangeOldForCanonical(bridgeToken.address, tokenAmount);
      // Check that user sent tokens
      const bridgeBalance = await bridgeToken.balanceOf(alchemicToken.address);
      expect(bridgeBalance).equal(tokenAmount);
      // Check that user received tokens, minus new swap fee
      const userBalance = await alchemicToken.balanceOf(wallet.address);
      expect(userBalance).equal(tokenAmount);
    });
  });
});
