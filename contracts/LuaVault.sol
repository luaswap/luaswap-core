// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0 <0.8.0;


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LuaVault is Ownable {
    IERC20 public lua;
    address public master;
    
    constructor(IERC20 _lua) public {
        lua = _lua;
    }

    function setMaster(address _master) public onlyOwner {
        master = _master;
    }

    function send(address _to, uint256 _amount) public {
        require(msg.sender == owner() || msg.sender == master);
        lua.transfer(_to, _amount);
    }
}