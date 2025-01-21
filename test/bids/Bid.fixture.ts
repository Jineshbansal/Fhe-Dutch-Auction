import { ethers } from "hardhat";

import type { BlindAuction } from "../../types";
import { getSigners } from "../signers";

export async function deployBidFixture(): Promise<BlindAuction> {
  const signers = await getSigners();

  const contractFactory = await ethers.getContractFactory("BlindAuction");
  console.log(contractFactory);
  const contract = await contractFactory.connect(signers.alice).deploy(); // City of Zama's battle
  await contract.waitForDeployment();

  return contract;
}
