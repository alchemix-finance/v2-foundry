#!/bin/bash

# upgradeMain.sh - Script to run the upgrade function on mainnet

# Set RPC URL (modify as needed)
export RPC_URL="<MAINNET_RPC_URL>"
# Create a mainnet fork
echo "Creating mainnet fork..."
forge script \
  src/scripts/eip7702/prod/UpgradeEIP7702CompatibilityScriptPROD.s.sol:UpgradeEIP7702CompatibilityScriptPROD \
  --rpc-url $RPC_URL \
  --sig "run()" \
  -vvv

echo "Upgrade simulation complete!"