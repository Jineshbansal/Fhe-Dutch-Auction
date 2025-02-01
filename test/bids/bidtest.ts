import { expect } from "chai";
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
    this.token1 = await token1Factory.connect(this.signers.bob).deploy();
    await this.token1.waitForDeployment();
    this.token1Address = await this.token1.getAddress();

    await this.token1.mint(this.signers.carol);
    await this.token1.mint(this.signers.alice);

    const auctionTokenFactory = await ethers.getContractFactory("ERC20");
    this.auctionToken = await auctionTokenFactory.connect(this.signers.alice).deploy();
    await this.auctionToken.waitForDeployment();
    this.auctionTokenAddress = await this.auctionToken.getAddress();

    // Auctions Contract
    const auctionFactory = await ethers.getContractFactory("BlindAuction");
    this.auction = await auctionFactory.connect(this.signers.alice).deploy();
    await this.auction.waitForDeployment();
    this.auctionAddress = await this.auction.getAddress();
    this.fhevm = await createInstance();
  });

  async function createAuction(this: Mocha.Context, auctionTitle: string) {
    const approveTokens = await this.fhevm
      .createEncryptedInput(this.auctionTokenAddress, this.signers.alice.address)
      .add64(10000)
      .encrypt();

    await this.auctionToken["approve(address,bytes32,bytes)"](
      this.auctionAddress,
      approveTokens.handles[0],
      approveTokens.inputProof,
    );

    await this.auction.createAuction(this.auctionTokenAddress, this.token1Address, auctionTitle, 1000, 4, 100);
  }

  async function initiateBid(this: Mocha.Context, bidder: any, auctionId: any, tokenrate: any, tokenAsked: any) {
    const tokenRate = await this.fhevm
      .createEncryptedInput(this.auctionAddress, bidder.address)
      .add64(tokenrate)
      .encrypt();
    const tokenCount = await this.fhevm
      .createEncryptedInput(this.auctionAddress, bidder.address)
      .add64(tokenAsked)
      .encrypt();
    const approveTokensForBid = await this.fhevm
      .createEncryptedInput(this.token1Address, bidder.address)
      .add64(tokenrate * tokenAsked)
      .encrypt();

    await this.token1
      .connect(bidder)
      ["approve(address,bytes32,bytes)"](
        this.auctionAddress,
        approveTokensForBid.handles[0],
        approveTokensForBid.inputProof,
      );
    await this.auction
      .connect(bidder)
      .initiateBid(auctionId, tokenRate.handles[0], tokenRate.inputProof, tokenCount.handles[0], tokenCount.inputProof);
  }

  it("Create Auction", async function () {
    await createAuction.call(this, "Willins".toString());

    // console.log(await this.auction.getAuctions());
    expect(await debug.decrypt64(await this.auctionToken.balanceOf(this.auctionAddress))).to.equal("1000");
  });

  it("Create Bids", async function () {
    await createAuction.call(this, "Willins".toString());

    await initiateBid.call(this, this.signers.carol, 1, 2, 200);
    await initiateBid.call(this, this.signers.bob, 1, 3, 300);
    await initiateBid.call(this, this.signers.alice, 1, 4, 400);

    expect(await debug.decrypt64(await this.token1.balanceOf(this.signers.carol.address))).to.equal("999600");
    expect(await debug.decrypt64(await this.token1.balanceOf(this.auctionAddress))).to.equal("2900");
  });

  it("reveal Bids", async function () {
    await createAuction.call(this, "Willins".toString());

    await initiateBid.call(this, this.signers.bob, 1, 2, 200);
    await initiateBid.call(this, this.signers.carol, 1, 3, 300);

    // console.log(
    //   "token1 balance of bob before",
    //   await debug.decrypt64(await this.token1.balanceOf(this.signers.bob.address)),
    // );
    // console.log(
    //   "AuctionToken balance of bob before",
    //   await debug.decrypt64(await this.auctionToken.balanceOf(this.signers.bob.address)),
    // );

    // console.log(
    //   "token1 balance of carol before",
    //   await debug.decrypt64(await this.token1.balanceOf(this.signers.carol.address)),
    // );
    // console.log(
    //   "AuctionToken balance of carol before",
    //   await debug.decrypt64(await this.auctionToken.balanceOf(this.signers.carol.address)),
    // );

    // console.log(
    //   "token1 balance of contract before",
    //   await debug.decrypt64(await this.token1.balanceOf(this.auctionAddress)),
    // );
    // console.log(
    //   "AuctionToken balance of contract before",
    //   await debug.decrypt64(await this.auctionToken.balanceOf(this.auctionAddress)),
    // );

    // console.log(
    //   "token1 balanced of alice before",
    //   await debug.decrypt64(await this.token1.balanceOf(this.signers.alice.address)),
    // );
    // console.log(
    //   "AuctionToken balanced of alice before",
    //   await debug.decrypt64(await this.auctionToken.balanceOf(this.signers.alice.address)),
    // );

    await this.auction.connect(this.signers.alice).revealAuction(1);

    // console.log(
    //   "token1 balance of bob after",
    //   await debug.decrypt64(await this.token1.balanceOf(this.signers.bob.address)),
    // );
    // console.log(
    //   "AuctionToken balance of bob after",
    //   await debug.decrypt64(await this.auctionToken.balanceOf(this.signers.bob.address)),
    // );

    // console.log(
    //   "token1 balance of carol after",
    //   await debug.decrypt64(await this.token1.balanceOf(this.signers.carol.address)),
    // );
    // console.log(
    //   "AuctionToken balance of carol after",
    //   await debug.decrypt64(await this.auctionToken.balanceOf(this.signers.carol.address)),
    // );

    // console.log(
    //   "token1 balance of contract after",
    //   await debug.decrypt64(await this.token1.balanceOf(this.auctionAddress)),
    // );
    // console.log(
    //   "AuctionToken balance of contract after",
    //   await debug.decrypt64(await this.auctionToken.balanceOf(this.auctionAddress)),
    // );

    // console.log(
    //   "token1 balanced of alice after",
    //   await debug.decrypt64(await this.token1.balanceOf(this.signers.alice.address)),
    // );
  });

  it("Increse existing bid", async function () {
    await createAuction.call(this, "Willins".toString());

    await initiateBid.call(this, this.signers.carol, 1, 2, 200);

    

  });
});
