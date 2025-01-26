import { expect } from "chai";
import { ethers, network } from "hardhat";

import { getFHEGasFromTxReceipt } from "../coprocessorUtils";
import { createInstance } from "../instance";
import { getSigners, initSigners } from "../signers";
import { debug } from "../utils";
import { deployConfidentialERC20Fixture } from "./ConfidentialERC20.fixture";

describe("ConfidentialERC20:FHEGas", function () {
  before(async function () {
    await initSigners();
    this.signers = await getSigners();
  });

  beforeEach(async function () {
    // Token1 Contract
    const token1Factory = await ethers.getContractFactory("ERC20");
    this.token1 = await token1Factory.connect(this.signers.alice).deploy();
    await this.token1.waitForDeployment();
    this.token1Address = await this.token1.getAddress();

    // Auctions Contract
    const auctionFactory = await ethers.getContractFactory("MyConfidentialERC20");
    this.auction = await auctionFactory.connect(this.signers.alice).deploy(this.token1Address);
    await this.auction.waitForDeployment();
    this.auctionAddress = await this.auction.getAddress();
    this.fhevm = await createInstance();
  });

  it("receive tokens", async function () {
    // // const supply = await this.auction.createAuction("Token1", 3000, 100, 100);
    const input1 = await this.fhevm.createEncryptedInput(this.token1Address, this.signers.alice.address);
    input1.add64(10);
    const bobBidAmount = await input1.encrypt();
    const txBobApprove = await this.token1
      .connect(this.signers.alice)
      ["approve(address,bytes32,bytes)"](this.auction, bobBidAmount.handles[0], bobBidAmount.inputProof);
    await txBobApprove.wait();
    const input3 =await this.fhevm.createEncryptedInput(this.auctionAddress, this.signers.alice.address);
    input3.add64(10);
    const bobBidAmount_auction = await input3.encrypt();

    const txBobBid = await this.auction
    .receiveTokens(bobBidAmount_auction.handles[0], bobBidAmount_auction.inputProof, { gasLimit: 5000000 });
    txBobBid.wait();
    console.log(await debug.decrypt64(await this.token1.balanceOf(this.auctionAddress)));
  });
});
