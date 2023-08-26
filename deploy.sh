#!/bin/bash

read -p "Enter func [deploy/verify/compile]: " func

if [ $func == 'deploy' ]; then
  read -p "Enter network: " network
  read -p "Enter name of contract: " name
  read -p "Enter salt: " salt
  name=$name salt=$salt npx hardhat run --network $network scripts/deploy.js
elif [ $func == 'verify' ]; then
  read -p "Enter network: " network
  read -p "Enter name of contract: " name
  read -p "Enter address of the contract: " contract_address
  npx hardhat --network $network verify-cli --address $contract_address --name $name
elif [ $func == 'compile' ]; then
  npx hardhat compile
else
  echo "Invalid func!"
fi