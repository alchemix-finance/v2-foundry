// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {AlchemistV2} from "../../../AlchemistV2.sol";
import {AutoleverageCurveMetapool} from "../../../AutoleverageCurveMetapool.sol";
import {AutoleverageCurveFactoryethpool} from "../../../AutoleverageCurveFactoryethpool.sol";
import {WETHGateway} from "../../../WETHGateway.sol";
import {ATokenGateway} from "../../../adapters/aave/ATokenGateway.sol";
import {YTokenGateway} from "../../../adapters/yearn/YTokenGateway.sol";
import {ProxyAdmin} from "../../../../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "../../../../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IWhitelist} from "../../../interfaces/IWhitelist.sol";

// Running the script
// forge script script/UpgradeEIP7702Compatibility.s.sol:UpgradeEIP7702CompatibilityScriptPROD --rpc-url $RPC_URL --broadcast --verify

contract UpgradeEIP7702CompatibilityScriptPROD is Script {
    // Addresses needed for the upgrade - to be filled before running the script
    address constant PROXY_ADMIN_ADDRESS = address(0xE0fC5CB7665041CdA26969A2D1ceb5cD5046347d);
    address constant PROXY_ADMIN_OWNER = address(0xE0fC5CB7665041CdA26969A2D1ceb5cD5046347d);
    
    // Proxy address
    address constant ALCHEMIST_PROXY_ADDRESS = address(0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd);

    // Original Implementations
    address constant AUTOLEVEREGE_METAPOOL_ADDRESS = address(0xe3CfDbfA339b749C6df27854E11Df3398b12d56E);
    address constant AUTOLEVEREGE_FACTORYETHPOOL_ADDRESS = address(0x0256fC7bA8d1513Be9661c504F36e075942d9A49);
    address constant WETH_GATEWAY_ADDRESS = address(0xA22a7ec2d82A471B1DAcC4B37345Cf428E76D67A); 
    address constant ATOKEN_GATEWAY_ALUSD_ADDRESS = address(0x67EC822A2F981Ef2db6Afce4E8dF57ff1439f4d3); 
    address constant ATOKEN_GATEWAY_ALETH_ADDRESS = address(0xA067C885d958aec176eC3D8dAdc847e0c9384809);
    address constant ALCHEMIST_ADDRESS = address(0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd);

    // Whitelist addresses
    address constant ALCHEMIST_ALUSD_WHITELIST_ADDRESS = address(0x78537a6CeBa16f412E123a90472C6E0e9A8F1132); 
    address constant ALCHEMIST_ALETH_WHITELIST_ADDRESS = address(0xA3dfCcbad1333DC69997Da28C961FF8B2879e653);

    // Other addresses
    address constant WETH_ADDRESS = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    function run() public {
        string memory privateKeyStr = vm.envString("PRIVATE_KEY");
        uint256 deployerPrivateKey;
        if (bytes(privateKeyStr).length > 0 && bytes(privateKeyStr)[0] != '0' && bytes(privateKeyStr)[1] != 'x') {
            // Add 0x prefix if missing
            deployerPrivateKey = vm.parseUint(string(abi.encodePacked("0x", privateKeyStr)));
        } else {
            deployerPrivateKey = vm.parseUint(privateKeyStr);
        }
        
        // Should be proxy admin owner
        vm.startBroadcast(deployerPrivateKey);
        
        console2.log("Starting EIP-7702 compatibility upgrade...");

        // Get proxy admin
        ProxyAdmin proxyAdmin = ProxyAdmin(PROXY_ADMIN_ADDRESS);
            
        // Deploy new implementations
        
        // 1. AlchemistV2
        AlchemistV2 alchemistV2Implementation = new AlchemistV2();
        console2.log("New AlchemistV2 implementation deployed to:", address(alchemistV2Implementation));
        
        // 2. AutoleverageCurveMetapool
        AutoleverageCurveMetapool metapoolImpl = new AutoleverageCurveMetapool();
        console2.log("New AutoleverageCurveMetapool deployed to:", address(metapoolImpl));
        
        // 3. AutoleverageCurveFactoryethpool
        AutoleverageCurveFactoryethpool factoryethpoolImpl = new AutoleverageCurveFactoryethpool();
        console2.log("New AutoleverageCurveFactoryethpool deployed to:", address(factoryethpoolImpl));
        
        // 4. WETHGateway
        WETHGateway wethGatewayImpl = new WETHGateway(
            ALCHEMIST_PROXY_ADDRESS,
            ALCHEMIST_ALETH_WHITELIST_ADDRESS
        );
        console2.log("New WETHGateway deployed to:", address(wethGatewayImpl));
        
        // 5. ATokenGateway for alETH
        ATokenGateway aTokenGatewayImplALETH = new ATokenGateway(
            ALCHEMIST_PROXY_ADDRESS,
            ALCHEMIST_ALETH_WHITELIST_ADDRESS
        );
        console2.log("New ATokenGateway for alETH deployed to:", address(aTokenGatewayImplALETH));

        // 6. ATokenGateway for alUSD
        ATokenGateway aTokenGatewayImplALUSD = new ATokenGateway(
            ALCHEMIST_PROXY_ADDRESS,
            ALCHEMIST_ALUSD_WHITELIST_ADDRESS
        );
        console2.log("New ATokenGateway for alUSD deployed to:", address(aTokenGatewayImplALUSD));
        console2.log("All implementations deployed. Performing upgrades...");
        
        // Perform the upgrades
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(payable(ALCHEMIST_PROXY_ADDRESS)), 
            address(alchemistV2Implementation)
        );
        console2.log("AlchemistV2 proxy upgraded");

        // Updating whitelists
        console2.log("Updating ALETH whitelists...");
        IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).add(address(aTokenGatewayImplALETH));
        IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).add(address(wethGatewayImpl));
        IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).add(address(metapoolImpl));
        IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).add(address(factoryethpoolImpl));

        console2.log("Updating ALUSD whitelists...");
        IWhitelist(ALCHEMIST_ALUSD_WHITELIST_ADDRESS).add(address(aTokenGatewayImplALUSD));

        // confirm addresses are whitelisted
        console2.log("Confirming whitelists...");
        require(IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).isWhitelisted(address(aTokenGatewayImplALETH)), "ATokenGateway for alETH is not whitelisted");
        require(IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).isWhitelisted(address(wethGatewayImpl)), "WETHGateway is not whitelisted");
        require(IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).isWhitelisted(address(metapoolImpl)), "AutoleverageCurveMetapool is not whitelisted");
        require(IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).isWhitelisted(address(factoryethpoolImpl)), "AutoleverageCurveFactoryethpool is not whitelisted");
        require(IWhitelist(ALCHEMIST_ALUSD_WHITELIST_ADDRESS).isWhitelisted(address(aTokenGatewayImplALUSD)), "ATokenGateway for alUSD is not whitelisted");
        

        console2.log("All whitelists updated.");
        console2.log("Removing old whitelisted addresses...");
        IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).remove(ATOKEN_GATEWAY_ALETH_ADDRESS);
        IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).remove(WETH_GATEWAY_ADDRESS);
        IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).remove(AUTOLEVEREGE_METAPOOL_ADDRESS);
        IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).remove(AUTOLEVEREGE_FACTORYETHPOOL_ADDRESS);
        IWhitelist(ALCHEMIST_ALUSD_WHITELIST_ADDRESS).remove(ATOKEN_GATEWAY_ALUSD_ADDRESS);

        // confirm addresses are not whitelisted
        require(!IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).isWhitelisted(ATOKEN_GATEWAY_ALETH_ADDRESS), "Original ATokenGateway for alETH is still whitelisted");
        require(!IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).isWhitelisted(WETH_GATEWAY_ADDRESS), "Original WETHGateway is still whitelisted");
        require(!IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).isWhitelisted(AUTOLEVEREGE_METAPOOL_ADDRESS), "Original AutoleverageCurveMetapool is still whitelisted");
        require(!IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).isWhitelisted(AUTOLEVEREGE_FACTORYETHPOOL_ADDRESS), "Original AutoleverageCurveFactoryethpool is still whitelisted");
        require(!IWhitelist(ALCHEMIST_ALUSD_WHITELIST_ADDRESS).isWhitelisted(ATOKEN_GATEWAY_ALUSD_ADDRESS), "Original ATokenGateway for alUSD is still whitelisted");

        console2.log("All old whitelisted addresses removed.");
        console2.log("Upgrade complete!");
        vm.stopBroadcast();
    }

    function revertUpgrade() public {
        string memory privateKeyStr = vm.envString("PRIVATE_KEY");
        uint256 deployerPrivateKey;
        if (bytes(privateKeyStr).length > 0 && bytes(privateKeyStr)[0] != '0' && bytes(privateKeyStr)[1] != 'x') {
            // Add 0x prefix if missing
            deployerPrivateKey = vm.parseUint(string(abi.encodePacked("0x", privateKeyStr)));
        } else {
            deployerPrivateKey = vm.parseUint(privateKeyStr);
        }
        vm.startBroadcast(deployerPrivateKey);

        
        console2.log("Starting reversion of EIP-7702 compatibility upgrade...");
        
        // Get proxy admin
        ProxyAdmin proxyAdmin = ProxyAdmin(PROXY_ADMIN_ADDRESS);
        
        // Revert the AlchemistV2 proxy back to original implementation
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(payable(ALCHEMIST_PROXY_ADDRESS)), 
            ALCHEMIST_ADDRESS
        );
        console2.log("AlchemistV2 proxy reverted to original implementation.");
        
        // Add original implementations back to whitelists
        console2.log("Restoring original ALETH whitelists...");
        IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).add(ATOKEN_GATEWAY_ALETH_ADDRESS);
        IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).add(WETH_GATEWAY_ADDRESS);
        IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).add(AUTOLEVEREGE_METAPOOL_ADDRESS);
        IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).add(AUTOLEVEREGE_FACTORYETHPOOL_ADDRESS);
        
        console2.log("Restoring original ALUSD whitelists...");
        IWhitelist(ALCHEMIST_ALUSD_WHITELIST_ADDRESS).add(ATOKEN_GATEWAY_ALUSD_ADDRESS);
        
        // confirm original addresses are now whitelisted
        console2.log("Confirming whitelists...");
        require(IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).isWhitelisted(ATOKEN_GATEWAY_ALETH_ADDRESS), "Original ATokenGateway for alETH is not whitelisted");
        require(IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).isWhitelisted(WETH_GATEWAY_ADDRESS), "Original WETHGateway is not whitelisted");
        require(IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).isWhitelisted(AUTOLEVEREGE_METAPOOL_ADDRESS), "Original AutoleverageCurveMetapool is not whitelisted");
        require(IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).isWhitelisted(AUTOLEVEREGE_FACTORYETHPOOL_ADDRESS), "Original AutoleverageCurveFactoryethpool is not whitelisted");
        require(IWhitelist(ALCHEMIST_ALUSD_WHITELIST_ADDRESS).isWhitelisted(ATOKEN_GATEWAY_ALUSD_ADDRESS), "Original ATokenGateway for alUSD is not whitelisted");
        
        // Using placeholder addresses for the new implementations that need to be removed from whitelists
        // These should be updated with the actual addresses of the new implementations once deployed
        address NEW_ATOKEN_GATEWAY_ALETH = address(0); // replace with actual address
        address NEW_WETH_GATEWAY = address(0); // replace with actual address
        address NEW_AUTOLEVEREGE_METAPOOL = address(0); // replace with actual address
        address NEW_AUTOLEVEREGE_FACTORYETHPOOL = address(0); // replace with actual address
        address NEW_ATOKEN_GATEWAY_ALUSD = address(0); // replace with actual address
        
        console2.log("Removing new implementation addresses from whitelists...");
        IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).remove(NEW_ATOKEN_GATEWAY_ALETH);
        IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).remove(NEW_WETH_GATEWAY);
        IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).remove(NEW_AUTOLEVEREGE_METAPOOL);
        IWhitelist(ALCHEMIST_ALETH_WHITELIST_ADDRESS).remove(NEW_AUTOLEVEREGE_FACTORYETHPOOL);
        IWhitelist(ALCHEMIST_ALUSD_WHITELIST_ADDRESS).remove(NEW_ATOKEN_GATEWAY_ALUSD);
        
        console2.log("Reversion complete!");
        vm.stopBroadcast();
    }
}