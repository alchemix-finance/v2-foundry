import chai from "chai";
import { solidity } from "ethereum-waffle";
import { ethers, deployments, waffle } from "hardhat";
import { BigNumber, BigNumberish, ContractFactory, Signer, utils } from "ethers";
import { AlchemixHarvester } from '../typechain/src/keepers/AlchemixHarvester';
import { HarvestResolver } from '../typechain/src/keepers/HarvestResolver';
import { AlchemistV2Mock } from '../typechain/src/mocks/AlchemistV2Mock';
import { YieldTokenMock } from '../typechain/src/mocks/YieldTokenMock';
import { ERC20Mock } from '../typechain/src/mocks/ERC20Mock';
import { TokenAdapterMock } from '../typechain/src/mocks/TokenAdapterMock';
import { increaseTime } from "../utils/helpers";
const {parseEther, formatEther} = utils;

chai.use(solidity);

const { expect } = chai;

let AlchemixHarvesterFactory: ContractFactory;
let HarvestResolverFactory: ContractFactory;
let AlchemistV2MockFactory: ContractFactory;
let YieldTokenMockFactory: ContractFactory;
let ERC20MockFactory: ContractFactory;
let TokenAdapterFactory: ContractFactory;

describe.only("AlchemixHarvester", () => {
    let signers: Signer[];
    let alHarvester: AlchemixHarvester;
    let alResolver: HarvestResolver;
    let alchemist: AlchemistV2Mock;
    let token: ERC20Mock;
    let yToken: YieldTokenMock;
    let tokenAdapter: TokenAdapterMock;

    let deployer: Signer;
    let rewards: Signer;
    let depositor: Signer;

    let depositorAddress: string;

    before(async () => {
        AlchemixHarvesterFactory = await ethers.getContractFactory("AlchemixHarvester");
        HarvestResolverFactory = await ethers.getContractFactory("HarvestResolver");
        AlchemistV2MockFactory = await ethers.getContractFactory("AlchemistV2Mock");
        ERC20MockFactory = await ethers.getContractFactory("ERC20Mock");
        YieldTokenMockFactory = await ethers.getContractFactory("YieldTokenMock");
        TokenAdapterFactory = await ethers.getContractFactory("TokenAdapterMock");
    });

    beforeEach(async () => {
        signers = await ethers.getSigners();
        [
            deployer,
            rewards,
            depositor,
            ...signers
          ] = signers;

        depositorAddress = await depositor.getAddress();
        
        token = (await ERC20MockFactory.deploy('Test Token', 'TEST')) as ERC20Mock;
        yToken = (await YieldTokenMockFactory.deploy('Test Yield', 'yTEST', token.address)) as YieldTokenMock;
        alchemist = (await AlchemistV2MockFactory.deploy(await rewards.getAddress())) as AlchemistV2Mock;
        tokenAdapter = (await TokenAdapterFactory.deploy(yToken.address)) as TokenAdapterMock;
        const params = {
            adapter: tokenAdapter.address,
            maximumLoss: 1,
            maximumExpectedValue: parseEther('1000000000'),
            creditUnlockBlocks: 10
        }
        await alchemist.setYieldTokenParameters(yToken.address, params);

        alResolver = (await HarvestResolverFactory.deploy()) as HarvestResolver;
        alHarvester = (await AlchemixHarvesterFactory.deploy(await deployer.getAddress(), 100000000000, alResolver.address)) as AlchemixHarvester;
        alResolver.setHarvester(alHarvester.address, true);

        await token.mint(await depositor.getAddress(), parseEther("10000"));
        await token.mint(await deployer.getAddress(), parseEther("10000"));
    });
    
    describe("HarvestResolver", () => {
        let depositAmt = parseEther("1000");
        let yieldAmt = parseEther("50");

        beforeEach(async () => {
            await alResolver.addHarvestJob(true, yToken.address, alchemist.address, parseEther("20"), 1, 1);
            await token.connect(depositor).approve(yToken.address, depositAmt);
            await yToken.connect(depositor).deposit(depositAmt);
            await yToken.connect(depositor).approve(alchemist.address, depositAmt);
            await alchemist.connect(depositor).deposit(yToken.address, depositAmt);
        })

        it("returns false if there is not enough to harvest", async () => {
            await increaseTime(waffle.provider, 200);
            const res = await alResolver.checker();
            expect(res.canExec).equal(false);
        })

        it("returns false if not enough time has passed since the last harvest", async () => {
            const res = await alResolver.checker();
            expect(res.canExec).equal(false);
        })

        it("returns false if the yield token is not active", async () => {
            await increaseTime(waffle.provider, 200);
            await alResolver.addHarvestJob(false, yToken.address, alchemist.address, parseEther("20"), 0, 1);
            const res = await alResolver.checker();
            expect(res.canExec).equal(false);
        })
        
        it("returns true with the correct parameters", async () => {
            await increaseTime(waffle.provider, 200);
            await token.connect(deployer).transfer(yToken.address, yieldAmt);
            const res = await alResolver.checker();
            expect(res.canExec).equal(true);
        })

        it("removes a harvest job", async () => {
            const yToken2 = (await YieldTokenMockFactory.deploy('Test Yield 2', 'yTEST2', token.address)) as YieldTokenMock;
            const tokenAdapter2 = (await TokenAdapterFactory.deploy(yToken.address)) as TokenAdapterMock;
            const params = {
                adapter: tokenAdapter2.address,
                maximumLoss: 1,
                maximumExpectedValue: parseEther('1000000000'),
                creditUnlockBlocks: 1
            }
            await alchemist.setYieldTokenParameters(yToken2.address, params);
            await alResolver.addHarvestJob(true, yToken2.address, alchemist.address, parseEther("20"), 1, 1);
            await alResolver.removeHarvestJob(yToken.address);
            const harvestJob = await alResolver.harvestJobs(yToken.address);
            expect(harvestJob.active).equal(false);
            expect(harvestJob.lastHarvest).equal(0);
            expect(harvestJob.minimumHarvestAmount).equal(0);
            expect(harvestJob.minimumDelay).equal(0);
            const yieldTokenAddy = await alResolver.yieldTokens(0);
            expect(yieldTokenAddy).equal(yToken2.address);
        })

        it("reverts when attempting to remove a harvest job that does not exist", async () => {
            await expect(alResolver.removeHarvestJob(alchemist.address)).revertedWith('HarvestJobDoesNotExist()');
        })

        it("returns false if the yield token is disabled in the alchemist", async () => {
            await increaseTime(waffle.provider, 200);
            await alchemist.setEnabledYieldToken(yToken.address, false);
            const res = await alResolver.checker();
            expect(res.canExec).equal(false);
        })

        it("returns false if the resolver is paused", async () => {
            await alResolver.setPause(true);
            const res = await alResolver.checker();
            expect(res.canExec).equal(false);
        })

        it("reverts when adding a yield token that is disabled in the alchemist", async () => {
            const yToken2 = (await YieldTokenMockFactory.deploy('Test Yield 2', 'yTEST2', token.address)) as YieldTokenMock;
            const tokenAdapter2 = (await TokenAdapterFactory.deploy(yToken.address)) as TokenAdapterMock;
            const params = {
                adapter: tokenAdapter2.address,
                maximumLoss: 1,
                maximumExpectedValue: parseEther('1000000000'),
                creditUnlockBlocks: 1
            }
            await alchemist.setYieldTokenParameters(yToken2.address, params);
            await alchemist.setEnabledYieldToken(yToken2.address, false);
            await expect(alResolver.addHarvestJob(true, yToken2.address, alchemist.address, parseEther('1'), 1, 1)).revertedWith('');
        })

        it('sets the active flag for a harvest job', async () => {
            const flag = false;
            await alResolver.setActive(yToken.address, flag);
            const harvestJob = await alResolver.harvestJobs(yToken.address);
            expect(harvestJob.active).equal(flag);
        })

        describe("setting the alchemist", () => {
            let alchemist2: AlchemistV2Mock;
            let yToken2: YieldTokenMock;
            beforeEach(async () => {
                alchemist2 = (await AlchemistV2MockFactory.deploy(await rewards.getAddress())) as AlchemistV2Mock;
                yToken2 = (await YieldTokenMockFactory.deploy('Test Yield 2', 'yTEST2', token.address)) as YieldTokenMock;
                const tokenAdapter2 = (await TokenAdapterFactory.deploy(yToken.address)) as TokenAdapterMock;
                const params = {
                    adapter: tokenAdapter2.address,
                    maximumLoss: 1,
                    maximumExpectedValue: parseEther('1000000000'),
                    creditUnlockBlocks: 1
                }
                await alchemist2.setYieldTokenParameters(yToken2.address, params);
            })

            it('sets the alchemist for a harvest job', async () => {
                await alResolver.setAlchemist(yToken2.address, alchemist2.address);
                const harvestJob = await alResolver.harvestJobs(yToken2.address);
                expect(harvestJob.alchemist).equal(alchemist2.address);
            })
    
            it('reverts if the yield token is not enabled in the alchemist', async () => {
                await alchemist2.setEnabledYieldToken(yToken2.address, false);
                await expect(alResolver.setAlchemist(yToken2.address, alchemist2.address)).revertedWith('YieldTokenDisabled()');
            })
        })


        it('sets the minimum harvest amount for a harvest job', async () => {
            const minimumHarvestAmount = parseEther('555');
            await alResolver.setMinimumHarvestAmount(yToken.address, minimumHarvestAmount);
            const harvestJob = await alResolver.harvestJobs(yToken.address);
            expect(harvestJob.minimumHarvestAmount).equal(minimumHarvestAmount);
        })

        it('sets the minimum delay for a harvest job', async () => {
            const minimumDelay = 555;
            await alResolver.setMinimumDelay(yToken.address, minimumDelay);
            const harvestJob = await alResolver.harvestJobs(yToken.address);
            expect(harvestJob.minimumDelay).equal(minimumDelay);
        })
    })

    describe("AlchemixHarvester", () => {
        let depositAmt = parseEther("1000");
        let yieldAmt = parseEther("50");

        describe("set poker", () => {
            it("reverts if the caller is not the owner", async () => {
                await expect(alHarvester.connect(depositor).setPoker(depositorAddress)).revertedWith("Ownable: caller is not the owner");
            })

            it("sets the poker address", async () => {
                await alHarvester.connect(deployer).setPoker(await depositor.getAddress())
                const poker = await alHarvester.gelatoPoker();
                expect(poker).equal(depositorAddress);
            })
        })

        describe("harvest", () => {
            beforeEach(async () => {
                await alResolver.addHarvestJob(true, yToken.address, alchemist.address, parseEther("20"), 0, 1);
                await token.connect(depositor).approve(yToken.address, depositAmt);
                await yToken.connect(depositor).deposit(depositAmt);
                await yToken.connect(depositor).approve(alchemist.address, depositAmt);
                await alchemist.connect(depositor).deposit(yToken.address, depositAmt);
            })
    
            it("correctly harvests the alchemist", async () => {
                await token.connect(deployer).transfer(yToken.address, yieldAmt);
                await increaseTime(waffle.provider, 200);
                const balBefore = await token.balanceOf(yToken.address);
                await alHarvester.harvest(alchemist.address, yToken.address, 0);
                const balAfter = await token.balanceOf(yToken.address);
                expect(balAfter).equal(balBefore.sub(yieldAmt));
            })

            it("reverts if the caller is not the poker", async () => {
                await expect(alHarvester.connect(depositor).harvest(alchemist.address, token.address, 0)).revertedWith("");
            })

            it("reverts if the gas is too damn high", async () => {
                await alHarvester.setMaxGasPrice(0);
                await expect(alHarvester.connect(depositor).harvest(alchemist.address, token.address, 0)).revertedWith("");
            })
        })
    })
})