// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { DSTestPlus } from "./utils/DSTestPlus.sol";

import { 
    NextAlchemicToken, 
    InitializationParams 
} from "../NextAlchemicToken.sol";

import {IAlchemicToken} from "../interfaces/IAlchemicToken.sol";

contract NextAssetTest is DSTestPlus {
    address constant alUSD = 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A;
    NextAlchemicToken nextAlUSD;

    function setUp() external {
        InitializationParams memory params = InitializationParams({
            name: "nextAlUSD",
            symbol: "xAlUSD",
            alAsset: alUSD
        });

        NextAlchemicToken xAlUSD = new NextAlchemicToken();
        bytes memory nextParams = abi.encodeWithSelector(NextAlchemicToken.initialize.selector, params);
		TransparentUpgradeableProxy proxynextAlUSD = new TransparentUpgradeableProxy(address(xAlUSD), address(0xC224bf25Dcc99236F00843c7D8C4194abE8AA94a), nextParams);
        nextAlUSD = NextAlchemicToken(address(proxynextAlUSD));

        hevm.startPrank(0xC224bf25Dcc99236F00843c7D8C4194abE8AA94a);
        IAlchemicToken(alUSD).setWhitelist(address(nextAlUSD), true);
        IAlchemicToken(alUSD).setCeiling(address(nextAlUSD), UINT256_MAX);
        hevm.stopPrank();
        
        IAlchemicToken(alUSD).approve(address(nextAlUSD), UINT256_MAX);
        nextAlUSD.setWhitelist(address(this), true);
    }

    function testMint() external {
        uint256 amount = 100e18;
        
        nextAlUSD.mint(address(this), amount);

        assertEq(amount, nextAlUSD.balanceOf(alUSD));
        assertEq(0, nextAlUSD.balanceOf(address(this)));
        assertEq(amount, IERC20(alUSD).balanceOf(address(this)));
    }

    function testBurn() external {
        uint256 amount = 100e18;
        
        nextAlUSD.mint(address(this), amount);

        nextAlUSD.burn(address(this), amount);
    }

    function testBurnWithoutBacking() external {
        uint256 amount = 100e18;

        hevm.expectRevert("ERC20: burn amount exceeds balance");
        nextAlUSD.burn(address(this), amount);
    }
}