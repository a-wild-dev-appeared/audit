// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

contract ClonableWithoutInitData is Initializable {
    uint256 public immutable val = uint256(10);

    function initialize() public initializer {}

    function fail() external pure {
        revert("This always reverts");
    }
}
