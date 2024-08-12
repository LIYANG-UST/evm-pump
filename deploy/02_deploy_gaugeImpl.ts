import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { readAddressList, storeAddressList } from "../scripts/contractAddress";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;
  const { ethers, network } = hre;

  const addressList = readAddressList();

  const UNISWAPV3_POSITION_MANAGER = addressList[network.name].UNIV3_POSITION_MANAGER;
  const WETH = addressList[network.name].WETH;
  const treasuryAddress = addressList[network.name].BoosterTreasury;

  const gaugeImpl = await deploy("Gauge", {
    from: deployer,
    args: [UNISWAPV3_POSITION_MANAGER, WETH, treasuryAddress],
    log: true,
  });

  console.log(`Gauge implementation deployed to: `, gaugeImpl.address);
  addressList[network.name].Gauge = gaugeImpl.address;
  storeAddressList(addressList);
};
export default func;

func.id = "deploy_gauge_impl";
func.tags = ["Gauge"];
