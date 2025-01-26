// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";
import { ConfidentialERC20 } from "fhevm-contracts/contracts/token/ERC20/ConfidentialERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "fhevm/config/ZamaFHEVMConfig.sol";
import "fhevm/config/ZamaGatewayConfig.sol";
import "fhevm/gateway/GatewayCaller.sol";
import "./ERC20.sol";

contract MyConfidentialERC20 is SepoliaZamaFHEVMConfig, SepoliaZamaGatewayConfig, GatewayCaller {
    address public tokenAddress;

    constructor(address _tokenAddress) {
        // Set the address of the confidential ERC20 token
        tokenAddress = _tokenAddress;
    }

    function receiveTokens(einput encryptedAmount, bytes calldata inputProof) public {
        // Get the ConfidentialERC20 interface
        ERC20 confidentialToken = ERC20(tokenAddress);
        euint64 value = TFHE.asEuint64(encryptedAmount, inputProof);
        // Transfer the encrypted amount to this contract
        TFHE.allowTransient(value, tokenAddress);
        require(
            confidentialToken.transferFrom(msg.sender, address(this), value),
            "Transfer failed"
        );
    }
}
