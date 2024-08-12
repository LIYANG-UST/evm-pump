import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { readAddressList, storeAddressList } from "../scripts/contractAddress";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;
  const { ethers, network } = hre;

  const addressList = readAddressList();

  const UNISWAPV3_POSITION_MANAGER = addressList[network.name].UNIV3_POSITION_MANAGER;
  const treasuryAddress = addressList[network.name].BoosterTreasury;

  const lpHolder = await deploy("LPHolder", {
    contract: "LpHolder",
    from: deployer,
    args: [UNISWAPV3_POSITION_MANAGER, treasuryAddress],
    log: true,
  });

  console.log(`Curve implementation deployed to: `, lpHolder.address);
  addressList[network.name].LPHolder = lpHolder.address;
  storeAddressList(addressList);
};
export default func;

func.id = "deploy_lp_holder";
func.tags = ["LPHolder"];
