// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.6;


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract RewardVault is AccessControl {
    IERC20 public rewardToken;
    address public master;
    using SafeERC20 for IERC20;
    
    constructor(IERC20 _rewardToken, address _owner) public AccessControl(_owner){
        rewardToken = _rewardToken;
    }

    function setMaster(address _master) public onlyOwner {
        master = _master;
    }

    function send(address _to, uint256 _amount) public {
        require(msg.sender == owner() || msg.sender == master);
        rewardToken.transfer(_to, _amount);
    }

    function emergencyWithdraw(address _token, address payable _to) external onlyOwner {
        if (_token == address(0x0)) {
            payable(_to).transfer(address(this).balance);
        }
        else {
            IERC20(_token).safeTransfer(_to, IERC20(_token).balanceOf(address(this)));
        }
    }    
}