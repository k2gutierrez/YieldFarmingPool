// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { ERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/**
 * @title Mock Token
 * @author Carlos Gutiérrez
 * @notice ERC20 token to test the yield farming project
 */
contract MockToken is ERC20, Ownable {
    
    constructor(string memory _name, string memory _symbol, address _owner, uint256 _initialSupply) ERC20(_name, _symbol) Ownable(_owner) {
        _mint(_owner, _initialSupply * 10**decimals());
    }

    /**
     * @dev Function to mint tokens
     * @param to Address to send minted tokens
     * @param amount amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Function to burn tokens
     * @param amount amount of tokens to burn
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

}
