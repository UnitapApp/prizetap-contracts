// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
const args = require("./args");
const verify = require("./verify");
const contractName = process.env.name

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function main() {

  const factory = await hre.ethers.getContractFactory(contractName);

  const prizetapRaffle = await factory.deploy(...args);

  await prizetapRaffle.deployed();

  console.log(
    `${contractName} deployed to ${prizetapRaffle.address}`
  );

  await sleep(10000);

  await verify(prizetapRaffle.address);

  console.log(`${contractName} verified successfully`)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
