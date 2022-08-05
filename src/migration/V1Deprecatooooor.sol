pragma solidity 0.8.13;

import {Ownable} from "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IAlchemistV1} from "../interfaces/IAlchemistV1.sol";
import {IAlToken} from "../interfaces/IAlToken.sol";
import {ITransmuterV1} from "../interfaces/ITransmuterV1.sol";

contract V1Deprecatooooor is Ownable {
    constructor() {}

    function deprecate(address alchemist, address altoken, address transmuter) external onlyOwner {
        IAlToken(altoken).pauseAlchemist(address(alchemist), true);
        ITransmuterV1(transmuter).setPause(true);
        uint256 numVaults = IAlchemistV1(alchemist).vaultCount();
        // we are going to recall the funds from the most recent vault.
        // we are assuming that the new TransferAdapter has already been deployed and
        // added to the Alchemist via the migrate() function, which is why we need the (-2).
        IAlchemistV1(alchemist).recallAll(numVaults - 2);
        IAlchemistV1(alchemist).flush();
        IAlchemistV1(alchemist).setEmergencyExit(true);
    }
}