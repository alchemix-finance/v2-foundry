# `WstETHAdapterV1` Properties and Proofs

## Invariant 1: Wrapping

```solidity=
uint256 price = price();
uint256 mintedWstEth = wrap(amount, recipient);
uint256 decimals = SafeERC20.expectDecimals(wstETH);
assert(price * mintedWstEth / 10 ** decimals == amount);
```

The above code fragment describes the essential invariant of the `wrap` function: the amount of yield tokens returned times the price of the yield token equals the amount of underlying tokens passed as input.

### Assumptions

We use the `StETH` contract as a simplified model of the stETH token. Assuming the correctness of the model, we prove that the invariant holds for the `WstETHAdapterV1` contract. Our analysis also depends on the following assumptions:

* No rounding errors occur due to imprecision of fixed-point arithmetic.
* In the `StETH` contract, `totalShares = 0` if and only if `totalPooledEther = 0`.
* The wstETH token follows the implementation from https://github.com/lidofinance/lido-dao/blob/master/contracts/0.6.12/WstETH.sol
* The wETH token follows the implementation from https://github.com/gnosis/canonical-weth/blob/master/contracts/WETH9.sol

### Proof

Consider the following code fragment from the `wrap` function in `WstETHAdapterV1`:

```solidity=
uint256 startingStEthBalance = IERC20(parentToken).balanceOf(address(this));

IStETH(parentToken).submit{value: amount}(referral);

uint256 mintedStEth =
    IERC20(parentToken).balanceOf(address(this)) - startingStEthBalance;
```

We use the notation `x{1}` to denote the value of a variable or function before the call to `submit` and `x{2}` to denote the value after. `getSharesByPooledEth`, `getPooledEthByShares`, `totalShares` and `totalPooledEther` refer to the functions and variables of the same name in the `StETH` contract.

Let `shares` denote the number of shares of the adapter in the `StETH` contract. By the definition of `submit` in our model of the `StETH` contract,

```
shares{2} = shares{1} + getSharesByPooledEth{1}(amount)
          = shares{1} + amount * totalShares{1} / totalPooledEther{1}
          
totalPooledEther{2} = totalPooledEther{1} + amount
          
totalShares{2} = totalShares{1} + getSharesByPooledEth{1}(amount)
               = totalShares{1} + amount * totalShares{1} / totalPooledEther{1}
               = (totalShares{1} * totalPooledEther{1} / totalPooledEther{1})
                 + (amount * totalShares{1} / totalPooledEther{1})
               = (totalPooledEther{1} + amount)
                 * totalShares{1} / totalPooledEther{1}
               = totalPooledEther{2} * totalShares{1} / totalPooledEther{1}
```

Note that the ratio between `totalPooledEther` and `totalShares` remains the same, therefore from here on out we will write `totalPooledEther / totalShares` or `totalShares / totalPooledEther` without a numerical index.

(Obs.: For the purpose of calculating this ratio, we consider that `0 / 0 = 1`. Since we assume that `totalShares = 0` if and only if `totalPooledEther = 0`, this handles the only possible cases of division by zero. This is also consistent with the implementation in our model of the `StETH` contract.)

Let `balance` denote the balance of the adapter in the `StETH` contract. By the definition of `balanceOf` in our model of the `StETH` contract,

```
balance{i} = getPooledEthByShares{i}(shares{i})
           = shares{i} * totalPooledEther / totalShares
```

Then,

```
mintedStEth = balance{2} - balance{1}
            = (shares{2} - shares{1}) * totalPooledEther / totalShares
            = amount * (totalShares / totalPooledEther)
                     * (totalPooledEther / totalShares)
            = amount
```

Finally, the output `mintedWstEth` is computed using the `wrap` function from the `WstETH` contract. From the implementation of the contract we have

```
mintedWstEth = getPooledEthByShares(mintedStEth)
             = mintedStEth * totalShares / totalPooledEther
             = amount * totalShares / totalPooledEther
```

Given the implementation of `price` in the adapter,

```
price = getStETHByWstETH(10 ** decimals)
      = getPooledEthByShares(10 ** decimals)
      = (10 ** decimals) * totalPooledEther / totalShares
```

and therefore

```
price * mintedWstEth / 10 ** decimals = amount
```

## Invariant 2: Unwrapping

```solidity=
uint256 price = price();
uint256 received = unwrap(amount, recipient);
uint256 decimals = SafeERC20.expectDecimals(token);
assert(price * amount / 10 ** decimals == received);
```

The above code fragment describes the essential invariant of the `unwrap` function: the amount of underlying tokens returned equals the price times the amount of yield tokens given as input.

However, this invariant does not hold hold exactly for the present version of the `WstETHAdapterV1` contract. This is because, since withdrawing ETH from the Beacon Chain is not possible at the moment, unwrapping has to go through a Curve pool to exchange stETH for ETH. Therefore, the unwrapped amount is affected by both the exchange rate of the pool and the fees. Our analysis will therefore focus on calculating the multiplicative and additive errors of the result:

```
expected = price * amount / 10 ** decimals

mulError = received / expected

addError = received - expected
```

Note that since the Alchemist requires that users specify the minimum amount that they are willing to accept from unwrapping, users have some protection against unknowingly being hit with an error that is too large. Also note that after the merge happens and withdrawing ETH from the Beacon Chain becomes possible, it is expected that `unwrap` will be updated so that it no longer needs to rely on the Curve pool.

### Assumptions

We use the same simplified model of the stETH token and make the same assumptions as for the `wrap case. In addition, we also assume that the behavior of the StableSwap pool is captured by the simplified model provided in the `StableSwapStETH` contract. The contract models the exchange rate between stETH and ETH by a fixed rate, rather than using the StableSwap invariant. In practice, the exchange rate will vary depending on the current amount of ETH and stETH in the pool, as well as the amount being exchanged, but is expected to remain close to 1. We also assume that the pool always has enough funds to perform the exchange.

### Analysis

Consider the following code fragment of the `unwrap` function in `WstETHAdapterV1`:

```solidity=
uint256 startingStEthBalance = IStETH(parentToken).balanceOf(address(this));
IWstETH(token).unwrap(amount);
uint256 endingStEthBalance = IStETH(parentToken).balanceOf(address(this));

uint256 unwrappedStEth = endingStEthBalance - startingStEthBalance;
```

Similar to before, let `x{1}` be the value of a variable or function before calling the `unwrap` function of the `WstETH` contract, and `x{2}` the value after. From the implementation of this function and our `StETH` model, we have that

```
shares{2} = shares{1} + getSharesByPooledEth(getPooledEthByShares(amount))
          = shares{1} + getPooledEthByShares(amount) * totalShares / totalPooledEther
          = shares{1} + amount * (totalPooledEther / totalShares) * (totalShares / totalPooledEther)
          = shares{1} + amount
```

Note that `totalShares` and `totalPooledEther` are not affected, therefore the exchange rate again remains constant. We can then calculate the value of `unwrappedStEth` as

```
balance{i} = getPooledEthByShares(shares{i})
           = shares{i} * totalPooledEther / totalShares
         
unwrappedStEth = balance{2} - balance{1}
               = (shares{2} - shares{1}) * totalPooledEther / totalShares
               = amount * totalPooledEther / totalShares
```

Then, from the implementation of `exchange` in our model of the StableSwap pool,

```
received = (unwrappedStEth * exchangeRate / 10 ** 18) -
           (unwrappedStEth * exchangeRate / 10 ** 18) * (fee / 10 ** 18)
```

For simplicity, denote `exchangeRate / 10 ** 18` by `e` and `fee / 10 ** 18` by `f`. Then,

```
received = unwrappedStEth * e * (1 - f)
```

The expected amount of ETH based on the price reported by the adapter is

```
price * amount / 10 ** decimals
	= amount * totalPooledEther / totalShares
	= unwrappedStEth
```

Therefore, we can calculate the multiplicative and additive error as

```
mulError = received / unwrappedStEth
         = e * (1 - f)

addError = received - unwrappedStEth
         = unwrappedStEth * e * (1 - f) - unwrappedStEth
		 = unwrappedStEth * (e - e * f - 1)
```

Naturally, if `e = 1` and `f = 0`, then `mulError = 1` and `addError = 0`. In that case, `received = unwrappedStEth` and the invariant holds. More generally, this will be the case whenever `e * f = e - 1`.
