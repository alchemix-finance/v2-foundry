make test_file_block FILE=Autoleverage;
make test_file_block FILE=EthAssetManager;
make test_file_block FILE=FuseTokenAdapterV1;
make test_file_block FILE=MigrationToolETH BLOCK=14677441;
make test_file_block FILE=MigrationToolUSD BLOCK=14668199;
make test_file_block FILE=RETHAdapterV1 BLOCK=14695010;
make test_file_block FILE=ThreePoolAssetManager;
make test_file_block FILE=TransmuterConduit;
make test_file_block FILE=V2Migration BLOCK=14731227;
make test_file_block FILE=VesperAdapterV1;
make test_file_block FILE=WstETHAdapterV1;
# run invariants locally and include test results on PR
# make test_file_block FILE=InvariantsTests;
make test_file_block FILE=AAVETokenAdapter;
make test_file_block FILE=ATokenGateway;
