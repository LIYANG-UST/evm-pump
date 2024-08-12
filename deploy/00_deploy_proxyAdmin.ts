import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { readAddressList, storeAddressList } from "../scripts/contractAddress";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  console.log("\n-----------------------------------------------------------");
  console.log("-----  Network:  ", network.name);
  console.log("-----  Deployer: ", deployer);
  console.log("-----------------------------------------------------------\n");

  const balance = await hre.ethers.provider.getBalance(deployer);
  console.log("Deployer balance: ", balance.toString());

  // Read address list from local file
  const addressList = readAddressList();

  // Proxy Admin contract artifact
  const proxyAdmin = await deploy("ProxyAdmin", {
    contract: "MyProxyAdmin",
    from: deployer,
    args: [deployer],
    log: true,
  });
  addressList[network.name].ProxyAdmin = proxyAdmin.address;

  console.log("\ndeployed to address: ", proxyAdmin.address);

  // Store the address list after deployment
  storeAddressList(addressList);
};

func.tags = ["ProxyAdmin"];
export default func;
