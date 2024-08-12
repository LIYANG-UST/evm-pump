import "@nomicfoundation/hardhat-toolbox";
import "hardhat-deploy";
import type { HardhatUserConfig } from "hardhat/config";
import { vars } from "hardhat/config";
import type { NetworkUserConfig } from "hardhat/types";

import "./tasks/accounts";
import "./tasks/createToken";
import "./tasks/lock";

// Run 'npx hardhat vars setup' to see the list of variables that need to be set

const pk: string = vars.get("YOLO_YARD_DEV_PK");
const devpk: string = vars.get("SEPOLIA_DEV_PK");
const infuraApiKey: string = vars.get("INFURA_API_KEY");

const chainIds = {
  hardhat: 31337,
  mainnet: 1,
  sepolia: 11155111,
  base: 8453,
  base_sepolia: 84532,
};

function getChainConfig(chain: keyof typeof chainIds): NetworkUserConfig {
  let jsonRpcUrl: string;
  let accounts: string[] = [];

  switch (chain) {
    case "base":
      jsonRpcUrl = vars.get("TENDERLY_BASE_RPC");
      accounts = [pk];
      break;
    case "base_sepolia":
      jsonRpcUrl = vars.get("TENDERLY_BASE_SEPOLIA_RPC");
      break;
    case "sepolia":
      jsonRpcUrl = vars.get("SEPOLIA_PUB_RPC");
      accounts = [devpk];
      break;
    default:
      jsonRpcUrl = "https://" + chain + ".infura.io/v3/" + infuraApiKey;
      accounts = [pk];
  }
  return {
    accounts: accounts,
    chainId: chainIds[chain],
    url: jsonRpcUrl,
  };
}

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  namedAccounts: {
    deployer: 0,
  },
  etherscan: {
    apiKey: {
      mainnet: vars.get("ETHERSCAN_API_KEY", ""),
      sepolia: vars.get("ETHERSCAN_API_KEY", ""),
      base: vars.get("BASESCAN_API_KEY", ""),
      base_sepolia: vars.get("BASESCAN_API_KEY", ""),
    },
  },
  gasReporter: {
    currency: "USD",
    enabled: process.env.REPORT_GAS ? true : false,
    excludeContracts: [],
    src: "./contracts",
  },
  networks: {
    // Hardhat network uses base forking
    hardhat: {
      forking: {
        url: vars.get("TENDERLY_BASE_RPC"),
      },
      // accounts: [
      //   {
      //     privateKey: pk,
      //     balance: "10000000000000000000000000000",
      //   },
      // ],
    },
    mainnet: getChainConfig("mainnet"),
    sepolia: getChainConfig("sepolia"),
    base: getChainConfig("base"),
    base_sepolia: getChainConfig("base_sepolia"),
  },
  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    sources: "./contracts",
    tests: "./test",
  },
  solidity: {
    version: "0.8.25",
    settings: {
      metadata: {
        // Not including the metadata hash
        // https://github.com/paulrberg/hardhat-template/issues/31
        bytecodeHash: "none",
      },
      // Disable the optimizer when debugging
      // https://hardhat.org/hardhat-network/#solidity-optimizer-support
      optimizer: {
        enabled: true,
        runs: 800,
      },
    },
  },
  typechain: {
    outDir: "types",
    target: "ethers-v6",
  },
};

export default config;
