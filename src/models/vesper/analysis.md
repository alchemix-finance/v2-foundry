# Vesper

## Invariant 1: Wrapping

```solidity=
uint256 price = price();
uint256 decimals = SafeERC20.expectDecimals(vToken);
uint256 expected = amount * 10 ** decimals / price;
uint256 minted = wrap(amount, recipient);
uint256 error = expected - minted;
```

The above code fragment defines the expected amount of tokens wrapped and the error between the expected and the real amount. The following analysis has the goal of calculating the value of this error.

### Assumptions

Our analysis depends on the following assumptions:

* The vToken follows the simplified model defined in the `VToken` contract. 
* In the `VToken` contract, `totalValue() > 0`, `totalSupply() > 0`, and `totalValue() * 10 ** _underlyingToken.decimals() < totalSupply()`. This ensures that `price > 0`.

Since our analysis includes a precision analysis of the fixed-point arithmetic, we are _not_ assuming that rounding errors do not occur.

### Analysis

Consider the following code fragment from the `wrap` function of `VesperAdapterV1`:

```solidity=
uint256 balanceBefore = IERC20(token).balanceOf(address(this));

IVesperPool(token).deposit(amount);

uint256 balanceAfter = IERC20(token).balanceOf(address(this));

uint256 minted = balanceAfter - balanceBefore;
```

From the definition of `deposit`,

```
externalDepositFee = floor(amount * fee / 10 ** 4)

calculatedShares = floor((amount - externalDepositFee) * price / 10 ** 18)

balanceAfter = balanceBefore + shares
```

where `shares` is calculated as follows. First, a fee is subtracted from the deposit:

```
externalDepositFee = (amount * baseFee / 10 ** 4) - e0    (0 <= e0 < 1)

remainingAmount = amount - externalDepositFee
                = amount * (1 - baseFee / 10 ** 4) - e0
```

Then, the remaining amount is converted to shares:

```
calculatedShares = (remainingAmount * 10 ** 18 / price) - e1    (0 <= e1 < 1)
```

Finally, the implementation adjusts the number of shares in case of a division error:

1. If `remainingAmount > floor(calculatedShares * price / 10 ** 18)`, then `shares = calculatedShares + 1`.
2. Otherwise, `shares = calculatedShares`.

Equivalently, we can say that `shares = calculatedShares + d`, where `d = 0` in the first case and `d = 1` in the second. As `minted = shares`, we can calculate the error as

```
error = expected - minted
      = expected - shares
      = expected - (calculatedShares + d)
      = expected - (remainingAmount * 10 ** 18 / price) + e1 - d
      = expected - (amount * (1 - f) * 10 ** 18 / price)
                 + (e0 * 10 ** 18 / price) + e1 - d
      = (amount * 10 ** 18 / price) - (amount * 10 ** 18 / price)
                                    + (amount * f * 10 ** 18 / price)
                                    + (e0 * 10 ** 18 / price)
                                    + e1 - d
      = (amount * f * 10 ** 18 / price) + (e0 * 10 ** 18 / price) + e1 - d
```

Note that if `f = e0 = e1 = 0` and `d = 1`, then `error = -1`, indicating that `minted = expected + 1`. This is the only case when the minted amount is greater than it should.

## Invariant 2: Unwrapping

```solidity=
uint256 price = price();
uint256 decimals = SafeERC20.expectDecimals(vToken);
uint256 expected = price * amount / 10 ** decimals;
uint256 withdrawn = unwrap(amount, recipient);
uint256 error = expected - withdrawn;
```

The above code fragment defines the expected amount of tokens unwrapped and the error between the expected and the real amount. The following analysis has the goal of calculating the value of this error.

### Assumptions

Our analysis depends on the following assumptions:

* The vToken follows the simplified model defined in the `VToken` contract. 
* In the `VToken` contract, `totalValue() > 0`, `totalSupply() > 0`, and `totalValue() * 10 ** _underlyingToken.decimals() < totalSupply()`. This ensures that `price > 0`.

Since our analysis includes a precision analysis of the fixed-point arithmetic, we are _not_ assuming that rounding errors do not occur.

### Analysis

Consider the following code fragment of the `unwrap` function of `VesperAdapterV1`:

```solidity=
uint256 balanceBeforeUnderlying = IERC20(underlyingToken).balanceOf(address(this));
uint256 balanceBeforeYieldToken = IERC20(token).balanceOf(address(this));
    
IVesperPool(token).withdraw(amount);

uint256 balanceAfterUnderlying = IERC20(underlyingToken).balanceOf(address(this));
uint256 balanceAfterYieldToken = IERC20(token).balanceOf(address(this));

uint256 withdrawn = balanceAfterUnderlying - balanceBeforeUnderlying;
```

From the definition of `withdraw` in our model, we have that

```
balanceAfterUnderlying = balanceBeforeUnderlying + amountWithdrawn

balanceAfterYieldToken = balanceBeforeYieldToken - shares

withdrawn = amountWithdrawn
```

`amountWithdrawn` is defined as

```
amountWithdrawn = min(floor(amount * price / 10 ** 18), tokensHere)
```

where `tokensHere` is the maximum amount of collateral that the contract has available to withdraw. Note that the use of `floor` captures the result of Solidity's integer division. Therefore, the division error `e0 = (amount * price / 10 ** 18) - floor(amount * price / 10 ** 18)` is such that `0 <= e0 < 1`. Note that `amount * price / 10 ** 18 = expected`, so we can alternatively write `amountWithdrawn = min(expected - e0, tokensHere)`.

To calculate `shares`, we need to account for 3 different cases:

1. If `amountWithdrawn = floor(amount * price / 10 ** 18)`, then `shares = amount`. Otherwise, `amountWithdrawn = tokensHere < floor(amount * price / 10 ** 18)` and we calculate `calculatedShares = floor(amountWithdrawn * 10 ** 18 / price)`.
2. If `floor(calculatedShares * price / 10 ** 18) < amountWithdrawn` (meaning that there has been a division error), then `shares = min(amount, calculatedShares + 1)`.
3. Otherwise, `shares = min(amount, calculatedShares)`.

To facilitate the analysis, note that the implementation of `unwrap` reverts if `shares != amount`:

```solidity=
if (balanceBeforeYieldToken - balanceAfterYieldToken != amount) {
    revert IllegalState("Not all shares were burned");
}
```

Therefore, if `unwrap` doesn't revert, `shares = amount`. Using this we can calculate `error = expected - withdrawn = expected - amountWithdrawn` for each of the 3 cases.

In case (1),

```
amountWithdrawn = floor(amount * price / 10 ** 18)
                = (amount * price / 10 ** 18) - e0
                = expected - e0
                
error = expected - amountWithdrawn
      = expected - (expected - e0)
      = e0
```

In case (2), there are two separate cases. First, if `shares = calculatedShares + 1`, then

```
amount = calculatedShares + 1
amount - 1 = floor(amountWithdrawn * 10 ** 18 / price)
amount - 1 = (amountWithdrawn * 10 ** 18 / price) - e1    (0 <= e1 < 1)
amount - 1 + e1 = amountWithdrawn * 10 ** 18 / price
(amount - 1 + e1) * 10 ** 18 / price = amountWithdrawn
expected - (1 - e1) * 10 ** 18 / price = amountWithdrawn
expected - amountWithdrawn = (1 - e1) * 10 ** 18 / price
error = (1 - e1) * 10 ** 18 / price
```

Second, if `shares = amount < calculatedShares + 1`, recall first that `calculatedShares = floor(amountWithdrawn * 10 ** 18 / price)` and `amountWithdrawn = tokensHere < floor(amount * price / 10 ** 18)`. Therefore,

```
amount < calculatedShares + 1
amount < amountWithdrawn * 10 ** 18 / price
amount < (amount * price / 10 ** 18) * 10 ** 18 / price
amount < amount
```

This is a contradiction, therefore this case can never happen.

In case (3), `amountWithdrawn < floor(amount * price / 10 ** 18) <= amount * price / 10 ** 18`, and therefore `amountWithdrawn * 10 ** 18 / price < amount`. But we also have that `shares <= floor(amountWithdrawn * 10 ** 18 / price) <= amountWithdrawn * 10 ** 18 / price`. Therefore, `shares < amount` and the function always reverts in this case.

