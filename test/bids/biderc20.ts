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
    await this.bidToken.mint(this.signers.bob);
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

  async function createAuction(this: Mocha.Context, auctionTitle: string, amount: any) {
    await this.auctionToken["approve(address,uint256)"](this.auctionAddress, amount);

    await this.auction.createAuction(this.auctionTokenAddress, this.bidTokenAddress, auctionTitle, amount, 4, 100);
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
    await createAuction.call(this, "Willins".toString(), 1000);

    expect(await this.auctionToken.balanceOf(this.auctionAddress)).to.equal("1000");
  });

  it("Create Bids", async function () {
    await createAuction.call(this, "Willins".toString(), 1000);
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
    await createAuction.call(this, "Willins".toString(), 1000);

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
    await createAuction.call(this, "Willins".toString(), 1000);

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

  it("should reveal auction coorectly against 20 bids", async function () {
    await createAuction.call(this, "Ultra Large Bid".toString(), 1000);

    await initiateBid.call(this, this.signers.bob, 1, 2, 200);
    await initiateBid.call(this, this.signers.carol, 1, 3, 300);
    await initiateBid.call(this, this.signers.dave, 1, 4, 100);
    await initiateBid.call(this, this.signers.eve, 1, 5, 500);
    await initiateBid.call(this, this.signers.fred, 1, 6, 600);
    await initiateBid.call(this, this.signers.greg, 1, 7, 700);
    await initiateBid.call(this, this.signers.hugo, 1, 8, 800);
    await initiateBid.call(this, this.signers.ian, 1, 9, 900);
    await initiateBid.call(this, this.signers.jane, 1, 10, 1000);
    // await initiateBid.call(this, this.signers.a, 1, 10, 1000);
    // await initiateBid.call(this, this.signers.b, 1, 10, 1000);
    // await initiateBid.call(this, this.signers.c, 1, 10, 1000);
    // await initiateBid.call(this, this.signers.d, 1, 10, 1000);
    // await initiateBid.call(this, this.signers.e, 1, 10, 1000);
    // await initiateBid.call(this, this.signers.f, 1, 10, 1000);
    // await initiateBid.call(this, this.signers.g, 1, 10, 1000);
    // await initiateBid.call(this, this.signers.h, 1, 10, 1000);
    await initiateBid.call(this, this.signers.i, 1, 10, 1000);
    await initiateBid.call(this, this.signers.j, 1, 10, 1000);

    const totalBidTokens = 2 * 200 + 3 * 300 + 4 * 100 + 5 * 500 + 6 * 600 + 7 * 700 + 8 * 800 + 9 * 900 + 10 * 1000 +
                 10 * 1000 + 10 * 1000 + 10 * 1000 + 10 * 1000 + 10 * 1000 + 10 * 1000 + 10 * 1000 + 10 * 1000 + 10 * 1000 + 10 * 1000;
    // expect(await debug.decrypt64(await this.bidToken.balanceOf(this.auctionAddress))).to.equal(totalBidTokens);

    console.log(await debug.decrypt64(await this.bidToken.balanceOf(this.auctionAddress)));
    await this.auction.decryptAllbids(1);
    await awaitAllDecryptionResults();
    const value= await this.auction.connect(this.signers.alice).getbidslength(1);
    console.log(value);
    const value2=await this.auction.connect(this.signers.alice).getFinalPrice(1);
    console.log(value2);
    await this.auction.connect(this.signers.alice).revealAuction(1);
  });

  // it("should reveal auction correctly with 3 bidders", async function () {
  //   await createAuction.call(this, "BasicAuction".toString(), 1000);

  //   await initiateBid.call(this, this.signers.bob, 1, 2, 200);
  //   await initiateBid.call(this, this.signers.carol, 1, 3, 300);
  //   await initiateBid.call(this, this.signers.dave, 1, 4, 100);

  //   // Initial balance of the auciton contract
  //   expect(await this.auctionToken.balanceOf(this.auctionAddress)).to.equal("1000");
  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.auctionAddress))).to.equal("1700");

  //   // Bidders of the auction
  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.signers.bob))).to.equal("1009600");
  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.signers.carol))).to.equal("999100");
  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.signers.dave))).to.equal("999600");

  //   await this.auction.decryptAllbids(1);
  //   await awaitAllDecryptionResults();
  //   const value=await this.auction.connect(this.signers.alice).getbidslength(1);
  //   console.log(value);
  //   await this.auction.connect(this.signers.alice).revealAuction(1);

  //   expect(await this.auctionToken.balanceOf(this.auctionAddress)).to.equal("0");

  //   // Bidders of the auction
  //   expect(await this.auctionToken.balanceOf(this.signers.bob)).to.equal("200");
  //   expect(await this.auctionToken.balanceOf(this.signers.carol)).to.equal("300");
  //   expect(await this.auctionToken.balanceOf(this.signers.dave)).to.equal("100");

  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.signers.bob))).to.equal("1009600");
  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.signers.carol))).to.equal("999400");
  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.signers.dave))).to.equal("999800");

  //   // owner of the auction
  //   expect(await this.auctionToken.balanceOf(this.signers.alice)).to.equal("99400");
  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.signers.alice))).to.equal("1001200");

  //   // Final balance of the auction contract
  //   expect(await this.auctionToken.balanceOf(this.auctionAddress)).to.equal("0");
  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.auctionAddress))).to.equal("0");
  // });

  // it("should reveal auction correctly with 9 bidders", async function () {
  //   await createAuction.call(this, "LargeAuction".toString(), 10000);

  //   const bidders = [
  //     this.signers.bob,
  //     this.signers.carol,
  //     this.signers.dave,
  //     this.signers.eve,
  //     this.signers.fred,
  //     this.signers.greg,
  //     this.signers.hugo,
  //     this.signers.ian,
  //     this.signers.jane,
  //   ];
  //   const bidAmounts = [200, 300, 100, 500, 600, 700, 800, 900, 1000, 1100];

  //   for (let i = 0; i < bidders.length; i++) {
  //     await initiateBid.call(this, bidders[i], 1, i + 1, bidAmounts[i]);
  //   }

  //   // Initial Balance of the contract
  //   expect(await this.auctionToken.balanceOf(this.auctionAddress)).to.equal("10000");
  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.auctionAddress))).to.equal("32100");

  //   // Initial balance of the auciton owner
  //   expect(await this.auctionToken.balanceOf(this.signers.alice)).to.equal("90000");
  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.signers.alice))).to.equal("1000000");

  //   await this.auction.decryptAllbids(1);
  //   await awaitAllDecryptionResults();
  //   await this.auction.connect(this.signers.alice).revealAuction(1);

  //   // Final balance of the auction owner
  //   expect(await this.auctionToken.balanceOf(this.signers.alice)).to.equal("94900");
  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.signers.alice))).to.equal("1005100");

  //   // Final balance of the auction contract
  //   expect(await this.auctionToken.balanceOf(this.auctionAddress)).to.equal("0");
  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.auctionAddress))).to.equal("0");
  // });

  // it("should handle auction reveal when no bids are placed", async function () {
  //   await createAuction.call(this, "EmptyAuction".toString(), 1000);

  //   await this.auction.decryptAllbids(1);
  //   await awaitAllDecryptionResults();

  //   await expect(this.auction.connect(this.signers.alice).revealAuction(1)).to.be.revertedWith("No bids to reveal");
  // });

  // it("should correctly reveal auction when all bids are identical", async function () {
  //   await createAuction.call(this, "IdenticalBidsAuction".toString(), 1000);

  //   const bidders = [this.signers.bob, this.signers.carol, this.signers.dave];
  //   const bidAmount = 500;

  //   // Initiate bids for all 3 bidders
  //   for (const bidder of bidders) {
  //     await initiateBid.call(this, bidder, 1, 1, bidAmount);
  //   }

  //   // Initial balance checks
  //   expect(await this.auctionToken.balanceOf(this.auctionAddress)).to.equal("1000");
  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.auctionAddress))).to.equal("1500");

  //   // Bidders' initial bidToken balances before auction reveal
  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.signers.bob))).to.equal("1009500");
  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.signers.carol))).to.equal("999500");
  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.signers.dave))).to.equal("999500");

  //   await this.auction.decryptAllbids(1);
  //   await awaitAllDecryptionResults();
  //   await this.auction.connect(this.signers.alice).revealAuction(1);

  //   // Auction contract's auctionToken balance should now be 0
  //   expect(await this.auctionToken.balanceOf(this.auctionAddress)).to.equal("0");

  //   // Bidders' final auctionToken balances after auction reveal
  //   expect(await this.auctionToken.balanceOf(this.signers.bob)).to.equal("500");
  //   expect(await this.auctionToken.balanceOf(this.signers.carol)).to.equal("500");
  //   expect(await this.auctionToken.balanceOf(this.signers.dave)).to.equal("0");

  //   // Bidders' bidToken balances should be adjusted correctly
  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.signers.bob))).to.equal("1009500");
  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.signers.carol))).to.equal("999500");
  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.signers.dave))).to.equal("1000000");

  //   // Auction owner's balances
  //   expect(await this.auctionToken.balanceOf(this.signers.alice)).to.equal("99000");
  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.signers.alice))).to.equal("1001000");

  //   // Final balance of the auction contract
  //   expect(await this.auctionToken.balanceOf(this.auctionAddress)).to.equal("0");
  //   expect(await debug.decrypt64(await this.bidToken.balanceOf(this.auctionAddress))).to.equal("0");
  // });
});
