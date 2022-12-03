// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../core/interfaces/IWitnetPriceRouter.sol";

contract WitnetPriceRouter {
    address public gov;

    mapping(bytes4 => int256) public answers;
    mapping(address => bool) public isAdmin;

    constructor() public {
        gov = msg.sender;
        isAdmin[msg.sender] = true;
    }


    function valueFor(bytes4 _erc2362id)
        external view
        returns (
            int256 _lastPrice,
            uint256 _lastTimestamp,
            uint256 _latestUpdateStatus
        )
    {
        return (answers[_erc2362id], 0, 0);
    }

    function setAdmin(address _account, bool _isAdmin) public {
        require(msg.sender == gov, "WintnetPriceRouter: forbidden");
        isAdmin[_account] = _isAdmin;
    }


    function setLatestAnswer(bytes4 _erc2362id, int256 _answer) public {
        require(isAdmin[msg.sender], "WintnetPriceRouter: forbidden");
        answers[_erc2362id] = _answer;
    }


}
