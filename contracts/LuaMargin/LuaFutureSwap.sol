// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../uniswapv2/interfaces/IUniswapV2Pair.sol";
import '../uniswapv2/libraries/UniswapV2Library.sol';
import "./LuaPool.sol"

contract LuaPool is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public token;
    LuaPool public pool;
    IUniswapV2Pair public pair;
    uint public swapFee;
    uint public BORROW_FEE = 50;  // 50 / 1000 = 50%

    uint public constant MAX_LEVERAGE = 10;
    uint public constant MAX_LEVERAGE_PERCENT_OF_POOL = 3;

    mapping(address => uint) public positionIdOf;
    Position[] public positions;

    struct Position {
        uint collateral;
        uint borrowing;
        uint amount;
        uint openedAtBlock;
        address owner;
    }

    constructor(address _token, address _pool, IUniswapV2Pair _pair, uint _swapFee) public {
        token = IERC20(_token);
        pool = LuaPool(_pool);

        (address token0, address token1) = UniswapV2Library.sortTokens(_token, address(pool.token));
        require(token0 == _pair.token0() && token1 == _pair.token1(), "LuaMargin: Wrong pair");

        pair = _pair;
        swapFee = swapFee;
        
        // skip id will start from 1
        positions.push(Position({
            collateral: 0,
            borrowing: 0,
            amount: 0,
            token: address(0x0),
            openedAtBlock: 0,
            owner: address(0x0)
        }));
    }

    modifier existPosition(uint _pid) {
        require(positions[_pid].amount > 0, "LuaMargin: woring pid");
        _;
    }

    function _updatePosition(address _owner, uint _collateral, uint _borrowing, uint _amount) private returns (uint pid) {
        pid = positionIdOf[_owner];
        if (pid == 0) {
            pid = positions.length;
            positionIdOf[_owner] = pid;
            positions.push(Position({
                collateral: _collateral,
                borrowing: _borrowing,
                amount: _amount,
                openedAtBlock: block.number,
                owner: _owner
            }));
        }
        else {
            Position storage p = positions[pid];
            p.collateral = p.collateral.add(_collateral);
            p.borrowing = p.borrowing.add(_borrowing);
            uint currentAmount = p.amount;
            uint numerator = p.openedAtBlock.mul(currentAmount) + block.number.mul(amountOut);
            uint totalAmount = currentAmount.add(amountOut);
            p.openedAtBlock = numerator.div(totalAmount);
            p.amount = totalAmount;
        }
    }

    function _getAmountOut(address _tokenIn, uint _amountIn) private view {
        (uint reserve0, uint reserve1,) = pair.getReserves();
        (uint reserveIn, uint reserveOut) = token0 == _tokenIn ? (reserve0, reserve1) : (reserve1, reserve0);
        return UniswapV2Library.getAmountOut(_amountIn, reserveIn, reserveOut, swapFee)
    }

    function _swap(address _tokenIn, uint _amountIn, uint _amountOutMin) private returns (uint amountOut) {
        IUniswapV2Pair _pair = pair;

        uint amountOut = _getAmountOut(_tokenIn, _amountInt);
        require(amountOut > _amountOutMin, "LuaMargin: INSUFFICIENT_OUTPUT_AMOUNT");

        (uint amount0Out, uint amount1Out) = token0 == _tokenIn ? (uint(0), amountOut) : (amountOut, uint(0));
        IERC20(_tokenIn).safeTransfer(address(_pair), _amountIn);
        _pair.swap(amount0Out, amount1Out, address(this), new bytes(0));
    }
    
    function openPosition(uint _collateral, uint _borrowing, uint _amountOutMin, uint _deadline) public ensure(_deadline) returns (uint pid) {
        require(_borrowing.div(_collateral) <= MAX_LEVERAGE, "LuaMargin: INSUFFICIENT_BORROW_AMOUNT_1");
        require(_borrowing <= pool.poolBalance().div(MAX_LEVERAGE_PERCENT_OF_POOL), "LuaMargin: INSUFFICIENT_BORROW_AMOUNT_2");

        token.safeTransferFrom(msg.sender, address(this), _collateral);
        pool.loan(_borrowing);

        uint amountOut = _swap(address(pool.token), _collateral.add(_borrowing), _amountOutMin);

        return _updatePosition(msg.sender, _collateral, _borrowing, amountOut);
    }

    function closePosition(uint _pid) public existPosition(_pid) {
        Position storage p = positions[_pid];

        uint total = p.collateral.add(p.borrowing);
        uint PnL = _getAmountOut(address(token), p.amount).mul(100).div(total); // loss if value less than 100
        require(PnL < 20 || msg.sender == p.owner, "LuaMargin: Cannot close position"); // cannot remove fund if value drop more than 60%

        uint value = _swap(address(token), p.amount, 0);
        uint fee = p.borrowing.mul(BORROW_FEE).div(1000);
        uint repayAmount = p.borrowing.add(fee);

        repayAmount = value > repayAmount ? repayAmount : value;
        value = value.sub(repayAmount);

        pool.token.safeTransfer(address(pool), repayAmount);
        pool.repay(p.borrowing, repayAmount);

        pool.token.safeTransfer(p.owner, value);

        p.amount = 0;

    }

    function addMoreFund(uint _pid, uint _amount) public existPosition(_pid) {
        Position storage p = positions[_pid];
        token.safeTransferFrom(msg.sender, address(this), _amount);
        p.collateral = p.collateral.add(_amount);
    }

    function removeFund(uint _pid, uint _amount) public existPosition(_pid) {
        Position storage p = positions[_pid];
        require(p.owner == msg.sender, "LuaMargin: wrong user");

        uint value = _getAmountOut(address(token), p.amount);
        uint total = p.collateral.add(p.borrowing)
        require(value * 100 / total >= 40, "LuaMargin: value is low"); // cannot remove fund if value drop more than 60%

        uint _collateral = p.collateral.sub(_amount);
        require(_borrowing.div(_collateral) <= MAX_LEVERAGE, "LuaMargin: Cannot remove fund");
        
        token.safeTransferFrom(msg.sender, address(this), _amount);
        p.collateral = p.collateral.sub(_amount);
    }
}