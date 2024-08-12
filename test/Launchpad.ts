import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import helpers from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";

import {
  BoosterTreasury,
  BoosterTreasury__factory,
  ConstantProductBondingCurve,
  ConstantProductBondingCurve__factory,
  Gauge,
  Gauge__factory,
  Launchpad,
  LaunchpadToken,
  LaunchpadToken__factory,
  Launchpad__factory,
  LpHolder,
  LpHolder__factory,
} from "../types";
import { getDomainStruct } from "./utils";

describe("LaunchPad Test", function () {
  let pad: Launchpad;

  let dev: SignerWithAddress, user1: SignerWithAddress, user2: SignerWithAddress, user3: SignerWithAddress;
  let feeReceiver: SignerWithAddress;

  let tokenImpl: LaunchpadToken;
  let gaugeImpl: Gauge;
  let curveImpl: ConstantProductBondingCurve;

  let lpHolder: LpHolder;
  let treasury: BoosterTreasury;

  const UNISWAPV3_POSITION_MANAGER = "0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1";
  const WETH = "0x4200000000000000000000000000000000000006";

  const snipeConfig: Launchpad.AutoSnipeConfigStruct = {
    minAmountOut: "0",
  };
  const curveParameters: Gauge.CurveParametersStruct = {
    yMin: "51136363636",
    yMax: "56250000000",
  };
  const fractionConfig: Launchpad.FractionConfigStruct = {
    boosterFraction: ethers.parseEther("0.1"),
    bondingCurveFraction: ethers.parseEther("0.8"),
  };

  beforeEach(async function () {
    [dev, user1, user2, user3, feeReceiver] = await ethers.getSigners();

    treasury = await new BoosterTreasury__factory(dev).deploy();
    await treasury.initialize();

    tokenImpl = await new LaunchpadToken__factory(dev).deploy();
    gaugeImpl = await new Gauge__factory(dev).deploy(UNISWAPV3_POSITION_MANAGER, WETH, await treasury.getAddress());
    curveImpl = await new ConstantProductBondingCurve__factory(dev).deploy();

    lpHolder = await new LpHolder__factory(dev).deploy(UNISWAPV3_POSITION_MANAGER, await treasury.getAddress());

    pad = await new Launchpad__factory(dev).deploy(
      tokenImpl,
      gaugeImpl,
      curveImpl,
      await treasury.getAddress(),
      lpHolder,
      ethers.parseEther("0.01"),
    );

    const gaugeFeeParameters: Gauge.FeeParametersStruct = {
      buyFee: ethers.parseEther("0.01"),
      sellFee: ethers.parseEther("0.01"),
    };
    await pad.setGaugeFees(gaugeFeeParameters);

    await treasury.setLaunchpad(await pad.getAddress());
  });

  describe("base test", function () {
    it("should have correct initial values", async function () {
      expect(await pad.tokenImplementation()).to.equal(await tokenImpl.getAddress());
    });
  });

  describe("launch new tokens", function () {
    it("should be able to launch a new token", async function () {
      const tokenConfig: LaunchpadToken.TokenConfigStruct = {
        name: "Test Token",
        symbol: "TT",
        initialSupply: ethers.parseEther("1000000000"),
      };
      const tokenMetadataConfig: LaunchpadToken.TokenMetadataConfigStruct = {
        ipfsHash: "",
        website: "",
        twitter: "https://twitter.com/@Yang1127LI",
        telegram: "@liynag_ust",
        description: "test",
        metadata: "sss",
      };

      // Total value: 1.01 ether
      // Creation cost: 0.01 ether
      // Auto buy token: 1 ether
      // Buy fee: 0.01 ether
      const s = await pad.createLaunchpadToken(
        tokenConfig,
        tokenMetadataConfig,
        snipeConfig,
        curveParameters,
        fractionConfig,
        {
          value: ethers.parseEther("1"),
        },
      );

      expect(await ethers.provider.getBalance(await treasury.getAddress())).to.equal(ethers.parseEther("0.0199"));
    });

    it("should be able to launch the pool", async function () {
      const tokenConfig: LaunchpadToken.TokenConfigStruct = {
        name: "Test Token",
        symbol: "TT",
        initialSupply: ethers.parseEther("1000000000"),
      };
      const tokenMetadataConfig: LaunchpadToken.TokenMetadataConfigStruct = {
        ipfsHash: "",
        website: "",
        twitter: "https://twitter.com/@Yang1127LI",
        telegram: "@liynag_ust",
        description: "test",
        metadata: "sss",
      };

      // Total value: 1.01 ether
      // Creation cost: 0.01 ether
      // Auto buy token: 1 ether
      // Buy fee: 0.01 ether
      const s = await pad.createLaunchpadToken(
        tokenConfig,
        tokenMetadataConfig,
        snipeConfig,
        curveParameters,
        fractionConfig,
        {
          value: ethers.parseEther("0.01"),
        },
      );

      const tokensList = await pad.getAllTokens();
      const newTokenAddress = tokensList[0];

      const info = await pad.getTokenInfo(newTokenAddress);
      const gaugeAddress = info.gauge;

      const newGauge = Gauge__factory.connect(gaugeAddress, dev);

      await newGauge.buyExactTokens(dev.address, ethers.parseEther("800000000"), { value: ethers.parseEther("10") });
      expect(await newGauge.gaugeClosable()).to.equal(true);

      await newGauge.launchPool();
    });

    it("should be able to buy tokens", async function () {
      const tokenConfig: LaunchpadToken.TokenConfigStruct = {
        name: "Test Token",
        symbol: "TT",
        initialSupply: ethers.parseEther("100000"),
      };
      const tokenMetadataConfig: LaunchpadToken.TokenMetadataConfigStruct = {
        ipfsHash: "",
        website: "",
        twitter: "https://twitter.com/@Yang1127LI",
        telegram: "@liynag_ust",
        description: "test",
        metadata: "sss",
      };

      // Total value: 1.01 ether
      // Creation cost: 0.01 ether
      // Auto buy token: 1 ether
      // Buy fee: 0.01 ether
      const s = await pad.createLaunchpadToken(
        tokenConfig,
        tokenMetadataConfig,
        snipeConfig,
        curveParameters,
        fractionConfig,
        {
          value: ethers.parseEther("0.01"),
        },
      );

      const tokensList = await pad.getAllTokens();
      const newTokenAddress = tokensList[0];

      const newToken = LaunchpadToken__factory.connect(newTokenAddress, dev);
      console.log("new token total supply",ethers.formatEther(await newToken.totalSupply()));

      const info = await pad.getTokenInfo(newTokenAddress);
      const gaugeAddress = info.gauge;

      const newGauge = Gauge__factory.connect(gaugeAddress, dev);

      let price = await newGauge.getCurrentPrice();
      console.log("initialPrice", ethers.formatEther(price));

      await newGauge.buyExactTokens(dev.address, ethers.parseEther("10"), { value: ethers.parseEther("10") });

      price = await newGauge.getCurrentPrice();
      console.log("price", ethers.formatEther(price));

      await newGauge.buyExactTokens(dev.address, ethers.parseEther("6000000000000"), { value: ethers.parseEther("10") });

      price = await newGauge.getCurrentPrice();
      console.log("price", ethers.formatEther(price));
    });
  });

  describe("airdrop", function () {
    it("should be able to claim airdrop", async function () {
      const tokenConfig: LaunchpadToken.TokenConfigStruct = {
        name: "Test Token",
        symbol: "TT",
        initialSupply: ethers.parseEther("1000000000"),
      };
      const tokenMetadataConfig: LaunchpadToken.TokenMetadataConfigStruct = {
        ipfsHash: "",
        website: "",
        twitter: "https://twitter.com/@Yang1127LI",
        telegram: "@liynag_ust",
        description: "test",
        metadata: "sss",
      };

      // Total value: 1.01 ether
      // Creation cost: 0.01 ether
      // Auto buy token: 1 ether
      // Buy fee: 0.01 ether
      const s = await pad.createLaunchpadToken(
        tokenConfig,
        tokenMetadataConfig,
        snipeConfig,
        curveParameters,
        fractionConfig,
        {
          value: ethers.parseEther("0.01"),
        },
      );

      const newTokenAddress = await pad.tokenNameToAddress("Test Token");
      const newToken = LaunchpadToken__factory.connect(newTokenAddress, dev);

      expect(await newToken.balanceOf(await treasury.getAddress())).to.equal(ethers.parseEther("100000000"));

      const blockNumber = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNumber);
      const blockTimestamp = block?.timestamp;

      //   const validUntil = (await helpers.time.latest()) + 10900;
      const validUntil = blockTimestamp ? blockTimestamp + 10900 : 0;
      const airdropRequestType = {
        AirdropRequest: [
          { name: "user", type: "address" },
          { name: "token", type: "address" },
          { name: "amount", type: "uint256" },
          { name: "validUntil", type: "uint256" },
        ],
      };
      const airdropRequest: BoosterTreasury.AirdropRequestStruct = {
        user: user1.address,
        amount: ethers.parseEther("10000"),
        token: newTokenAddress,
        validUntil: validUntil,
      };
      const chainId = await ethers.provider.getNetwork().then((network) => network.chainId);
      const domainStruct = getDomainStruct(Number(chainId), await treasury.getAddress());
      const signature = await dev.signTypedData(domainStruct, airdropRequestType, airdropRequest);

      expect(await treasury.isValidSigner(dev.address)).to.equal(true);

      const info = await pad.getTokenInfo(newTokenAddress);
      const gaugeAddress = info.gauge;

      const newGauge = Gauge__factory.connect(gaugeAddress, dev);

      await newGauge.buyExactTokens(dev.address, ethers.parseEther("800000000"), { value: ethers.parseEther("10") });
      expect(await newGauge.gaugeClosable()).to.equal(true);

      await newGauge.launchPool();

      await treasury.connect(user1).requestAirdrop(newTokenAddress, ethers.parseEther("10000"), validUntil, signature);

      expect(await newToken.balanceOf(user1.address)).to.equal(ethers.parseEther("10000"));
    });
  });
});
