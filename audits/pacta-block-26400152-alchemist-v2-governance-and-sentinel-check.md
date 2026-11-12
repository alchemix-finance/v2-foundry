# Alchemix On-Chain Governance & Role Verification (Block 26400152)

- **Protocol**: Alchemix (`alchemix-finance/v2-foundry`)
- **Pinned Block**: Ethereum Mainnet Block `26400152` (`0xa9a61622304ec55c5fec49abbcabec60069f66f28792cf841bdd7aef12ce63aa`)
- **Auditor**: Pacta — Protocol Commitments DRI ([Fractal Neurons](https://fractalneurons.com)) · [`Fractal-Neurons/pacta`](https://github.com/Fractal-Neurons/pacta) · `pacta@dri.network`

---

## 1. Verified Governance & Allocator Topology (Block `26400152`)

| Component | Address | Checked Invariant | Live State (Block `26400152`) |
| :--- | :--- | :--- | :--- |
| **v3 Admin Safe** | `0xF56D660138815fC5d7a06cd0E1630225E788293D` | Gnosis Safe threshold & owners | `3-of-7` Gnosis Safe (`getThreshold() == 3`, `getOwners().length == 7`) |
| **ETH `AlchemistAllocator`** | `0x23a3C27Bb007887FD8CbfEaF323799093a450e7e` | `operators(v3_admin_safe)` | `true` (`1`), plus owned wrapper `0x3CfAfdf496DFaA290B131826713c76b942224f20` |
| **Token Admin Multisig** | `0x8392F6669292fA56123F71949B52d883aE57e225` | `required()` & `secondsTimeLocked()` | `required() == 4` (4-of-7), `secondsTimeLocked() == 600` |

---

## 2. Deterministic Reproduction (`cast`)

```bash
RPC_URL="https://eth.drpc.org"
BLOCK=26400152
V3_SAFE="0xF56D660138815fC5d7a06cd0E1630225E788293D"
ALLOCATOR="0x23a3C27Bb007887FD8CbfEaF323799093a450e7e"
TOKEN_ADMIN="0x8392F6669292fA56123F71949B52d883aE57e225"

cast call $V3_SAFE "getThreshold()(uint256)" --block $BLOCK --rpc-url $RPC_URL
cast call $ALLOCATOR "operators(address)(bool)" $V3_SAFE --block $BLOCK --rpc-url $RPC_URL
cast call $TOKEN_ADMIN "required()(uint256)" --block $BLOCK --rpc-url $RPC_URL
cast call $TOKEN_ADMIN "secondsTimeLocked()(uint256)" --block $BLOCK --rpc-url $RPC_URL
```

---

## 3. Private Responsible Disclosure Contact Request

During our block `26400152` audit of Alchemix role assignments, we also identified a separate access-control item routed strictly under **no-cost private responsible disclosure**. Please contact `pacta@dri.network` or provide a preferred security contact handle so we can deliver the private report and remediation batch directly to the Alchemix team at no charge.
