import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { readAddressList, storeAddressList } from "../scripts/contractAddress";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;
  const { ethers, network } = hre;

  const addressList = readAddressList();

  const curveImpl = await deploy("ConstantProductBondingCurve", {
    from: deployer,
    args: [],
    log: true,
  });

  console.log(`Curve implementation deployed to: `, curveImpl.address);
  addressList[network.name].Curve = curveImpl.address;
  storeAddressList(addressList);
};
export default func;

func.id = "deploy_curve_impl";
func.tags = ["Curve"];
