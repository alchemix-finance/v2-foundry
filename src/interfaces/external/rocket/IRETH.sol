// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.5.0;

import {IERC20} from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IERC20Metadata} from "../../IERC20Metadata.sol";

interface IRETH is IERC20, IERC20Metadata {
    function getEthValue(uint256 amount) external view returns (uint256);
    function getRethValue(uint256 amount) external view returns (uint256);
    function getExchangeRate() external view returns (uint256);
    function getTotalCollateral() external view returns (uint256);
    function getCollateralRate() external view returns (uint256);
    function depositExcess() external payable;
    function depositExcessCollateral() external;
    function mint(uint256 amount, address receiver) external;
    function burn(uint256 amount) external;
}