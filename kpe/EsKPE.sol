// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../tokens/MintableBaseToken.sol";

contract EsKPE is MintableBaseToken {
    constructor() public MintableBaseToken("Escrowed KPE", "esKPE", 0) {}

    function id() external pure returns (string memory _name) {
        return "esKPE";
    }
}
