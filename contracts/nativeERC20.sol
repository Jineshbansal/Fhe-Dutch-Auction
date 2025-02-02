// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract NativeERC20 is ERC20 {
    constructor() ERC20("BTN", "BidToken") {
        _mint(msg.sender, 100000);
    }

    function mint(address recipient) external {
        _mint(recipient, 1000000);
    }
}