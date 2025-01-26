import { ethers, network } from "hardhat";

import { awaitAllDecryptionResults, initGateway } from "../asyncDecrypt";
import { createInstance } from "../instance";
import { getSigners, initSigners } from "../signers";
import { debug } from "../utils";

describe("Blind Auction", function () {
  before(async function () {
    await initSigners();
    this.signers = await getSigners();
    await initGateway();
  });

  beforeEach(async function () {
    // Token1 Contract
    const token1Factory = await ethers.getContractFactory("ERC20");
    this.token1 = await token1Factory.connect(this.signers.alice).deploy();
    await this.token1.waitForDeployment();
    this.token1Address = await this.token1.getAddress();

    // Auctions Contract
    const auctionFactory = await ethers.getContractFactory("BlindAuction");
    this.auction = await auctionFactory.connect(this.signers.alice).deploy(this.token1Address);
    await this.auction.waitForDeployment();
    this.auctionAddress = await this.auction.getAddress();
    this.fhevm = await createInstance();
  });

  it("Create Auction and Bid", async function () {
    const amount = await this.fhevm
      .createEncryptedInput(this.auctionAddress, this.signers.alice.address)
      .add64(10000)
      .encrypt();
    // const amount = await encypt_amt.add64(10000).encrypt();

    const amount2 = await this.fhevm
      .createEncryptedInput(this.auctionAddress, this.signers.bob.address)
      .add64(10000)
      .encrypt();

    await this.auction.createAuction("WilliBeans", 1000, 4, 100, amount.handles[0], amount.inputProof);
    await this.auction
      .connect(this.signers.bob)
      .createAuction("WilliBeans2", 1000, 4, 100, amount2.handles[0], amount2.inputProof);

    // console.log(await this.auction.getAuctions());

    // TODO! test the transfers

    // Create Bids
    const auctionID = await this.fhevm
      .createEncryptedInput(this.auctionAddress, this.signers.alice.address)
      .addAddress(this.signers.alice.address)
      .encrypt();

    const tokenRate = await this.fhevm
      .createEncryptedInput(this.auctionAddress, this.signers.alice.address)
      .add64(2)
      .encrypt();

    const tokenCount = await this.fhevm
      .createEncryptedInput(this.auctionAddress, this.signers.alice.address)
      .add64(1000)
      .encrypt();

    await this.auction.initiateBid(
      auctionID.handles[0],
      auctionID.inputProof,
      tokenRate.handles[0],
      tokenRate.inputProof,
      tokenCount.handles[0],
      tokenCount.inputProof,
    );

    await awaitAllDecryptionResults();

    console.log(await this.auction.counter_anon());
  });

  it("Decryption", async function () {
    // await this.auction.increment();
    // await this.auction.increment();
    await this.auction.connect(this.signers.carol).getCounter();
    await awaitAllDecryptionResults();

    console.log(await this.auction.counter_anon());
  });
});
