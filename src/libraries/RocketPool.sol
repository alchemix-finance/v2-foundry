pragma solidity >=0.5.0;

import {IRETH} from "../interfaces/external/rocket/IRETH.sol";
import {IRocketStorage} from "../interfaces/external/rocket/IRocketStorage.sol";

library RocketPool {
    /// @dev Gets the current rETH contract.
    ///
    /// @param self The rocket storage contract to read from.
    ///
    /// @return The current rETH contract.
    function getRETH(IRocketStorage self) internal view returns (IRETH) {
        return IRETH(self.getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"))
        ));
    }
}