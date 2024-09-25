// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const { ethers, upgrades } = require("hardhat");
const { args_values } = require("./args");
const verify = require("./verify");
const contractName = "PrizetapERC20Raffle"

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function deploy() {
  const [signer] = await ethers.getSigners();

  const factory = await ethers.getContractFactory(contractName, {signer});
  const prizetap = await upgrades.deployProxy(factory, args_values);
  await prizetap.deployed();

  console.log(
    `${contractName} deployed to ${await prizetap.address}`
  );

  await sleep(20000);

  await verify(await prizetap.address, `contracts/${contractName}.sol:${contractName}`);

  console.log(`${contractName} verified successfully`)
}

async function upgrade() {
  const PRIZETAP_ADDRESS = "0x0147c481f30f4EE4F747f96a78CbcE3ef0Eb5Ed4";
  const factory = await ethers.getContractFactory(contractName);
  const prizetap = await upgrades.upgradeProxy(PRIZETAP_ADDRESS, factory);
  console.log(`${contractName} upgraded`);

  await sleep(20000);

  await verify(await prizetap.address, `contracts/${contractName}.sol:${contractName}`);

  console.log(`${contractName} verified successfully`)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
upgrade().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
