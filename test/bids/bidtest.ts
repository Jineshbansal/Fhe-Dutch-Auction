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
    const auctionTokenFactory = await ethers.getContractFactory("ERC20");
    this.auctionToken = await auctionTokenFactory.connect(this.signers.alice).deploy();
    await this.auctionToken.waitForDeployment();
    this.auctionTokenAddress = await this.auctionToken.getAddress();

    // Auctions Contract
    const auctionFactory = await ethers.getContractFactory("BlindAuction");
    this.auction = await auctionFactory.connect(this.signers.alice).deploy(this.auctionTokenAddress,this.token1Address);
    await this.auction.waitForDeployment();
    this.auctionAddress = await this.auction.getAddress();
    this.fhevm = await createInstance();
  })
  it("Create Auction", async function () {
    const amount = await this.fhevm
      .createEncryptedInput(this.auctionAddress, this.signers.alice.address)
      .add64(10000)
      .encrypt();
    // const amount = await encypt_amt.add64(10000).encrypt();

    const amount2 = await this.fhevm
      .createEncryptedInput(this.auctionAddress, this.signers.bob.address)
      .add64(10000)
      .encrypt();

    const approveTokens=await this.fhevm.createEncryptedInput(this.auctionTokenAddress, this.signers.alice.address).add64(1000).encrypt();

    await this.auctionToken["approve(address,bytes32,bytes)"](this.auctionAddress,approveTokens.handles[0],approveTokens.inputProof);

    await this.auction.createAuction("WilliBeans", 1000, 4, 100);

    // console.log(await this.auction.getAuctions());
    // console.log(await debug.decrypt64(await this.auctionToken.balanceOf(this.auctionAddress)));
  });
  it("Create Bids", async function () {
    
    const amount = await this.fhevm
      .createEncryptedInput(this.auctionAddress, this.signers.alice.address)
      .add64(10000)
      .encrypt();
    // const amount = await encypt_amt.add64(10000).encrypt();

    const amount2 = await this.fhevm
      .createEncryptedInput(this.auctionAddress, this.signers.bob.address)
      .add64(10000)
      .encrypt();

    const approveTokens=await this.fhevm.createEncryptedInput(this.auctionTokenAddress, this.signers.alice.address).add64(1000).encrypt();

    await this.auctionToken["approve(address,bytes32,bytes)"](this.auctionAddress,approveTokens.handles[0],approveTokens.inputProof);

    await this.auction.createAuction("WilliBeans", 1000, 4, 100);

    const tokenRate=await this.fhevm.createEncryptedInput(this.auctionAddress, this.signers.bob.address).add64(2).encrypt();
    const tokenCount=await this.fhevm.createEncryptedInput(this.auctionAddress, this.signers.bob.address).add64(200).encrypt();
    const approveTokensForBid=await this.fhevm.createEncryptedInput(this.token1Address, this.signers.bob.address).add64(200*2).encrypt();

    await this.token1.connect(this.signers.bob)["approve(address,bytes32,bytes)"](this.auctionAddress,approveTokensForBid.handles[0],approveTokensForBid.inputProof);
    await this.auction.connect(this.signers.bob).initiateBid(this.signers.alice.address,tokenRate.handles[0],tokenRate.inputProof,tokenCount.handles[0],tokenCount.inputProof);

    // console.log(await debug.decrypt64(await this.token1.balanceOf(this.signers.bob.address)));
    // console.log(await debug.decrypt64(await this.token1.balanceOf(this.auctionAddress)));

    // console.log(await this.auction.connect(this.signers.bob).getMyBids());
    
    
  });
  it("reveal Bids", async function () {
    
    const amount = await this.fhevm
      .createEncryptedInput(this.auctionAddress, this.signers.alice.address)
      .add64(10000)
      .encrypt();
    // const amount = await encypt_amt.add64(10000).encrypt();

    const amount2 = await this.fhevm
      .createEncryptedInput(this.auctionAddress, this.signers.bob.address)
      .add64(10000)
      .encrypt();

    const approveTokens=await this.fhevm.createEncryptedInput(this.auctionTokenAddress, this.signers.alice.address).add64(1000).encrypt();

    await this.auctionToken["approve(address,bytes32,bytes)"](this.auctionAddress,approveTokens.handles[0],approveTokens.inputProof);

    await this.auction.createAuction("WilliBeans", 1000, 4, 100);

    const tokenRate=await this.fhevm.createEncryptedInput(this.auctionAddress, this.signers.bob.address).add64(2).encrypt();
    const tokenCount=await this.fhevm.createEncryptedInput(this.auctionAddress, this.signers.bob.address).add64(200).encrypt();
    const approveTokensForBid=await this.fhevm.createEncryptedInput(this.token1Address, this.signers.bob.address).add64(200*2).encrypt();

    await this.token1.connect(this.signers.bob)["approve(address,bytes32,bytes)"](this.auctionAddress,approveTokensForBid.handles[0],approveTokensForBid.inputProof);
    await this.auction.connect(this.signers.bob).initiateBid(this.signers.alice.address,tokenRate.handles[0],tokenRate.inputProof,tokenCount.handles[0],tokenCount.inputProof);

    // console.log("token1 balanced of bob before",await debug.decrypt64(await this.token1.balanceOf(this.signers.bob.address)));
    // console.log("AuctionToken balanced of bob before",await debug.decrypt64(await this.auctionToken.balanceOf(this.signers.bob.address)));
    console.log("token1 balanced of contract before",await debug.decrypt64(await this.token1.balanceOf(this.auctionAddress)));
    console.log("AuctionToken balanced of contract before",await debug.decrypt64(await this.auctionToken.balanceOf(this.auctionAddress)));
    // console.log("token1 balanced of alice before",await debug.decrypt64(await this.token1.balanceOf(this.signers.alice.address)));
    // console.log("AuctionToken balanced of alice before",await debug.decrypt64(await this.auctionToken.balanceOf(this.signers.alice.address)));
    await this.auction.connect(this.signers.alice).revealAuction(this.signers.alice);

    // console.log("token1 balanced of bob after",await debug.decrypt64(await this.token1.balanceOf(this.signers.bob.address)));
    console.log("AuctionToken balanced of bob after",await debug.decrypt64(await this.auctionToken.balanceOf(this.signers.bob.address)));
    console.log("token1 balanced of contract after",await debug.decrypt64(await this.token1.balanceOf(this.auctionAddress)));
    console.log("AuctionToken balanced of contract after",await debug.decrypt64(await this.auctionToken.balanceOf(this.auctionAddress)));
    console.log("token1 balanced of alice after",await debug.decrypt64(await this.token1.balanceOf(this.signers.alice.address)));
    console.log("AuctionToken balanced of alice after",await debug.decrypt64(await this.auctionToken.balanceOf(this.signers.alice.address)));

    
    
  });



});