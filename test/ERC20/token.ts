import { expect } from "chai";
import { ethers, network } from "hardhat";

import { createInstance } from "../instance";
import { getSigners, initSigners } from "../signers";
import { debug } from "../utils";

describe("Ecrypted ERC20", function () {
  before(async function () {
    await initSigners();
    this.signers = await getSigners();
  });

  beforeEach(async function () {
    this.fhevm = await createInstance();
    const contractFactory = await ethers.getContractFactory("ERC20");
    this.contract = await contractFactory.connect(this.signers.alice).deploy();
    await this.contract.waitForDeployment();
    this.contractAddress = await this.contract.getAddress();
  });

  it("Mints correctly", async function () {
    const balance: bigint = await this.contract.balanceOf(this.signers.alice);
    console.log(balance);
    console.log(await debug.decrypt64(balance));
  });

  it("Transfers correctly", async function () {
    const encypt_amt = await this.fhevm.createEncryptedInput(this.contractAddress, this.signers.alice.address);
    encypt_amt.add64(1000);
    const amount = await encypt_amt.encrypt();

    await this.contract["transfer(address,bytes32,bytes)"](this.signers.carol, amount.handles[0], amount.inputProof);
    console.log(await debug.decrypt64(await this.contract.balanceOf(this.signers.carol)));
  });

  it("Transfers from correctly", async function () {
    const encypt_amt = await this.fhevm.createEncryptedInput(this.contractAddress, this.signers.alice.address);
    encypt_amt.add64(1000);
    const amount = await encypt_amt.encrypt();

    await this.contract["approve(address,bytes32,bytes)"](this.signers.bob, amount.handles[0], amount.inputProof);
    console.log(await debug.decrypt64(await this.contract.allowance(this.signers.alice, this.signers.bob)));

    const encypt_amt_bob = await this.fhevm.createEncryptedInput(this.contractAddress, this.signers.bob.address);
    encypt_amt_bob.add64(1000);
    const amount_bob = await encypt_amt_bob.encrypt();

    const tx = await this.contract
      .connect(this.signers.bob)
      ["transferFrom(address,address,bytes32,bytes)"](
        this.signers.alice,
        this.signers.carol,
        amount_bob.handles[0],
        amount_bob.inputProof,
      );

    await tx.wait();

    console.log(await debug.decrypt64(await this.contract.balanceOf(this.signers.carol)));
  });
});
