import { ethers, network } from "hardhat";

import { createInstance } from "../instance";
import { getSigners, initSigners } from "../signers";
import { debug } from "../utils";

describe("Blind Auction", function () {
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
    const auctionFactory = await ethers.getContractFactory("BlindAuction");
    this.auction = await auctionFactory.connect(this.signers.alice).deploy(this.token1Address);
    await this.auction.waitForDeployment();
    this.auctionAddress = await this.auction.getAddress();
    this.fhevm = await createInstance();
  });

  it("Create Auction", async function () {
    // const supply = await this.auction.createAuction("Token1", 3000, 100, 100);
    const encypt_amt = await this.fhevm.createEncryptedInput(this.auctionAddress, this.signers.alice.address);
    encypt_amt.add64(10000);
    const amount = await encypt_amt.encrypt();

    await this.auction.createAuction("Token1", 1000, 4, 100, amount.handles[0], amount.inputProof);
    console.log(await debug.decrypt64(await this.token1.balanceOf(this.auctionAddress)));
  });

  it("Decryption", async function() {
    console.log()
  })
});
