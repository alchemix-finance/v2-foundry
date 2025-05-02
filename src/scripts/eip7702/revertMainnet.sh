#!/bin/bash

# revertMainnet.sh - Script to run the revert function on a forked mainnet

# Set RPC URL (modify as needed)
export RPC_URL="http://localhost:8545"

# Create a mainnet fork
echo "Creating mainnet fork..."
forge script \
  src/scripts/eip7702/prod/UpgradeEIP7702CompatibilityScriptPROD.s.sol:UpgradeEIP7702CompatibilityScriptPROD \
  --rpc-url $RPC_URL \
  --sig "revertUpgrade()" \
  -vvv

echo "Revert simulation complete!"