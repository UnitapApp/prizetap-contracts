require("@nomicfoundation/hardhat-toolbox");
require('dotenv').config();
const Web3 = require('web3');


const networks = {
  sepolia: {
    url: "https://rpc.ankr.com/eth_sepolia",
    chainId: 11155111,
    accounts: [process.env.PRIVATE_KEY || missing_privateKey()]
  },
  goerli: {
    url: "https://rpc.ankr.com/eth_goerli",
    chainId: 5,
    accounts: [process.env.PRIVATE_KEY || missing_privateKey()]
  },
  bscTestnet: {
    url: "https://rpc.ankr.com/bsc_testnet_chapel",
    chainId: 97,
    accounts: [process.env.PRIVATE_KEY || missing_privateKey()]
  }
}

function missing_privateKey() {
  throw Error('PrivateKey missing')
}

task("account", "returns nonce and balance for specified address on multiple networks")
  .addParam("address")
  .setAction(async taskArgs => {
    

    let resultArr  = Object.keys(networks).map(async network => {
      const config = networks[network];
      const web3 = new Web3(config['url']);

      const nonce = await web3.eth.getTransactionCount(taskArgs.address, "latest");
      const balance = await web3.eth.getBalance(taskArgs.address);

      return [
        network, 
        nonce, 
        parseFloat(web3.utils.fromWei(balance, "ether")).toFixed(2) + "ETH"
      ]

    });

    await Promise.all(resultArr).then((resultArr) => {
      resultArr.unshift(["NETWORK | NONCE | BALANCE"]);
      console.log(resultArr);
    });

  });


task("verify-cli", "verify contract on the specified network")
  .addParam("address")
  .addParam("name")
  .setAction(async taskArgs => {
    
    const verify = require("./scripts/verify");

    await verify(taskArgs.address, `contracts/${taskArgs.name}.sol:${taskArgs.name}`);

  });



module.exports = {
  defaultNetwork: "goerli",
  networks: {
    hardhat: {
    },
    ...networks
  },
  solidity: {
    version: "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 40000
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_KEY,
      sepolia: process.env.ETHERSCAN_KEY,
      goerli: process.env.ETHERSCAN_KEY,
      bscTestnet: process.env.BSCSCAN_KEY
    }
  },
}
