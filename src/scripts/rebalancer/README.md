## alETH Pool Calculator Instructions

clone repo

create .env file from .env.example

install [**Foundry**](https://book.getfoundry.sh/getting-started/installation) if not installed:

```sh
curl -L https://foundry.paradigm.xyz | bash
```

```sh
foundryup
```

install submodules

```sh
git submodule update --init --recursive
```

install dependencies

```sh
forge install
```

set desired exchange rate in AlEthPool.t.sol on line 39 (default is 99111)

run the following script within v2-foundry to see results:

```sh
make alEth_pool
```

the results will display the amount of alETH or ETH that needs to be added or removed to achieve the desired exchange rate. If the elixir does not have a sufficient account balance or pool position the "updated dy" will reflect the exchange rate if the maximum amount of elixir funds are used.

## Example

if your desired exchange rate is 99999 alETH/ETH and the results from the script are "alEth liquidity change in eth: -18646" and "ETH liquidity change in eth: 19382" then 18646 alETH needs to be REMOVED from the pool OR 19382 ETH needs to be ADDED to the pool to achieve an exchange rate of 99999.
