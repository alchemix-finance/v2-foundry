# shortcuts for calling common foundry commands

-include .env

# file to test 
FILE=

# specific test to run
TEST=

# block to test from 
BLOCK=13952959

# forks from specific block 
FORK_BLOCK=--fork-block-number $(BLOCK)

# file to test
MATCH_PATH=--match-path src/test/$(FILE).t.sol

# test to run
MATCH_TEST=--match-test $(TEST)

# rpc url
FORK_URL=--fork-url https://eth-mainnet.alchemyapi.io/v2/$(ALCHEMY_API_KEY)


# runs all tests: "make test"
test :; forge test $(FORK_URL)

# runs all tests from a given block (setting block is optional): "make test_block BLOCK=14635241" 
test_block :; forge test $(FORK_URL) $(FORK_BLOCK)

# runs all tests with added verbosity for failing tests: "make test_debug"
test_debug :; forge test $(FORK_URL) -vvv

# runs specific test file: "make test_file FILE=RETHAdapterV1"
test_file :; forge test $(FORK_URL) $(MATCH_PATH)

# runs specific test file with added verbosity for failing tests: "make test_file_debug FILE=RETHAdapterV1"
test_file_debug :; forge test $(FORK_URL) $(MATCH_PATH) -vvv

# runs specific test file from a given block (setting block is optional): "make test_file_block FILE=RETHAdapterV1"
test_file_block :; forge test $(FORK_URL) $(MATCH_PATH) $(FORK_BLOCK)

# runs specific test file with added verbosity for failing tests from a given block: "make test_file_block_debug FILE=RETHAdapterV1"
test_file_block_debug :; forge test $(FORK_URL) $(MATCH_PATH) $(FORK_BLOCK) -vvv

# runs single test within file with added verbosity for failing test: "make test_file_debug_test FILE=RETHAdapterV1 TEST=testUnwrap"
test_file_debug_test :; forge test $(FORK_URL) $(MATCH_PATH) $(MATCH_TEST) -vvv

# runs single test within file with added verbosity for failing test from a given block: "make test_file_block_debug_test FILE=RETHAdapterV1 TEST=testUnwrap"
test_file_block_debug_test :; forge test $(FORK_URL) $(MATCH_PATH) $(MATCH_TEST) $(FORK_BLOCK) -vvv