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

### Assumptions

We use the same simplified model of the stETH token as before. In addition to the assumptions used for proving the `wrap` invariant, this analysis also depends on the assumption that the amount of ETH received from the `exchange` function of the StableSwap pool contract is always the same as the amount of stETH deposited. This assumption is captured in the `StableSwapStETH` contract, which serves as a simplified model of the pool that always exchanges ETH and stETH 1:1.

(In practice, the exchange rate of the StableSwap pool might not be exactly 1:1, and additionally a fee is deducted for every exchange. This means that the effective price when unwrapping is likely to be lower than that reported by the `price()` function. However, going through a Curve pool when unwrapping is only a temporary measure until the merge happens and withdrawing ETH from the Beacon Chain becomes possible. In the meantime, users still have some control over the amount withdrawn, as the Alchemist requires them to specify how much slippage they are willing to accept.)

### Proof

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

Since we assume that the StableSwap pool exchanges stETH for ETH at a 1:1 rate, we then have that `received = unwrappedStEth`, and therefore

```
price * amount / 10 ** decimals
	= amount * totalPooledEther / totalShares
	= unwrappedStEth
	= received
```
