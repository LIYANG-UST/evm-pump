import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { readAddressList, storeAddressList } from "../scripts/contractAddress";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;
  const { network } = hre;

  const addressList = readAddressList();

  const tokenImpl = await deploy("LaunchpadToken", {
    from: deployer,
    args: [],
    log: true,
  });

  console.log(`Token implementation deployed to: `, tokenImpl.address);
  addressList[network.name].Token = tokenImpl.address;
  storeAddressList(addressList);
};
export default func;

func.id = "deploy_token_impl";
func.tags = ["Token"];
