const hre = require("hardhat");
const { args_values } = require("./args");

module.exports = async (contractAddress, contractName) => {
  return hre.run("verify:verify", {
    address: contractAddress,
    constructorArguments: args_values,
    contract: contractName
  })
  .catch(error => console.log(error));
    
}