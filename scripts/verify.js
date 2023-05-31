const hre = require("hardhat");
const args = require("./args");

module.exports = async (contractAddress) => {
  return hre.run("verify:verify", {
    address: contractAddress,
    constructorArguments: args
  })
  .catch(error => console.log(error));
    
}