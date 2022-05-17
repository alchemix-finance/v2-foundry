# shortcuts for calling common foundry commands

-include .env

# test params 
FILE=
TEST=
PATH=--match-path src/test/$(FILE).t.sol
TEST_PATH=--match-test $(TEST)


# runs all tests: "make test"
test :; forge test --fork-url https://eth-mainnet.alchemyapi.io/v2/$(ALCHEMY_API_KEY)

# runs all tests with added verbosity for failing tests: "make test-debug"
test-debug :; forge test --fork-url https://eth-mainnet.alchemyapi.io/v2/$(ALCHEMY_API_KEY) -vvv

# runs specific test file: "make test-file FILE=RETHAdapterV1"
test-file :; forge test --fork-url https://eth-mainnet.alchemyapi.io/v2/$(ALCHEMY_API_KEY) $(PATH)

# runs specific test file with added verbosity for failing tests: "make debug-file FILE=RETHAdapterV1"
debug-file :; forge test --fork-url https://eth-mainnet.alchemyapi.io/v2/$(ALCHEMY_API_KEY) $(PATH) -vvv

# runs single test within file with added verbosity for failing test: "make debug-test FILE=RETHAdapterV1 TEST=testUnwrap"
debug-test :; forge test --fork-url https://eth-mainnet.alchemyapi.io/v2/$(ALCHEMY_API_KEY) $(PATH) $(TEST_PATH) -vvv