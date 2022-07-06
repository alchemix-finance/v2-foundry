# Alchemix Token Adapters

## Findings

1. (Fixed in PR [#15](https://github.com/alchemix-finance/v2-foundry/pull/15)) In the `wrap` function of the `WstETHAdapterV1`, the starting stETH balance was taken from the wstETH address rather than the stETH address. Since the starting balance is used to calculate how much stETH should be wrapped, this could cause the user to receive the wrong amount of wstETH.
2. The `unwrap` function of the `CompoundTokenAdapter` used `redeemUnderlying(amount)`, but `amount` is an amount of yield tokens rather than underlying tokens. Instead, it should use `redeem(amount)`, like the `FuseTokenAdapterV1`.
3. In the `price` function of the `FuseTokenAdapterV1`, the `LibFuse.viewExchangeRate` calculates the exchange rate with `18 + underlyingTokenDecimals - cTokenDecimals` decimals.
    * This is not a problem as long as `cTokenDecimals = underlyingTokenDecimals`, which is the case for the Fuse version of the `CErc20` token contract (see [here](https://github.com/Rari-Capital/compound-protocol/blob/5fea929e43aac2b87615b12174475921f75bb2aa/contracts/CErc20.sol)). However, in that case it would be important to check before adding a Fuse token to the Alchemist that this assumption does hold for the token.
    * The safer option is to normalize the exchange rate to `underlyingTokenDecimals` decimals. If `cTokenDecimals <= 18`, this can be done by dividing by `10 ** (18 - cTokenDecimals)`. A safer alternative that does not revert if `cTokenDecimals > 18` is to multiply by `10 ** cTokenDecimals` and then divide by `10 ** 18`.

## Caveats

### Lido

1. Effective exchange rate in `WstETHAdapterV1` when unwrapping is lower than reported price, due to going through a Curve pool (fee + exchange rate). The difference can be significant if stETH depegs. However, using a Curve pool to unwrap is a temporary measure until the merge happens, and users have control over how much slippage they are willing to accept when unwrapping.
2. If `totalPooledEther` or `totalShares` are 0 in Lido, the price reported by the `WstETHAdapterV1` returns 0, but tokens are wrapped and unwrapped using a 1:1 exchange rate.
3. If `totalPooledEther = 0` but `totalShares > 0`, and the `WstETHAdapterV1` has some previous wstETH balance (which shouldn't happen normally), wrapping will transfer this balance along with the newly-wrapped tokens to the user's CDP.

### Vesper

1. Vesper's VToken tries to compensate for rounding errors in its `_calculateShares` function by adding 1 to the result if an error is detected. However, in certain cases this adjustment can lead to the amount of yield tokens returned when wrapping to be 1 higher than the expected.
2. When wrapping, VTokens can also charge an external deposit fee as a percentage of the amount of underlying tokens wrapped. This fee is not considered when calculating the price of the token, making the effective exchange rate used for wrapping slightly lower than the reported price.
3. In general, if we ignore the fee, the actual amount of yield tokens returned when wrapping remains between `expected + 1` and `expected - (10 ** 18 / price) - 1`.
4. When unwrapping, the actual amount of underlying tokens returned remains between `expected` and `expected - (10 ** 18 / price)`.
5. For more details, see `vesper/analysis.md`.

## CToken Reentrancy Vulnerability Analysis

1. The version of Compound forked by Fuse does not always follow the checks-effects-interactions pattern, making it vulnerable to reentrancy attacks. This can be seen in Fuse's version of the `CToken` contract (deployed [here](https://etherscan.io/address/0xd77E28A1b9a9cFe1fc2EEE70E391C05d25853cbF#code)), where the `borrowFresh` function calls `doTransferOut` before updating its internal state.
2. Compound's `CEther` contract (deployed [here](https://etherscan.io/address/0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5#code)), which inherits from `CToken`, protects against reentrancy by using `transfer` to send ETH in `doTransferOut`. However, the version deployed by Fuse ([here](https://etherscan.io/address/0xd77E28A1b9a9cFe1fc2EEE70E391C05d25853cbF#code)) uses `call.value` instead, making it vulnerable.
3. When alerted earlier this year about this vulnerability, Rari Capital added a `nonReentrant` modifier to the `CToken` external functions. However, functions in the `Comptroller` contract (deployed [here](https://etherscan.io/address/0xE16DB319d9dA7Ce40b666DD2E365a4b8B3C18217#code)) were not protected, allowing the attacker to make a reentrant call to `exitMarket`.
4. As a response to the attack, a [pull request](https://github.com/Rari-Capital/compound-protocol/pull/10) has been submitted updating the `CEther` contract to use `transfer` in `doTransferOut` and updating `CToken` to use the checks-effects-interactions pattern.
5. To avoid being affected by such an attack, I would recommend only interacting with Fuse pools where the token contracts have been updated to use the new version of the `CEther` and `CToken` contracts from the above pull request.
6. Regarding Compound, the use of `transfer` protects against reentrancy when borrowing ETH. However, this vulnerability can be triggered also by ERC20 tokens with transfer hooks (e.g. ERC777). According to [this Twitter thread](https://twitter.com/Hacxyk/status/1520370421773725698) (which also provides more details on the attack), Compound governance actively avoids listing such tokens, but this should be double-checked when adding a CToken to the Alchemist.


