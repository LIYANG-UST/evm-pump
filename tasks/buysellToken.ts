import { task, types } from "hardhat/config";

import { readAddressList } from "../scripts/contractAddress";
import { Gauge, Launchpad, LaunchpadToken, Launchpad__factory } from "../types";

const zeroAddress = "0x000000000000000000000";

task("buyExactETH", "Buy exact eth for a token")
  .addParam("token", "Token address", zeroAddress, types.string)
  .addParam("amount", "Amount of eth to spend", "0", types.string)
  .addParam("minAmountOut", "Minimum amount of token to receive", "0", types.string)
  .setAction(async (args, hre) => {
    const { network, ethers } = hre;

    const [dev] = await ethers.getSigners();
    const addressList = readAddressList();
    const pad: Launchpad = Launchpad__factory.connect(addressList[network.name].Launchpad, dev);

    const tx = await pad.buyExactEth(args.token, args.minAmountOut, { value: ethers.parseEther(args.amount) });
    console.log("tx details:", await tx.wait());
  });
