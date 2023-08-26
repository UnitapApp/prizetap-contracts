// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const contractName = process.env.name
const { bytecode } = require(`../artifacts/contracts/${contractName}.sol/${contractName}.json`);
const { encoder, create2Address } = require("./utils.js")
const { args_abi, args_values } = require("./args");
const { UNITAP_DEPLOY_FACTORY_ABI } = require("./abi.js");
const verify = require("./verify");
const { ethers } = require("hardhat");

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

const main = async () => {
  const factoryAddr = process.env.FACTORY_ADDR;
  const saltHex = ethers.utils.id(`${process.env.salt}`);
  const initCode = bytecode + encoder(args_abi, args_values);

  const create2Addr = create2Address(factoryAddr, saltHex, initCode);
  console.log("Precomputed address:", create2Addr);

  const factory = await ethers.getContractAt(UNITAP_DEPLOY_FACTORY_ABI, factoryAddr)

  const contractDeployment = await factory.deploy(initCode, saltHex, process.env.salt);
  const txReceipt = await contractDeployment.wait();

  // const contractAddress = txReceipt.events[0].args[0];
  console.log(txReceipt.events);
  if(txReceipt.events?.length) {
    const contractAddress = create2Addr;

    console.log("Deployed to:", contractAddress);

    await sleep(10000);

    await verify(contractAddress, `contracts/${contractName}.sol:${contractName}`);
  }
};

main()
.then(() => process.exit(0))
.catch((error) => {
  console.error(error);
  process.exit(1);
});
