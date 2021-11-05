// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.6;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract AccessControl {
    using SafeERC20 for IERC20;

    address payable public _owner;

    mapping(address => bool) public operators;

    event SetOperator(address indexed add, bool value);

    constructor(address _ownerAddress) public {
        _owner = payable(_ownerAddress);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner);
        _;
    }

    modifier onlyOperator() {
        require(operators[msg.sender]);
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }


    function setOwner(address payable _newOwner) external onlyOwner {
        require(_newOwner != address(0));
        _owner = _newOwner;
    }  

    function setOperator(address _operator, bool _v) external onlyOwner {
        operators[_operator] = _v;
        emit SetOperator(_operator, _v);
    }
    
}
