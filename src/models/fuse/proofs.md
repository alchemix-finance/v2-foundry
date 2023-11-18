# `FuseTokenAdapterV1` Properties and Proofs

## Assumptions

Our analysis depends on the following assumptions:

* The fToken follows the simplified model defined in the `CErc20` contract.
* No rounding errors occur due to imprecision of fixed-point arithmetic.
* No math errors due to overflow or division by zero.
* The `price` function is equivalent to the following:

```solidity=
function price() external view returns (uint256) {
    ICERC20 cToken = ICERC20(token);
    
    return LibFuse.viewExchangeRate(cToken) / 10 ** (18 - cToken.decimals());
}
```

The following analysis likewise applies to the `CompoundTokenAdapter` contract, with the additional assumptions that `decimals = 8` and `totalAdminFees = totalFuseFees = adminFee = fuseFee = 0`.

## Price Calculation

The `price` function of `FuseAdapterV1` uses the `viewExchangeRate` function from the `LibFuse` library to calculate the price. By the definition of this function, we get the equations below for the price.

* `initialExchangeRate`, `reserveFactor`, `adminFee` and `fuseFee` are the fixed values returned by `initialExchangeRateMantissa`, `reserveFactorMantissa`, `adminFeeMantissa` and `fuseFeeMantissa`, respectively.
* `decimals` is the number of decimals of the token, obtained by the getter of the same name.
* `totalCash{1}` is the balance of underlying tokens owned by the yield token contract at the time `viewExchangeRate` is called.
* `accrualBlockNumber{1}`, `totalBorrows{1}`, `totalReserves{1]`, `totalAdminFees{1}`, `totalFuseFees{1}` and `totalSupply{1}` are the values returned by the getters of the same name at the time `viewExchangeRate` is called.
* `borrowRate{1}` is the value calculated using the `getBorrowRate` function in the token's `interestRateModel` at the time `viewExchangeRate` is called.

If `totalSupply{1} = 0`,

```
price = initialExchangeRate / 10 ** (18 - decimals)
```

If `totalSupply{1} > 0` and `accrualBlockNumber{1} = block.number` (using the definition of `exchangeRateStored()` from the `CErc20` model),

```
price = (totalCash{1}
         + totalBorrows{1}
         - totalReserves{1}
         - totalAdminFees{1}
         - totalFuseFees{1})
        * 10 ** decimals / totalSupply{1}
```

If `totalSupply{1} > 0` and `accrualBlockNumber{1} != block.number`,

```
price = (totalCash{1}
         + (totalBorrows{1} + interestAccumulated)
         - (totalReserves{1} + reserveFactor * interestAccumulated / 10 ** 18)
         - (totalAdminFees{1} + adminFee * interestAccumulated / 10 ** 18)
         - (totalFuseFees{1} + fuseFee * interestAccumulated / 10 ** 18))
        * 10 ** decimals / totalSupply{1}
        
interestAccumulated = borrowRate{1}
                      * (block.number - accrualBlockNumber{1})
                      * totalBorrows{1}
                      / 10 ** 18
```

## Invariant 1: Wrapping

```solidity=
uint256 price = price();
uint256 mintedAmount = wrap(amount, recipient);
uint256 decimals = SafeERC20.expectDecimals(token);
assert(price * mintedAmount / 10 ** decimals == amount);
```

The above code fragment describes the essential invariant of the `wrap` function: the amount of yield tokens returned times the price of the yield token equals the amount of underlying tokens passed as input.

Consider the following code fragment from the `wrap` function of `FuseAdapterV1`:

```solidity=
uint256 startingBalance = IERC20(token).balanceOf(address(this));

uint256 error;
if ((error = ICERC20(token).mint(amount)) != NO_ERROR) {
    revert FuseError(error);
}

uint256 endingBalance = IERC20(token).balanceOf(address(this));
uint256 mintedAmount = endingBalance - startingBalance;
```

We use `balance` to denote the fToken balance of the adapter contract, `x{1}` to denote value `x` before calling `mint` and `x{2}` to denote the value after. Then, we have the following:

```
startingBalance = balance{1}

endingBalance = balance{2}

mintedAmount = balance{2} - balance{1}
```

Following the definition of the `mint` function in the `CErc20` model, the function starts by calling `accrueInterest`. After the call, if `accrualBlockNumber{1} != block.number`,

```
accrualBlockNumber{2} = block.number

borrowIndex{2} = borrowIndex{1} + simpleInterestFactor * borrowIndex{1} / 10 ** 18

simpleInterestFactor = borrowRate{1} * (block.number - accrualBlockNumber{1})

totalBorrows{2} = totalBorrows{1} + interestAccumulated

totalReserves{2} = totalReserves{1}
                   + reserveFactor * interestAccumulated / 10 ** 18

totalFuseFees{2} = totalFuseFees{1} + fuseFee * interestAccumulated / 10 ** 18

totalAdminFees{2} = totalAdminFees{1} + adminFee * interestAccumulated / 10 ** 18
```

Otherwise, if `accrualBlockNumber{1} = block.number`, then

```
accrualBlockNumber{2} = accrualBlockNumber{1}

borrowIndex{2} = borrowIndex{1}

totalBorrows{2} = totalBorrows{1}

totalReserves{2} = totalReserves{1}

totalFuseFees{2} = totalFuseFees{1}

totalAdminFees{2} = totalAdminFees{1}
```

Then, by the definition of `mint` in the `CErc20` model,

```
balance{2} = balance{1} + mintTokens

totalSupply{2} = totalSupply{1} + mintTokens

mintTokens = actualMintAmount * 10 ** 18 / exchangeRate
```

Since `mintedAmount = balance{2} - balance{1}`, `mintedAmount = mintTokens`. To calculate this value, we need the definition of `actualMintAmount` and `exchangeRate` according to the model.

Assuming that the underlying token has no transfer fee,

```
actualMintAmount = amount
```

For `exchangeRate`, if `totalSupply{1} = 0`,

```
exchangeRate = initialExchangeRate
```

If `totalSupply{1} > 0`,

```
exchangeRate = (totalCash{1}
                + totalBorrows{2}
                - totalReserves{2}
                - totalFuseFees{2}
                - totalAdminFees{2})
               * 10 ** 18 / totalSupply{1}
```

We now show that `mintedAmount` equals the expected value `expected = amount * 10 ** decimals / price`. We consider three cases, using the definition of `price` given in the [Price Calculation](#price-calculation) section.

If `totalSupply{1} = 0`,

```
expected = amount * 10 ** decimals * 10 ** (18 - decimals) / initialExchangeRate
         = amount * 10 ** 18 / initialExchangeRate

mintTokens = amount * 10 ** 18 / initialExchangeRate
```

If `totalSupply{1} > 0` and `accrualBlockNumber{1} = block.number`,

```
expected = amount * totalSupply{1} /
           (totalCash{1}
            + totalBorrows{1}
            - totalReserves{1}
            - totalAdminFees{1}
            - totalFuseFees{1})

mintTokens = amount * totalSupply{1} / 
             (totalCash{1}
              + totalBorrows{2}
              - totalReserves{2}
              - totalAdminFees{2}
              - totalFuseFees{2})
           = amount * totalSupply{1} / 
             (totalCash{1}
              + totalBorrows{1}
              - totalReserves{1}
              - totalAdminFees{1}
              - totalFuseFees{1})
```

If `totalSupply{1} > 0` and `accrualBlockNumber{1} != block.number`,

```
expected = amount * totalSupply{1} /
           (totalCash{1}
            + (totalBorrows{1} + interestAccumulated)
            - (totalReserves{1} + reserveFactor * interestAccumulated / 10 ** 18)
            - (totalAdminFees{1} + adminFee * interestAccumulated / 10 ** 18)
            - (totalFuseFees{1} + fuseFee * interestAccumulated / 10 ** 18))
           
mintTokens = amount * 10 ** 18 / exchangeRate
           = amount * totalSupply{1} /
             (totalCash{1}
              + totalBorrows{2}
              - totalReserves{2}
              - totalFuseFees{2}
              - totalAdminFees{2})
           = amount * totalSupply{1} /
             (totalCash{1}
              + (totalBorrows{1} + interestAccumulated)
              - (totalReserves{1} + reserveFactor * interestAccumulated / 10 ** 18)
              - (totalFuseFees{1} + fuseFee * interestAccumulated / 10 ** 18)
              - (totalAdminFees{1} + adminFee * interestAccumulated / 10 ** 18))
```

## Invariant 2: Unwrapping

```solidity=
uint256 price = price();
uint256 redeemedAmount = unwrap(amount, recipient);
uint256 decimals = SafeERC20.expectDecimals(token);
assert(price * amount / 10 ** decimals == received);
```

The above code fragment describes the essential invariant of the `unwrap` function: the amount of underlying tokens returned equals the price times the amount of yield tokens given as input.

Consider the following code fragment from the `wrap` function of `FuseAdapterV1`:

```solidity=
uint256 startingBalance = IERC20(underlyingToken).balanceOf(address(this));

uint256 error;
if ((error = ICERC20(token).redeem(amount)) != NO_ERROR) {
    revert FuseError(error);
}

uint256 endingBalance = IERC20(underlyingToken).balanceOf(address(this));
uint256 redeemedAmount = endingBalance - startingBalance;
```

Denoting by `underlyingBalance` the underlying token balance of the adapter contract, we have that

```
startingBalance = underlyingBalance{1}

endingBalance = underlyingBalance{2}

redeemedAmount = underlyingBalance{2} - underlyingBalance{1}
```

From the definition of `redeem` in the `CErc20` model, and again assuming no transfer fees in the underlying token,

```
underlyingBalance{2} = underlyingBalance{1} + exchangeRate * amount / 10 ** 18
```

where `exchangeRate` is calculated as in the `wrap` case, after calling `accrueInterest`.

We now show that `redeemedAmount = underlyingBalance{2} - underlyingBalance{1} = exchangeRate * amount / 10 ** 18` equals the expected result `xpected = price * amount / 10 ** decimals`, using the definition of `price` from the [Price Calculation](#price-calculation) section.

If `totalSupply{1} = 0`,

```
expected = initialExchangeRate * amount / 10 ** 18

redeemedAmount = exchangeRate * amount / 10 ** 18
               = initialExchangeRate * amount / 10 ** 18
```

If `totalSupply{1} > 0` and `accrualBlockNumber{1} = block.number`,

```
expected = (totalCash{1}
            + totalBorrows{1}
            - totalReserves{1}
            - totalAdminFees{1}
            - totalFuseFees{1})
           * amount / totalSupply{1}
           
redeemedAmount = exchangeRate * amount / 10 ** 18
               = (totalCash{1}
                  + totalBorrows{2}
                  - totalReserves{2}
                  - totalFuseFees{2}
                  - totalAdminFees{2})
                 * amount / totalSupply{1}
               = (totalCash{1}
                  + totalBorrows{1}
                  - totalReserves{1}
                  - totalFuseFees{1}
                  - totalAdminFees{1})
                 * amount / totalSupply{1}
```

If `totalSupply{1} > 0` and `accrualBlockNumber{1} != block.number`,

```
expected = (totalCash{1}
            + (totalBorrows{1} + interestAccumulated)
            - (totalReserves{1} + reserveFactor * interestAccumulated / 10 ** 18)
            - (totalAdminFees{1} + adminFee * interestAccumulated / 10 ** 18)
            - (totalFuseFees{1} + fuseFee * interestAccumulated / 10 ** 18))
           * amount / totalSupply{1}
           
redeemedAmount = exchangeRate * amount / 10 ** 18
               = (totalCash{1}
                  + totalBorrows{2}
                  - totalReserves{2}
                  - totalFuseFees{2}
                  - totalAdminFees{2})
                 * amount / totalSupply{1}
               = (totalCash{1}
                  + (totalBorrows{1} + interestAccumulated)
                  - (totalReserves{1} + reserveFactor * interestAccumulated / 10 ** 18)
                  - (totalFuseFees{1} + fuseFee * interestAccumulated / 10 ** 18)
                  - (totalAdminFees{1} + adminFee * interestAccumulated / 10 ** 18))
                 * amount / totalSupply{1}
```
