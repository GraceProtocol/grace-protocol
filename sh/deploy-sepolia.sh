#!/usr/bin/env bash

# To load the variables in the .env file
source .env

# To deploy and verify our contract
forge script script/SepoliaDeployer.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast -vvvv