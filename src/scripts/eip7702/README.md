# Alchemix EIP-7702 Compatibility Upgrade Scripts

Scripts for upgrading the Alchemix protocol contracts to be compatible with [EIP-7702](https://eips.ethereum.org/EIPS/eip-7702). The upgrade involves deploying new implementation contracts and updating various protocol components.

`Note`: Scripts are currently for ethereum mainnet and mainnet forks. This may me updated to include other relevant networks.

## Overview

The upgrade process includes:

1. Deploying new implementation contracts with EIP-7702 compatibility:
   - AlchemistV2
   - AutoleverageCurveMetapool
   - AutoleverageCurveFactoryethpool
   - WETHGateway
   - ATokenGateway (for alETH and alUSD)

2. Upgrading proxies to point to new implementations
3. Updating whitelists with the new contract addresses
4. Removing old implementations from whitelists

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
- Access to an Ethereum mainnet RPC URL
- Private key with appropriate permissions for production deployment

## Setting Up

1. Set your private key as an environment variable:
   ```bash
   export PRIVATE_KEY=your_private_key_here
   ```

2. For production scripts, update the RPC URL in the shell scripts:
   ```bash
   # In upgradeMainnetPROD.sh and revertMainnetPROD.sh
   export RPC_URL="<your-mainnet-rpc-url>"
   ```

## Simulation (Testing on Fork)

Before running on production, test the upgrade on a local fork of mainnet:



### Testing the Upgrade

1. Start a local fork of mainnet:
   ```bash
   anvil --fork-url <your-mainnet-rpc-url>
   ```

2. In a new terminal, run the upgrade simulation:
    ```bash
    chmod +x ./src/scripts/eip7702/prod/upgradeMainnet.sh
    ```
   ```bash
   ./src/scripts/eip7702/upgradeMainnet.sh
   ```

### Testing the Revert

If you need to test reverting the upgrade:

```bash
chmod +x ./src/scripts/eip7702/revertMainnet.sh
```

```bash
./src/scripts/eip7702/revertMainnet.sh
```

## Important Notes About the Revert Script (DEV & PROD)

Before using the revert script in production:

1. Update the placeholder addresses with actual deployed contract addresses within UpgradeEIP7702CompatibilityScript.s.sol (& UpgradeEIP7702CompatibilityScriptPROD.s.sol in PROD):
   - `NEW_ATOKEN_GATEWAY_ALETH`
   - `NEW_WETH_GATEWAY`
   - `NEW_AUTOLEVEREGE_METAPOOL`
   - `NEW_AUTOLEVEREGE_FACTORYETHPOOL`
   - `NEW_ATOKEN_GATEWAY_ALUSD`

2. These addresses should be the ones that were deployed during the upgrade process. 

## Verification

Logs are printed to the console (or can be routed to a file e.g. with flag : > logs.txt).
A successful run will print somthing like this : 
   
```bash
  Starting EIP-7702 compatibility upgrade...
  ProxyAdmin owner: 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9
  New AlchemistV2 implementation deployed to: 0x7aCCb860799227e9b8de5e394B5be68800CDd6d6
  New AutoleverageCurveMetapool deployed to: 0x57c4A600da7518Ce023bacc84EC958A6a8e77E51
  New AutoleverageCurveFactoryethpool deployed to: 0xb0D1360179E7a644FB5213B0f7fBf423d529056f
  New WETHGateway deployed to: 0x34697828E7fd72B24e4667b6d44bDf0AbD39f78e
  New ATokenGateway for alETH deployed to: 0x8E2C1843Ec44E857765e43107b2d51dc83e30b1A
  New ATokenGateway for alUSD deployed to: 0xBb3c85Deaf9a55446B3F41129B3BD7fac4dEfe89
  All implementations deployed. Performing upgrades...
  AlchemistV2 proxy upgraded
  Updating ALETH whitelists...
  Updating ALUSD whitelists...
  Confirming whitelists...
  All whitelists updated.
  Removing old whitelisted addresses...
  All old whitelisted addresses removed.
  Upgrade complete!
```


## Production Deployment

⚠️ **CAUTION**: These scripts make changes to production contracts. Use with extreme care!

### Prerequisites for Production

1. Ensure you have the correct permissions to call the upgrade functions
2. Double-check all addresses in the script
3. Test thoroughly on a fork first
4. Have sufficient ETH for gas fees

### Running the Production Upgrade

```bash
chmod +x ./src/scripts/eip7702/prod/upgradeMainnetPROD.sh
```

```bash
./src/scripts/eip7702/prod/upgradeMainnetPROD.sh
```

### Emergency Revert (Use Only If Necessary)

If issues arise after the production deployment, you can revert to the original implementations:

```bash
chmod +x ./src/scripts/eip7702/prod/revertMainnetPROD.sh
```

```bash
./src/scripts/eip7702/prod/revertMainnetPROD.sh
```

After running either upgrade or revert, verify that:

1. The proxies point to the correct implementations
2. Whitelists contain the correct addresses
3. Protocol functionality works as expected

## Troubleshooting

- If you encounter issues with the script execution, check the RPC connection
- Ensure your private key has the necessary permissions
- Check gas settings if transactions are failing
- In production, consider simulating transactions first with `--dry-run`
