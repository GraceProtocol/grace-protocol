#!/usr/bin/env bash

# To load the variables in the .env file
source .env

# To deploy and verify our contract
forge script script/deploy/feeds/WstethMainnetDeployer.s.sol --rpc-url $MAINNET_RPC_URL --broadcast -vvvv --etherscan-api-key $ETHERSCAN_API_KEY --verify