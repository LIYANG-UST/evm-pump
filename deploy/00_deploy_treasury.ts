import { DeployFunction, ProxyOptions } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { readAddressList, storeAddressList } from "../scripts/contractAddress";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;
  const { ethers, network } = hre;

  const addressList = readAddressList();

  const proxyOptions: ProxyOptions = {
    proxyContract: "OpenZeppelinTransparentProxy",
    viaAdminContract: {
      name: "ProxyAdmin",
      artifact: "MyProxyAdmin",
    },
    execute: {
      init: {
        methodName: "initialize",
        args: [],
      },
    },
  };

  const treasury = await deploy("BoosterTreasury", {
    contract: "BoosterTreasury",
    proxy: proxyOptions,
    from: deployer,
    args: [],
    log: true,
  });

  console.log(`Booster treasury deployed to: `, treasury.address);

  addressList[network.name].BoosterTreasury = treasury.address;
  storeAddressList(addressList);
};
export default func;

func.id = "deploy_booster_treasury";
func.tags = ["Treasury"];
