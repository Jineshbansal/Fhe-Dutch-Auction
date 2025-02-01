// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract NativeERC20 is ERC20 {
    uint dec = 10 ** 18;
    constructor() ERC20("BTN", "BidToken") {
        uint amount = 1000 * dec;
        _mint(msg.sender, amount);
    }

    function mint(address recipient) external {
        _mint(recipient, 1000000);
    }
}