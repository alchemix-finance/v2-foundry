# shortcuts for calling common foundry commands

-include .env

# test params 
FILE=
TEST=
BLOCK=14635241
BLOCK_PATH=--fork-block-number $(BLOCK)
PATH=--match-path src/test/$(FILE).t.sol
TEST_PATH=--match-test $(TEST)


# runs all tests: "make test"
test :; forge test --fork-url https://eth-mainnet.alchemyapi.io/v2/$(ALCHEMY_API_KEY)

# runs all tests from a given block (setting block is optional): "make test_block BLOCK=14635241" 
test_block :; forge test --fork-url https://eth-mainnet.alchemyapi.io/v2/$(ALCHEMY_API_KEY) --fork-block-number $(BLOCK)

# runs all tests with added verbosity for failing tests: "make test_debug"
test_debug :; forge test --fork-url https://eth-mainnet.alchemyapi.io/v2/$(ALCHEMY_API_KEY) -vvv

# runs specific test file: "make test_file FILE=RETHAdapterV1"
test_file :; forge test --fork-url https://eth-mainnet.alchemyapi.io/v2/$(ALCHEMY_API_KEY) $(PATH)

# runs specific test file with added verbosity for failing tests: "make test_file_debug FILE=RETHAdapterV1"
test_file_debug :; forge test --fork-url https://eth-mainnet.alchemyapi.io/v2/$(ALCHEMY_API_KEY) $(PATH) -vvv

# runs specific test file from a given block (setting block is optional): "make test_file_block FILE=RETHAdapterV1"
test_file_block :; forge test --fork-url https://eth-mainnet.alchemyapi.io/v2/$(ALCHEMY_API_KEY) $(PATH) $(BLOCK_PATH)

# runs specific test file with added verbosity for failing tests from a given block: "make test_file_block_debug FILE=RETHAdapterV1"
test_file_block_debug :; forge test --fork-url https://eth-mainnet.alchemyapi.io/v2/$(ALCHEMY_API_KEY) $(PATH) $(BLOCK_PATH) -vvv

# runs single test within file with added verbosity for failing test: "make test_file_debug_test FILE=RETHAdapterV1 TEST=testUnwrap"
test_file_debug_test :; forge test --fork-url https://eth-mainnet.alchemyapi.io/v2/$(ALCHEMY_API_KEY) $(PATH) $(TEST_PATH) -vvv

# runs single test within file with added verbosity for failing test from a given block: "make test_file_block_debug_test FILE=RETHAdapterV1 TEST=testUnwrap"
test_file_block_debug_test :; forge test --fork-url https://eth-mainnet.alchemyapi.io/v2/$(ALCHEMY_API_KEY) $(PATH) $(TEST_PATH) $(BLOCK_PATH) -vvv