// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LuaVault is Ownable {
    IERC20 lua;
    address master;
    
    constructor(IERC20 _lua, address _master) public {
        lua = _lua;
        master = _master;
    }

    function send(address _to, uint256 _amount) public {
        require(msg.sender == owner() || msg.sender == master);
        lua.transfer(_to, _amount);
    }
}