import { task, types } from "hardhat/config";

import { readAddressList } from "../scripts/contractAddress";
import {
  BoosterTreasury,
  BoosterTreasury__factory,
  Gauge,
  Launchpad,
  LaunchpadToken,
  Launchpad__factory,
} from "../types";

task("createToken", "Create a new token on Launchpad").setAction(async (args, hre) => {
  const { network, ethers } = hre;

  const [dev] = await ethers.getSigners();
  const addressList = readAddressList();
  const pad: Launchpad = Launchpad__factory.connect(addressList[network.name].Launchpad, dev);

  const tokenConfig: LaunchpadToken.TokenConfigStruct = {
    name: "PEPES",
    symbol: "PEPE",
    initialSupply: ethers.parseEther("1000000000"),
  };
  const metadataConfig: LaunchpadToken.TokenMetadataConfigStruct = {
    ipfsHash:
      "https://ichef.bbci.co.uk/news/976/cpsprodpb/16620/production/_91408619_55df76d5-2245-41c1-8031-07a4da3f313f.jpg.webp",
    website: "https://www.pepethefrog.com/",
    twitter: "https://twitter.com/pepethefrog",
    telegram: "https://t.me/pepethefrog",
    description: "PEPE is a meme token",
    metadata: "",
  };
  const autoSnipConfig: Launchpad.AutoSnipeConfigStruct = {
    minAmountOut: 0,
  };
  const curveParameters: Gauge.CurveParametersStruct = {
    yMin: "51136363636",
    yMax: "56250000000",
  };
  const fractionConfig: Launchpad.FractionConfigStruct = {
    boosterFraction: ethers.parseEther("0.1"),
    bondingCurveFraction: ethers.parseEther("0.8"),
  };

  const tx = await pad.createLaunchpadToken(
    tokenConfig,
    metadataConfig,
    autoSnipConfig,
    curveParameters,
    fractionConfig,
    { value: ethers.parseEther("0.01") },
  );
  console.log("tx details:", await tx.wait());
});

task("setLaunchpad", "Set launchpad address in treasury").setAction(async (args, hre) => {
  const { network, ethers } = hre;

  const [dev] = await ethers.getSigners();
  const addressList = readAddressList();
  const treasury: BoosterTreasury = BoosterTreasury__factory.connect(addressList[network.name].BoosterTreasury, dev);

  const tx = await treasury.setLaunchpad(addressList[network.name].Launchpad);
  console.log("tx details:", await tx.wait());
});

task("get", "get info").setAction(async (args, hre) => {
  const { network, ethers } = hre;

  const [dev] = await ethers.getSigners();
  const addressList = readAddressList();
  const treasury: BoosterTreasury = BoosterTreasury__factory.connect(addressList[network.name].BoosterTreasury, dev);

  const isValidSigner = await treasury.isValidSigner(dev.address);
  console.log("isValidSigner:", isValidSigner);
});
task("setFee", "get info").setAction(async (args, hre) => {
  const { network, ethers } = hre;

  const [dev] = await ethers.getSigners();
  const addressList = readAddressList();
  const pad: Launchpad = Launchpad__factory.connect(addressList[network.name].Launchpad, dev);

  const treasury: BoosterTreasury = BoosterTreasury__factory.connect(addressList[network.name].BoosterTreasury, dev);

  const gaugeFeeParameters: Gauge.FeeParametersStruct = {
    buyFee: ethers.parseEther("0.01"),
    sellFee: ethers.parseEther("0.01"),
  };

  const tx = await pad.setGaugeFees(gaugeFeeParameters);
  console.log("tx details:", await tx.wait());
});
