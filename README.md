# Alchemix V2 Foundry

Foundry-based repository for Alchemix V2 tools, expansions, new vaults, and surrounding infrastructure.

## Overview

Alchemix is a DeFi protocol that allows users to receive instant, self-repaying loans backed by yield-generating collateral. This repository contains the smart contract infrastructure for Alchemix V2.

## Key Contracts

| Contract | Description |
|----------|-------------|
| `AlchemistV2` | Core lending contract managing collateral deposits, debt, and yield |
| `TransmuterV2` | Converts synthetic assets (alUSD/alETH) to underlying tokens |
| `TransmuterBuffer` | Buffers funds between the Alchemist and Transmuter |
| `AlchemicTokenV2` | ERC20 synthetic tokens (alUSD, alETH) |
| `StakingPools` | ALCX staking and rewards distribution |
| `ThreePoolAssetManager` | Manages assets in Curve 3pool |
| `EthAssetManager` | Manages ETH-based yield strategies |

## Adapters

Token adapters connect the Alchemist to various yield sources:

- **Aave**: `AAVETokenAdapter`, `AaveV3TokenAdapter`
- **Yearn**: `YearnTokenAdapter`
- **Lido**: `WstETHAdapter`
- **Rocket Pool**: `RETHAdapterV1`
- **Vesper**: `VesperAdapterV1`
- **Fuse**: `FuseTokenAdapterV1`

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js >= 18

### Installation

```bash
# Clone the repository
git clone https://github.com/alchemix-finance/v2-foundry.git
cd v2-foundry

# Install submodules
git submodule update --init --recursive

# Install Foundry dependencies
forge install

# Install Node dependencies
yarn install
```

### Compile Contracts

```bash
forge build
```

### Run Tests

```bash
# Run all tests
make test

# Run specific test file
make test_file_block FILE=AlchemistV2

# Run with specific block number
make test_file_block FILE=WstETHAdapterV1 BLOCK=16839048
```

## Environment Setup

Copy `.env.example` to `.env` and configure:

```bash
cp .env.example .env
```

Required variables:
- `ALCHEMY_API_KEY`: Alchemy API key for mainnet forking
- `OPTIMISM_ALCHEMY_API_KEY`: Alchemy API key for Optimism
- `ARBITRUM_ALCHEMY_API_KEY`: Alchemy API key for Arbitrum

## Project Structure

```
src/
├── adapters/          # Yield source adapters (Aave, Yearn, Lido, etc.)
├── base/              # Base contracts and utilities
├── interfaces/        # Contract interfaces
├── keepers/           # Keeper/automation contracts
├── libraries/         # Shared libraries
├── migration/         # Migration utilities
├── mocks/             # Mock contracts for testing
├── test/              # Test files
└── utils/             # Utility contracts
```

## Documentation

- [Alchemix Docs](https://alchemix-finance.gitbook.io/v2/)
- [Foundry Book](https://book.getfoundry.sh/)

## Security

For security concerns, please refer to the Alchemix security policy.

## License

MIT
