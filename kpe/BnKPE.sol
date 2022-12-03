// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../tokens/MintableBaseToken.sol";

contract BnKPE is MintableBaseToken {
    constructor() public MintableBaseToken("Bonus KPE", "bnKPE", 0) {}

    function id() external pure returns (string memory _name) {
        return "bnKPE";
    }
}
