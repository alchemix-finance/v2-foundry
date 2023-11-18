# `RETHAdapterV1` Properties and Proofs

## Invariant 1: Wrapping

This invariant does not apply since the `RETHAdapterV1` contract doesn't support wrapping.

## Invariant 2: Unwrapping

```solidity=
uint256 price = price();
uint256 receivedEth = unwrap(amount, recipient);
uint256 decimals = SafeERC20.expectDecimals(rETH);
assert(price * amount / 10 ** decimals == received);
```

The above code fragment describes the essential invariant of the `unwrap` function: the amount of underlying tokens returned equals the price times the amount of yield tokens given as input.

### Assumptions

The analysis below depends on the following assumptions:

* No rounding errors occur due to imprecision of fixed-point arithmetic.
* The rETH token follows the implementation from https://github.com/rocket-pool/rocketpool/blob/master/contracts/contract/token/RocketTokenRETH.sol

### Proof

Consider the following code fragment of the `unwrap` function in `RETHAdapterV1`:

```solidity=
uint256 startingEthBalance = address(this).balance;
IRETH(token).burn(amount);
uint256 receivedEth = address(this).balance - startingEthBalance;
```

We use the notation `x{1}` to denote the value of a variable or function before the call to `burn` and `x{2}` to denote the value after. `getEthValue` refers to the function of the same name in the `RocketTokenRETH` contract, while `totalEthBalance` and `rethSupply` refer to the storage locations read via the `getTotalETHBalance` and `getTotalRETHSupply` functions of the `RocketNetworkBalances` contract. Finally, `balance` refers to the ETH balance of `RETHAdapterV1`.

From the implementation of `burn`, we have that

```
balance{2} = balance{1} + getEthValue{1}(amount)
           = balance{1} + amount * totalEthBalance{1} / rethSupply{1}
           (or balance{1} + amount if rethSupply{1} = 0)

receivedEth = balance{2} - balance{1}
            = amount * totalEthBalance{1} / rethSupply{1}
           (or amount if rethSupply{1} = 0)
```

From the implementation of `price`,

```
price = getEthValue{1}(10 ** decimals)
      = 10 ** decimals * totalEthBalance{1} / rethSupply{1}
      (or 10 ** decimals if rethSupply{1} = 0)
```

Therefore,

```
price * amount / 10 ** decimals = amount * totalEthBalance{1} / rethSupply{1}
                                (or amount if rethSupply{1} = 0)
                                = receivedEth
```
