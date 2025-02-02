import { expect } from "chai";
import { ethers, network } from "hardhat";



import { awaitAllDecryptionResults, initGateway } from "../asyncDecrypt";
import { createInstance } from "../instance";
import { getSigners, initSigners } from "../signers";
import { debug } from "../utils";


describe("Blind Auction ERC20", function () {
  before(async function () {
    await initSigners();
    this.signers = await getSigners();
    await initGateway();
  });

  beforeEach(async function () {
    // Token1 Contract
    const bitTokenFactory = await ethers.getContractFactory("ConfERC20");
    this.bidToken = await bitTokenFactory.connect(this.signers.bob).deploy();
    await this.bidToken.waitForDeployment();
    this.bidTokenAddress = await this.bidToken.getAddress();

    await this.bidToken.mint(this.signers.alice);
    await this.bidToken.mint(this.signers.carol);
    await this.bidToken.mint(this.signers.dave);
    await this.bidToken.mint(this.signers.eve);
    await this.bidToken.mint(this.signers.fred);
    await this.bidToken.mint(this.signers.greg);
    await this.bidToken.mint(this.signers.hugo);
    await this.bidToken.mint(this.signers.ian);
    await this.bidToken.mint(this.signers.jane);
    await this.bidToken.mint(this.signers.a);
    await this.bidToken.mint(this.signers.b);
    await this.bidToken.mint(this.signers.c);
    await this.bidToken.mint(this.signers.d);
    await this.bidToken.mint(this.signers.e);
    await this.bidToken.mint(this.signers.f);
    await this.bidToken.mint(this.signers.g);
    await this.bidToken.mint(this.signers.h);
    await this.bidToken.mint(this.signers.i);
    await this.bidToken.mint(this.signers.j);

    const auctionTokenFactory = await ethers.getContractFactory("NativeERC20");
    this.auctionToken = await auctionTokenFactory.connect(this.signers.alice).deploy();
    await this.auctionToken.waitForDeployment();
    this.auctionTokenAddress = await this.auctionToken.getAddress();

    // Auctions Contract
    const auctionFactory = await ethers.getContractFactory("BlindAuctionERC20");
    this.auction = await auctionFactory.connect(this.signers.alice).deploy();
    await this.auction.waitForDeployment();
    this.auctionAddress = await this.auction.getAddress();
    this.fhevm = await createInstance();
  });

  async function createAuction(this: Mocha.Context, auctionTitle: string) {
    await this.auctionToken["approve(address,uint256)"](this.auctionAddress, 1000);

    await this.auction.createAuction(this.auctionTokenAddress, this.bidTokenAddress, auctionTitle, 1000, 4, 100);
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
      .createEncryptedInput(this.bidTokenAddress, bidder.address)
      .add64(tokenrate * tokenAsked)
      .encrypt();

    await this.bidToken
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

    expect(await this.auctionToken.balanceOf(this.auctionAddress)).to.equal("1000");
  });

  it("Create Bids", async function () {
    await createAuction.call(this, "Willins".toString());
    await initiateBid.call(this, this.signers.bob, 1, 2, 200);
    await initiateBid.call(this, this.signers.carol, 1, 3, 300);
    await initiateBid.call(this, this.signers.dave, 1, 4, 400);
    await initiateBid.call(this, this.signers.eve, 1, 5, 500);
    await initiateBid.call(this, this.signers.fred, 1, 6, 600);
    await initiateBid.call(this, this.signers.greg, 1, 7, 700);
    await initiateBid.call(this, this.signers.hugo, 1, 8, 800);
    await initiateBid.call(this, this.signers.ian, 1, 9, 900);
    await initiateBid.call(this, this.signers.jane, 1, 10, 1000);

    const totalBidTokens = 2 * 200 + 3 * 300 + 4 * 400 + 5 * 500 + 6 * 600 + 7 * 700 + 8 * 800 + 9 * 900 + 10 * 1000;
    expect(await debug.decrypt64(await this.bidToken.balanceOf(this.auctionAddress))).to.equal(totalBidTokens);
  });

  it("Increse existing bid", async function () {
    await createAuction.call(this, "Willins".toString());

    await initiateBid.call(this, this.signers.carol, 1, 2, 200);

    const tokenRate = await this.fhevm
      .createEncryptedInput(this.auctionAddress, this.signers.carol.address)
      .add64(3)
      .encrypt();
    const tokenCount = await this.fhevm
      .createEncryptedInput(this.auctionAddress, this.signers.carol.address)
      .add64(300)
      .encrypt();
    const approveTokensForBid = await this.fhevm
      .createEncryptedInput(this.bidTokenAddress, this.signers.carol.address)
      .add64(500)
      .encrypt();

    await this.bidToken
      .connect(this.signers.carol)
      ["approve(address,bytes32,bytes)"](
        this.auctionAddress,
        approveTokensForBid.handles[0],
        approveTokensForBid.inputProof,
      );

    expect(await debug.decrypt64(await this.bidToken.balanceOf(this.auctionAddress))).to.equal("400");

    await this.auction
      .connect(this.signers.carol)
      .updateBidInc(1, tokenRate.handles[0], tokenRate.inputProof, tokenCount.handles[0], tokenCount.inputProof);

    expect(await debug.decrypt64(await this.bidToken.balanceOf(this.auctionAddress))).to.equal("900");
  });

  it("Decrease existing bid", async function () {
    await createAuction.call(this, "Willins".toString());

    await initiateBid.call(this, this.signers.carol, 1, 2, 200);

    const tokenRate = await this.fhevm
      .createEncryptedInput(this.auctionAddress, this.signers.carol.address)
      .add64(1)
      .encrypt();
    const tokenCount = await this.fhevm
      .createEncryptedInput(this.auctionAddress, this.signers.carol.address)
      .add64(100)
      .encrypt();

    expect(await debug.decrypt64(await this.bidToken.balanceOf(this.auctionAddress))).to.equal("400");

    await this.auction
      .connect(this.signers.carol)
      .updateBidDec(1, tokenRate.handles[0], tokenRate.inputProof, tokenCount.handles[0], tokenCount.inputProof);

    expect(await debug.decrypt64(await this.bidToken.balanceOf(this.auctionAddress))).to.equal("100");
  });

  it("reveal Bids", async function () {
    await createAuction.call(this, "Willins".toString());

    await initiateBid.call(this, this.signers.bob, 1, 2, 200);
    await initiateBid.call(this, this.signers.carol, 1, 3, 300);
    await initiateBid.call(this, this.signers.dave, 1, 4, 400);
    await initiateBid.call(this, this.signers.eve, 1, 5, 500);
    await initiateBid.call(this, this.signers.fred, 1, 6, 600);
    await initiateBid.call(this, this.signers.greg, 1, 7, 700);
    await initiateBid.call(this, this.signers.hugo, 1, 8, 800);
    await initiateBid.call(this, this.signers.ian, 1, 9, 900);
    await initiateBid.call(this, this.signers.jane, 1, 10, 1000);
    await initiateBid.call(this, this.signers.a, 1, 10, 1000);
    await initiateBid.call(this, this.signers.b, 1, 10, 1000);
    await initiateBid.call(this, this.signers.c, 1, 10, 1000);
    await initiateBid.call(this, this.signers.d, 1, 10, 1000);
    await initiateBid.call(this, this.signers.e, 1, 10, 1000);
    await initiateBid.call(this, this.signers.f, 1, 10, 1000);
    await initiateBid.call(this, this.signers.g, 1, 10, 1000);
    await initiateBid.call(this, this.signers.h, 1, 10, 1000);
    await initiateBid.call(this, this.signers.i, 1, 10, 1000);
    await initiateBid.call(this, this.signers.j, 1, 10, 1000);
    // console.log(
    //   "bidToken balance of bob before",
    //   await debug.decrypt64(await this.bidToken.balanceOf(this.signers.bob.address)),
    // );
    // console.log(
    //   "AuctionToken balance of bob before",
    //   await debug.decrypt64(await this.auctionToken.balanceOf(this.signers.bob.address)),
    // );

    // console.log(
    //   "bidToken balance of carol before",
    //   await debug.decrypt64(await this.bidToken.balanceOf(this.signers.carol.address)),
    // );
    // console.log(
    //   "AuctionToken balance of carol before",
    //   await debug.decrypt64(await this.auctionToken.balanceOf(this.signers.carol.address)),
    // );

    // console.log(
    //   "bidToken balance of contract before",
    //   await debug.decrypt64(await this.bidToken.balanceOf(this.auctionAddress)),
    // );
    // console.log(
    //   "AuctionToken balance of contract before",
    //   await debug.decrypt64(await this.auctionToken.balanceOf(this.auctionAddress)),
    // );

    // console.log(
    //   "bidToken balanced of alice before",
    //   await debug.decrypt64(await this.bidToken.balanceOf(this.signers.alice.address)),
    // );
    // console.log(
    //   "AuctionToken balanced of alice before",
    //   await debug.decrypt64(await this.auctionToken.balanceOf(this.signers.alice.address)),
    // );

    await this.auction.decryptAllbids(1);
    await awaitAllDecryptionResults();
    await this.auction.connect(this.signers.alice).revealAuction(1);

    // console.log(
    //   "bidToken balance of bob after",
    //   await debug.decrypt64(await this.bidToken.balanceOf(this.signers.bob.address)),
    // );
    // console.log(
    //   "AuctionToken balance of bob after",
    //   await debug.decrypt64(await this.auctionToken.balanceOf(this.signers.bob.address)),
    // );

    // console.log(
    //   "bidToken balance of carol after",
    //   await debug.decrypt64(await this.bidToken.balanceOf(this.signers.carol.address)),
    // );
    // console.log(
    //   "AuctionToken balance of carol after",
    //   await debug.decrypt64(await this.auctionToken.balanceOf(this.signers.carol.address)),
    // );

    // console.log(
    //   "bidToken balance of contract after",
    //   await debug.decrypt64(await this.bidToken.balanceOf(this.auctionAddress)),
    // );
    // console.log(
    //   "AuctionToken balance of contract after",
    //   await debug.decrypt64(await this.auctionToken.balanceOf(this.auctionAddress)),
    // );

    // console.log(
    //   "bidToken balanced of alice after",
    //   await debug.decrypt64(await this.bidToken.balanceOf(this.signers.alice.address)),
    // );
  });
});