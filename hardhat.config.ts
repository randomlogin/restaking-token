import "dotenv/config";
import { HardhatUserConfig } from "hardhat/config";
import "@typechain/hardhat";
import "@nomicfoundation/hardhat-verify";
import "@openzeppelin/hardhat-upgrades";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-foundry";

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.21",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          outputSelection: {
            "*": {
              "*": ["storageLayout"],
            },
          },
        },
      },
    ],
  },
  defaultNetwork: "hardhat",
  networks: {
    localhost: {
      url: "http://localhost:8545",
        },
    hardhat: {
      chainId: 1,
      blockGasLimit: 35_000_000,
      allowUnlimitedContractSize: true,
      forking: {
       url: "https://mainnet.infura.io/v3/21610e56588b408086a53e80d43a4506",
       blockNumber: 20018451,
      }
    },
  },
  etherscan: {
    apiKey: {
      goerli: `${process.env.GOERLI_ETHERSCAN_API_KEY}`,
      mainnet: `${process.env.MAINNET_ETHERSCAN_API_KEY}`,
    },
  },
};

export default config;
