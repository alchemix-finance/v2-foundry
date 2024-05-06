// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;
import {IERC20} from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";


interface IVeloOracle {
    function getManyRatesWithConnectors(uint8 src_len, IERC20[] memory connectors) external view returns (uint256[] memory rates);
}