import { expect } from "chai";
import { BigNumber, BigNumberish, Wallet } from "ethers";
import { network, ethers, waffle, upgrades } from "hardhat";
import {
  AlchemicTokenV2,
  AlchemicTokenV1,
  TestFlashBorrower
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

interface TokenFixture {
    alToken1: AlchemicTokenV1;
    alToken2: AlchemicTokenV2;
    flashBorrower: TestFlashBorrower;
}

async function tokenFixture([
  wallet,
  other,
  admin,
]: Wallet[]): Promise<TokenFixture> {
    const tokenFactory1 = await ethers.getContractFactory("AlchemicTokenV1", admin);
    const alToken1 = (await tokenFactory1.deploy()) as AlchemicTokenV1;

    const tokenFactory2 = await ethers.getContractFactory("AlchemicTokenV2", admin);
    const alToken2 = (await tokenFactory2.deploy("alBitcoin", "alBTC", 0)) as AlchemicTokenV2;

    const flashBorrowerFactory = await ethers.getContractFactory("TestFlashBorrower", admin);
    const flashBorrower = (await flashBorrowerFactory.deploy()) as TestFlashBorrower;

    return {
        alToken1,
        alToken2,
        flashBorrower
    };
}

describe("AlchemicTokenV2", () => {
    let wallet: Wallet, other: Wallet, admin: Wallet, sentinel: Wallet;

    let alToken1: AlchemicTokenV1;
    let alToken2: AlchemicTokenV2;
    let flashBorrower: TestFlashBorrower;

    let loadFixture: ReturnType<typeof waffle.createFixtureLoader>;

    before(async () => {
        [wallet, other, admin, sentinel] = waffle.provider.getWallets();
        loadFixture = waffle.createFixtureLoader([wallet, other, admin]);
    });

    beforeEach(async () => {
        ({
            alToken1,
            alToken2,
            flashBorrower
        } = await loadFixture(tokenFixture));
    });

    describe("Parity with AlchemicTokenV1", () => {
        describe("mint()", () => {
            const mintAmount = parseEther("10")

            describe("reverts if not whitelisted", () => {
                it("V1", async () => {
                    await expect(alToken1.connect(wallet).mint(wallet.address, mintAmount)).revertedWith("AlTokenV1: Alchemist is not whitelisted")
                })
    
                it("V2", async () => {
                    await expect(alToken2.connect(wallet).mint(wallet.address, mintAmount)).revertedWith("Unauthorized()")
                })
            })

            describe("reverts if paused", () => {
                it("V1", async () => {
                    await alToken1.setWhitelist(wallet.address, true);
                    await alToken1.pauseAlchemist(wallet.address, true);
                    await expect(alToken1.connect(wallet).mint(wallet.address, mintAmount)).revertedWith("AlUSD: Currently paused.")
                })
    
                it("V2", async () => {
                    await alToken2.setWhitelist(wallet.address, true);
                    await alToken2.pauseMinter(wallet.address, true);
                    await expect(alToken2.connect(wallet).mint(wallet.address, mintAmount)).revertedWith("IllegalState()")
                })
            })

            describe("mints to the recipient", () => {
                it("V1", async () => {
                    await alToken1.setWhitelist(wallet.address, true);
                    await alToken1.setCeiling(wallet.address, mintAmount)
                    const balBefore = await alToken1.balanceOf(wallet.address);
                    await alToken1.connect(wallet).mint(wallet.address, mintAmount)
                    const balAfter = await alToken1.balanceOf(wallet.address);
                    expect(balAfter).equal(balBefore.add(mintAmount));
                })

                it("V2", async () => {
                    await alToken2.setWhitelist(wallet.address, true);
                    const balBefore = await alToken2.balanceOf(wallet.address);
                    await alToken2.connect(wallet).mint(wallet.address, mintAmount)
                    const balAfter = await alToken2.balanceOf(wallet.address);
                    expect(balAfter).equal(balBefore.add(mintAmount));
                })
            })
        })

        describe("burn()", () => {
            const mintAmount = parseEther("10")
            const burnAmount = parseEther("5")
            beforeEach(async () => {
                await alToken1.setWhitelist(wallet.address, true);
                await alToken1.setCeiling(wallet.address, mintAmount)
                await alToken1.connect(wallet).mint(wallet.address, mintAmount)
                
                await alToken2.setWhitelist(wallet.address, true);
                await alToken2.connect(wallet).mint(wallet.address, mintAmount)
            })
            describe("reduces the user's balance", () => {
                it("V1", async () => {
                    const balBefore = await alToken1.balanceOf(wallet.address);
                    await alToken1.connect(wallet).burn(burnAmount)
                    const balAfter = await alToken1.balanceOf(wallet.address);
                    expect(balAfter).equal(balBefore.sub(burnAmount));
                })

                it("V2", async () => {
                    const balBefore = await alToken2.balanceOf(wallet.address);
                    await alToken2.connect(wallet).burn(burnAmount)
                    const balAfter = await alToken2.balanceOf(wallet.address);
                    expect(balAfter).equal(balBefore.sub(burnAmount));
                })
            })
        })

        describe("burnFrom()", () => {
            const mintAmount = parseEther("10")
            const burnAmount = parseEther("5")
            beforeEach(async () => {
                await alToken1.setWhitelist(wallet.address, true);
                await alToken1.setCeiling(wallet.address, mintAmount)
                await alToken1.connect(wallet).mint(wallet.address, mintAmount)
                
                await alToken2.setWhitelist(wallet.address, true);
                await alToken2.connect(wallet).mint(wallet.address, mintAmount)
            })
            describe("reverts if allowance is too small", () => {
                it("V1", async () => {
                    await expect(alToken1.connect(admin).burnFrom(wallet.address, burnAmount)).revertedWith("panic")
                })

                it("V2", async () => {
                    await expect(alToken2.connect(admin).burnFrom(wallet.address, burnAmount)).revertedWith("panic")
                })
            })

            describe("reduces the user's balance", () => {
                it("V1", async () => {
                    await alToken1.connect(wallet).approve(admin.address, burnAmount)
                    const balBefore = await alToken1.balanceOf(wallet.address);
                    await alToken1.connect(admin).burnFrom(wallet.address, burnAmount)
                    const balAfter = await alToken1.balanceOf(wallet.address);
                    expect(balAfter).equal(balBefore.sub(burnAmount));
                })

                it("V2", async () => {
                    await alToken2.connect(wallet).approve(admin.address, burnAmount)
                    const balBefore = await alToken2.balanceOf(wallet.address);
                    await alToken2.connect(admin).burnFrom(wallet.address, burnAmount)
                    const balAfter = await alToken2.balanceOf(wallet.address);
                    expect(balAfter).equal(balBefore.sub(burnAmount));
                })
            })
        })
    })

    describe("flash mint", () => {
        const initAmount = parseEther("5")
        const flashAmount = parseEther("10")

        beforeEach(async () => {
            await alToken2.setMaxFlashLoan(parseEther("100"))
            await alToken2.setFlashFee(1)
        })

        it("reverts if the token is incorrect", async () => {
            await expect(flashBorrower.takeLoan(alToken2.address, alToken1.address, flashAmount)).revertedWith("IllegalArgument()")
        })

        it("reverts if the max flash loan amount is breached", async () => {
            const bigFlashAmount = parseEther("1000")
            await expect(flashBorrower.takeLoan(alToken2.address, alToken2.address, bigFlashAmount)).revertedWith("IllegalArgument()")
        })

        it("returns 0 if the wrong token is passed to maxFlashLoan", async () => {
            const max = await alToken2.maxFlashLoan(alToken1.address)
            expect(max).equal(0)
        })
        
        it("burns the fee", async () => {
            await alToken2.setWhitelist(admin.address, true);
            await alToken2.connect(admin).mint(flashBorrower.address, initAmount)
            const balBefore = await alToken2.balanceOf(flashBorrower.address);
            const flashFee = await alToken2.flashFee(alToken2.address, flashAmount)
            await flashBorrower.takeLoan(alToken2.address, alToken2.address, flashAmount)
            const balAfter = await alToken2.balanceOf(flashBorrower.address);
            expect(balAfter).equal(balBefore.sub(flashFee))
        })
    })
});
