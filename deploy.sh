#!/bin/bash

read -p "Enter func [deploy/verify/compile]: " func

if [ $func == 'deploy' ]; then
  read -p "Enter network: " network
  read -p "Enter name of contract: " name
  name=$name npx hardhat run --network $network scripts/deploy.js
elif [ $func == 'verify' ]; then
  read -p "Enter network: " network
  read -p "Enter address of the contract: " contract_address
  npx hardhat --network $network verify-cli --address $contract_address
elif [ $func == 'compile' ]; then
  npx hardhat compile
else
  echo "Invalid func!"
fi