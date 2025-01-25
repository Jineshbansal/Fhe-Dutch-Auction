// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";

import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { ConfidentialERC20 } from "fhevm-contracts/contracts/token/ERC20/ConfidentialERC20.sol";

contract ERC20 is SepoliaZamaFHEVMConfig, ConfidentialERC20 {
    constructor() ConfidentialERC20("OZT", "Ozark") {
        _unsafeMint(msg.sender, 1000000);
        _unsafeMint(address(this), 10000);
    }

    function mint(address to) public {
        _unsafeMint(to, 10);
    }
}
