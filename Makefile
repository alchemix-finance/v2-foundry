# shortcuts for calling common foundry commands

-include .env

# file to test 
FILE=

# specific test to run
TEST=

# block to test from 
BLOCK=14414078

# foundry test profile to run
PROFILE=$(TEST_PROFILE)

# forks from specific block 
FORK_BLOCK=--fork-block-number $(BLOCK)

# file to test
MATCH_PATH=--match-path src/test/$(FILE).t.sol

# test to run
MATCH_TEST=--match-test $(TEST)

# rpc url
FORK_URL=--fork-url https://eth-mainnet.alchemyapi.io/v2/$(ALCHEMY_API_KEY)

FORK_URL_OPTIMISM=--fork-url https://opt-mainnet.g.alchemy.com/v2/$(OPTIMISM_ALCHEMY_API_KEY)

FORK_URL_ARBITRUM=--fork-url https://arb-mainnet.g.alchemy.com/v2/$(ARBITRUM_ALCHEMY_API_KEY)

# runs all tests: "make test"
test :; FOUNDRY_PROFILE=$(PROFILE) forge test $(FORK_URL)

# runs all tests from a given block (setting block is optional): "make test_block BLOCK=14635241" 
test_block :; FOUNDRY_PROFILE=$(PROFILE) forge test $(FORK_URL) $(FORK_BLOCK)

# runs all tests with added verbosity for failing tests: "make test_debug"
test_debug :; FOUNDRY_PROFILE=$(PROFILE) forge test $(FORK_URL) -vvv

# runs specific test file: "make test_file FILE=RETHAdapterV1"
test_file :; FOUNDRY_PROFILE=$(PROFILE) forge test $(FORK_URL) $(MATCH_PATH)

# runs specific test file with added verbosity for failing tests: "make test_file_debug FILE=RETHAdapterV1"
test_file_debug :; FOUNDRY_PROFILE=$(PROFILE) forge test $(FORK_URL) $(MATCH_PATH) -vvv

# runs specific test file from a given block (setting block is optional): "make test_file_block FILE=RETHAdapterV1"
test_file_block :; FOUNDRY_PROFILE=$(PROFILE) forge test $(FORK_URL) $(MATCH_PATH) $(FORK_BLOCK)

# runs specific test file from a given block (setting block is optional): "make test_file_block_optimism FILE=RETHAdapterV1"
test_file_block_optimism :; FOUNDRY_PROFILE=$(PROFILE) forge test $(FORK_URL_OPTIMISM) $(MATCH_PATH) $(FORK_BLOCK) -vvv

# runs specific test file from a given block (setting block is optional): "make test_file_block_optimism FILE=RETHAdapterV1"
test_file_block_arbitrum :; FOUNDRY_PROFILE=$(PROFILE) forge test $(FORK_URL_ARBITRUM) $(MATCH_PATH) $(FORK_BLOCK) -vvv

# runs specific test file with added verbosity for failing tests from a given block: "make test_file_block_debug FILE=RETHAdapterV1"
test_file_block_debug :; FOUNDRY_PROFILE=$(PROFILE) forge test $(FORK_URL) $(MATCH_PATH) $(FORK_BLOCK) -vvv

# runs single test within file with added verbosity for failing test: "make test_file_debug_test FILE=RETHAdapterV1 TEST=testUnwrap"
test_file_debug_test :; FOUNDRY_PROFILE=$(PROFILE) forge test $(FORK_URL) $(MATCH_PATH) $(MATCH_TEST) -vvvvv

# runs single test within file with added verbosity for failing test from a given block: "make test_file_block_debug_test FILE=RETHAdapterV1 TEST=testUnwrap"
test_file_block_debug_test :; FOUNDRY_PROFILE=$(PROFILE) forge test $(FORK_URL) $(MATCH_PATH) $(MATCH_TEST) $(FORK_BLOCK) -vvv

alEth_pool :; FOUNDRY_PROFILE=$(PROFILE) forge test $(FORK_URL) --match-path src/scripts/rebalancer/AlEthPool.t.sol -vv --gas-limit 18446744073709551615