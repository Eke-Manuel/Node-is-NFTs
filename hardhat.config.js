require("dotenv").config();

require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require("hardhat-gas-reporter");
require("solidity-coverage");
require("hardhat-deploy"); 


module.exports = {
  solidity: {
    version: "0.8.6",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
        details: {
          yul: false,
        }
      },
    },
  },
  networks: {
    RINKEBY: {
      url: process.env.RINKEBY_RPC_URL || "",
      accounts: {
        mnemonic: process.env.MNEMONIC
      }, 
      chainId: 4,
    },
    hardhat: {
    },
  },
  namedAccounts: {
    deployer:{
      default:0
    }
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  
};
