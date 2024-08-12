import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { readAddressList, storeAddressList } from "../scripts/contractAddress";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;
  const { ethers, network } = hre;

  const addressList = readAddressList();

  const tokenImpl = addressList[network.name].Token;
  const gaugeImpl = addressList[network.name].Gauge;
  const curveImpl = addressList[network.name].Curve;

  const lpHolder = addressList[network.name].LPHolder;
  const treasuryAddress = addressList[network.name].BoosterTreasury;

  const creationCost = ethers.parseEther("0.001");

  const launchpad = await deploy("Launchpad", {
    contract: "Launchpad",
    from: deployer,
    args: [tokenImpl, gaugeImpl, curveImpl, treasuryAddress, lpHolder, creationCost],
    log: true,
  });

  console.log(`Launchpad deployed to: `, launchpad.address);
  addressList[network.name].Launchpad = launchpad.address;
  storeAddressList(addressList);
};
export default func;

func.id = "deploy_launchpad";
func.tags = ["Launchpad"];
