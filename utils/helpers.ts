import { BigNumber, BigNumberish, ethers, utils } from "ethers";
import * as moment from "moment";

export const ONE = BigNumber.from(1);
export const MAXIMUM_U32 = ONE.shl(31);
export const MAXIMUM_U256 = ONE.shl(255);
export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

export const snapshot = async (
  provider: ethers.providers.JsonRpcProvider
): Promise<number> => {
  await provider.send("evm_snapshot", []);
  return await mine(provider);
};

export const revert = async (
  provider: ethers.providers.JsonRpcProvider,
  snapshotId: number
): Promise<any> => {
  return await provider.send("evm_revert", [snapshotId]);
};

export const increaseTime = async (
  provider: ethers.providers.JsonRpcProvider,
  seconds: number
): Promise<any> => {
  return provider.send("evm_increaseTime", [seconds]);
};

export const setNextBlockTime = async (
  provider: ethers.providers.JsonRpcProvider,
  time: moment.Moment
): Promise<any> => {
  return provider.send("evm_setNextBlockTimestamp", [time.unix()]);
};

export const mine = async (
  provider: ethers.providers.JsonRpcProvider
): Promise<any> => {
  return provider.send("evm_mine", []);
};

export const mineBlocks = async (
  provider: ethers.providers.JsonRpcProvider,
  numberBlocks: number
): Promise<any> => {
  for (let i = 0; i < numberBlocks; i++) {
    await provider.send("evm_mine", []);
  }
  return Promise.resolve();
};

export const feeOn = (
  value: BigNumberish,
  numerator: BigNumberish,
  resolution: BigNumberish
): BigNumber => {
  return ONE.mul(value).mul(numerator).div(resolution);
};

export const takeFee = (
  value: BigNumberish,
  numerator: BigNumberish,
  resolution: BigNumberish
): BigNumber => {
  return ONE.mul(value).sub(feeOn(value, numerator, resolution));
};

export const delay = (ms: number) => new Promise((res) => setTimeout(res, ms));

// export const getGas = async (tx) => {
// 	let resp = await tx.wait(1);
// 	console.log(resp);
// 	return resp.gasUsed;
// };

export const parseUsdc = (usdc: string): BigNumber => {
  return utils.parseUnits(usdc, 6);
};

export const formatUsdc = (usdcents: BigNumberish): string => {
  return utils.formatUnits(usdcents, 6);
};

export const generateRandomHex = (size: number) =>
  [...Array(size)]
    .map(() => Math.floor(Math.random() * 16).toString(16))
    .join("");