pragma solidity 0.8.13;

import {Ownable} from "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IAlchemistV1} from "../interfaces/IAlchemistV1.sol";
import {IAlToken} from "../interfaces/IAlToken.sol";

contract V1Deprecatooooor is Ownable {
    constructor() {}

    function deprecate(address alchemist, address altoken) external onlyOwner {
        IAlToken(altoken).pauseAlchemist(address(alchemist), true);
        uint256 numVaults = IAlchemistV1(alchemist).vaultCount();
        IAlchemistV1(alchemist).recallAll(numVaults - 2);
        IAlchemistV1(alchemist).flush();
        IAlchemistV1(alchemist).setEmergencyExit(true);
    }
}