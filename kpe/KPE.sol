// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract KPE is ERC20 {

    constructor() ERC20("Kperp Exchange", "KPE") {
        _mint(msg.sender, 5000000 * 10 ** decimals());   
    }
}

