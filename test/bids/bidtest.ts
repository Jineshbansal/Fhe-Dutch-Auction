import { expect } from "chai";
import { getSigners, initSigners } from "../signers";
import { deployBidFixture } from "./Bid.fixture";

describe("Bids:FHEGas", function () {
  before(async function () {
    await initSigners();
    this.signers = await getSigners();
  });

  beforeEach(async function () {
    const contract = await deployBidFixture();
    // this.contractAddress = await contract.getAddress();
    // console.log(this.contractAddress);
    // this.erc20 = contract;
    // this.fhevm = await createInstance();
  });

  it("test for bids", async function () {
    console.log(this.contractAddress);
    console.log(this.erc20);
    expect(1).to.eq(1);
  });

});
