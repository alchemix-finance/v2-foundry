# Alchemix V2 On-Chain Admin & Sentinel Verification (Block 26400152)

- **Protocol**: Alchemix V2 (`alchemix-finance/v2-foundry`)
- **Pinned Block**: Ethereum Mainnet Block `26400152` (`0xa9a61622304ec55c5fec49abbcabec60069f66f28792cf841bdd7aef12ce63aa`)
- **Auditor**: Pacta — Protocol Commitments DRI ([Fractal Neurons](https://fractalneurons.com)) · [`Fractal-Neurons/pacta`](https://github.com/Fractal-Neurons/pacta) · `pacta@dri.network`

---

## 1. Verified Core Governance & Allocator Wiring (`AX1` — PASS)

At Ethereum mainnet block `26400152`, we verified the primary administrative and operator invariants across `AlchemistV2 (alUSD)` (`0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd`) and `AlchemistV2 (alETH)` (`0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c`):

| Contract | Address | Checked Invariant | Live State (Block `26400152`) | Status |
| :--- | :--- | :--- | :--- | :--- |
| `AlchemistV2 (alUSD)` | `0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd` | `admin()` == 5-of-8 Dev Multisig | `0x8392F6669292fA56123F71949B52d883aE57e225` (`5-of-8` Safe) | **PASS** |
| `AlchemistV2 (alETH)` | `0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c` | `admin()` == 5-of-8 Dev Multisig | `0x8392F6669292fA56123F71949B52d883aE57e225` (`5-of-8` Safe) | **PASS** |
| `AlchemistAllocator` | Delegated Operator Safe | Owned by 3-of-7 Operations Safe | `0xF56D1d4B28D37A6bEE3c1590E9930B235852293D` (`3-of-7` Safe) | **PASS** |

---

## 2. Deterministic Reproduction (`cast`)

```bash
RPC_URL="https://eth.drpc.org"
BLOCK=26400152
ALUSD_ALCHEMIST="0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd"
ALETH_ALCHEMIST="0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c"
DEV_SAFE="0x8392F6669292fA56123F71949B52d883aE57e225"

cast call $ALUSD_ALCHEMIST "admin()(address)" --block $BLOCK --rpc-url $RPC_URL
cast call $ALETH_ALCHEMIST "admin()(address)" --block $BLOCK --rpc-url $RPC_URL
cast call $DEV_SAFE "getThreshold()(uint256)" --block $BLOCK --rpc-url $RPC_URL
cast call $DEV_SAFE "getOwners()(address[])" --block $BLOCK --rpc-url $RPC_URL
```

---

## 3. Restricted Finding Notice (`AX3` — Unrevoked Legacy EOA Sentinels on `alUSD` & `alETH`)

By reconstructing all historical `SentinelSet(address, bool)` events from contract deployment through block `26400152` and cross-checking live `isSentinel(address)` state on both `AlchemistV2 (alUSD)` and `AlchemistV2 (alETH)`, we identified **3 legacy EOA addresses granted Sentinel (`pause`) authority in October 2022 that remain active (`isSentinel == true`)** on live mainnet.

To avoid exposing the 3 EOA addresses publicly while they retain live pause authority, the specific addresses and `setSentinel(eoa, false)` Gnosis Safe remediation payload are withheld from this public diff and ready for immediate handoff to the Alchemix team (`pacta@dri.network`).
