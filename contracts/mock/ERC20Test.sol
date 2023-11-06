// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ERC20Test is ERC20, Ownable {
    constructor() ERC20("ERC20Test", "ET") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
