// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../uniswapv2/interfaces/IUniswapV2Pair.sol";
import '../uniswapv2/libraries/UniswapV2Library.sol';
import "./LuaPool.sol";

contract LuaFutureSwap is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public token;
    LuaPool public pool;
    IUniswapV2Pair public pair;
    uint public swapFee;
    uint public BORROW_FEE = 50;  // 50 / 1000 = 50%

    uint public constant MAX_LEVERAGE = 10;
    uint public constant MAX_LEVERAGE_PERCENT_OF_POOL = 3;
    uint public constant DEFAULT_DURATION = 500000;

    mapping(address => uint) public positionIdOf;
    Position[] public positions;


    uint private unlocked = 1;

    struct Position {
        uint collateral;
        uint borrowing;
        uint amount;
        uint openedAtBlock;
        uint closedAtBlock;
        uint duration;
        address owner;
    }

    constructor(address _token, address _pool, IUniswapV2Pair _pair, uint _swapFee) public {
        token = _token;
        pool = LuaPool(_pool);

        (address token0, address token1) = UniswapV2Library.sortTokens(_token, pool.token());
        require(token0 == _pair.token0() && token1 == _pair.token1(), "LuaMargin: Wrong pair");

        pair = _pair;
        swapFee = _swapFee;
        
        // skip id will start from 1
        positions.push(Position({
            collateral: 0,
            borrowing: 0,
            amount: 0,
            openedAtBlock: 0,
            closedAtBlock: 0,
            duration: 0,
            owner: address(0x0)
        }));
    }

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }

    modifier lock() {
        require(unlocked == 1, 'UniswapV2: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    modifier existPosition(uint _pid) {
        require(positions[_pid].closedAtBlock == 0, "LuaMargin: wrong pid or postion was close");
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
                closedAtBlock: 0,
                duration: DEFAULT_DURATION,
                owner: _owner
            }));
        }
        else {
            Position storage p = positions[pid];
            p.collateral = p.collateral.add(_collateral);
            p.borrowing = p.borrowing.add(_borrowing);
            
            uint totalAmount = p.amount.add(_amount);
            uint additionDuration = (block.number + DEFAULT_DURATION).sub(p.openedAtBlock + p.duration);
            additionDuration = additionDuration.mul(_amount).div(totalAmount);
            p.duration = p.duration.add(additionDuration);
            p.amount = totalAmount;
        }
    }

    function _getAmountOut(address _tokenIn, uint _amountIn) private view returns (uint) {
        IUniswapV2Pair _pair = pair;
        (uint reserve0, uint reserve1,) = _pair.getReserves();
        (uint reserveIn, uint reserveOut) = _pair.token0() == _tokenIn ? (reserve0, reserve1) : (reserve1, reserve0);
        return UniswapV2Library.getAmountOut(_amountIn, reserveIn, reserveOut, swapFee);
    }

    function _swap(address _tokenIn, uint _amountIn, uint _amountOutMin) private returns (uint amountOut) {
        IUniswapV2Pair _pair = pair;

        amountOut = _getAmountOut(_tokenIn, _amountIn);
        require(amountOut > _amountOutMin, "LuaMargin: INSUFFICIENT_OUTPUT_AMOUNT");

        (uint amount0Out, uint amount1Out) = _pair.token0() == _tokenIn ? (uint(0), amountOut) : (amountOut, uint(0));
        IERC20(_tokenIn).safeTransfer(address(_pair), _amountIn);
        _pair.swap(amount0Out, amount1Out, address(this), new bytes(0));
    }
    
    function openPosition(uint _collateral, uint _borrowing, uint _amountOutMin, uint _deadline) public lock ensure(_deadline) returns (uint pid) {
        require(_borrowing.div(_collateral) <= MAX_LEVERAGE, "LuaMargin: INSUFFICIENT_BORROW_AMOUNT_1");
        require(_borrowing <= pool.poolBalance().div(MAX_LEVERAGE_PERCENT_OF_POOL), "LuaMargin: INSUFFICIENT_BORROW_AMOUNT_2");

        IERC20(token).safeTransferFrom(msg.sender, address(this), _collateral);
        pool.loan(_borrowing);

        uint amountOut = _swap(pool.token(), _collateral.add(_borrowing), _amountOutMin);

        return _updatePosition(msg.sender, _collateral, _borrowing, amountOut);
    }

    function closePosition(uint _pid) public lock existPosition(_pid) {
        Position storage p = positions[_pid];
        p.closedAtBlock = block.number;

        uint total = p.collateral.add(p.borrowing);
        uint PnL = _getAmountOut(address(token), p.amount).mul(100).div(total); // loss if value less than 100
        require(PnL < 20 || msg.sender == p.owner, "LuaMargin: Cannot close position"); // cannot remove fund if value drop more than 60%

        uint value = _swap(address(token), p.amount, 0);
        uint fee = p.borrowing.mul(BORROW_FEE).div(1000);
        uint repayAmount = p.borrowing.add(fee);

        repayAmount = value > repayAmount ? repayAmount : value;
        value = value.sub(repayAmount);
        address poolToken = pool.token();

        IERC20(poolToken).safeTransfer(address(pool), repayAmount);
        pool.repay(p.borrowing, repayAmount);

        IERC20(poolToken).safeTransfer(p.owner, value);
    }

    function addMoreFund(uint _pid, uint _amount) public lock existPosition(_pid) {
        Position storage p = positions[_pid];
        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);
        p.collateral = p.collateral.add(_amount);
    }

    function removeFund(uint _pid, uint _amount) public lock existPosition(_pid) {
        Position storage p = positions[_pid];
        require(p.owner == msg.sender, "LuaMargin: wrong user");

        uint value = _getAmountOut(address(token), p.amount);
        uint total = p.collateral.add(p.borrowing);
        require(value * 100 / total >= 40, "LuaMargin: value is low"); // cannot remove fund if value drop more than 60%

        uint _collateral = p.collateral.sub(_amount);
        require(p.borrowing.div(_collateral) <= MAX_LEVERAGE, "LuaMargin: Cannot remove fund");
        
        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);
        p.collateral = p.collateral.sub(_amount);
    }
}