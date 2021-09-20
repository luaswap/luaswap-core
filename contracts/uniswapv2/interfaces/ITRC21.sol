pragma solidity ^0.6.6;
interface ITRC21 {
	function totalSupply() external view returns (uint256);
	function balanceOf(address who) external view returns (uint256);
  function issuer() external view returns (address);
	function estimateFee(uint256 value) external view returns (uint256);
  function minFee() external view returns (uint256);
	function allowance(address owner, address spender) external view returns (uint256);
	function transfer(address to, uint256 value) external returns (bool);
	function approve(address spender, uint256 value) external returns (bool);
	function transferFrom(address from, address to, uint256 value) external returns (bool);
}