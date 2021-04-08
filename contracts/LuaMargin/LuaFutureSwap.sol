// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../uniswapv2/interfaces/IUniswapV2Pair.sol";
import "../uniswapv2/libraries/UniswapV2Library.sol";
import "./LuaPool.sol";

contract LuaFutureSwap is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public token;
    LuaPool public pool;
    IUniswapV2Pair public pair;
    uint256 public swapFee;
    uint256 public BORROW_FEE = 50; //5% | 50 / 1000

    uint256 public constant RISK_LIQIDATION = 80; // liquidate if borrowing = 80% of value of amount
    uint256 public constant MAX_LEVERAGE = 5;
    uint256 public constant POSITION_DURATION = 500000;

    mapping(address => uint256) public positionIdOf;
    Position[] public positions;

    uint256 private unlocked = 1;

    struct Position {
        uint256 collateral;
        uint256 borrowing;
        uint256 amount;
        uint256 openedAtBlock;
        address owner;
    }

    constructor(
        address _token,
        address _pool,
        IUniswapV2Pair _pair,
        uint256 _swapFee
    ) public {
        token = _token;
        pool = LuaPool(_pool);

        (address token0, address token1) =
            UniswapV2Library.sortTokens(_token, pool.token());
        require(
            token0 == _pair.token0() && token1 == _pair.token1(),
            "LuaMargin: Wrong pair"
        );

        pair = _pair;
        swapFee = _swapFee;

        // skip id will start from 1
        positions.push(
            Position({
                collateral: 0,
                borrowing: 0,
                amount: 0,
                openedAtBlock: 0,
                owner: address(0x0)
            })
        );
    }

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "UniswapV2Router: EXPIRED");
        _;
    }

    modifier lock() {
        require(unlocked == 1, "UniswapV2: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    modifier correctBorrowing(uint256 _borrowing, uint256 _collateral) {
        require(
            _borrowing.div(_collateral) <= MAX_LEVERAGE,
            "LuaMargin: Borrow too much"
        );
        _;
    }

    modifier existPosition(uint256 _pid) {
        require(
            positions[_pid].amount > 0,
            "LuaMargin: wrong pid or postion was close"
        );
        _;
    }

    modifier ownerPosition(uint256 _pid) {
        require(
            positions[_pid].owner == msg.sender,
            "LuaMargin: not owner of positions"
        );
        _;
    }

    function _takeTokenFromSender(uint256 _amount) {
        IERC20(pool.token()).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
    }

    function _repay(uint256 _borrowing, uint256 _repayAmount) {
        IERC20(pool.token()).safeTransfer(address(pool), _repayAmount);
        pool.repay(_borrowing, _repayAmount);
    }

    function _closePosition(uint256 _pid, uint256 _amount) private {
        Position storage p = positions[_pid];

        require(p.amount >= _amount, "LuaMargin: wrong amount");

        uint256 _borrowing = p.borrowing.mul(_amount).div(p.amount);
        uint256 _collateral = p.collateral.mul(_amount).div(p.amount);

        uint256 value = _swap(address(token), _amount, 0);
        uint256 fee = _borrowing.mul(BORROW_FEE).div(1000);
        uint256 repayAmount = _borrowing.add(fee);

        repayAmount = value > repayAmount ? repayAmount : value;
        value = value.sub(repayAmount);

        p.collateral = p.collateral.sub(_collateral);
        p.borrowing = p.borrowing.sub(_borrowing);
        p.amount = p.amount.sub(_amount);

        if (p.amount == 0) {
            positionIdOf[p.owner] = 0;
        }

        IERC20(pool.token()).safeTransfer(p.owner, value);
        _repay(_borrowing, repayAmount);
    }

    function _getAmountOut(address _tokenIn, uint256 _amountIn)
        private
        view
        returns (uint256)
    {
        IUniswapV2Pair _pair = pair;
        (uint256 reserve0, uint256 reserve1, ) = _pair.getReserves();
        (uint256 reserveIn, uint256 reserveOut) =
            _pair.token0() == _tokenIn
                ? (reserve0, reserve1)
                : (reserve1, reserve0);
        return
            UniswapV2Library.getAmountOut(
                _amountIn,
                reserveIn,
                reserveOut,
                swapFee
            );
    }

    function _swap(
        address _tokenIn,
        uint256 _amountIn,
        uint256 _amountOutMin
    ) private returns (uint256 amountOut) {
        IUniswapV2Pair _pair = pair;

        amountOut = _getAmountOut(_tokenIn, _amountIn);
        require(
            amountOut > _amountOutMin,
            "LuaMargin: INSUFFICIENT_OUTPUT_AMOUNT"
        );

        (uint256 amount0Out, uint256 amount1Out) =
            _pair.token0() == _tokenIn
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
        IERC20(_tokenIn).safeTransfer(address(_pair), _amountIn);
        _pair.swap(amount0Out, amount1Out, address(this), new bytes(0));
    }

    function _loanThenSwap(
        uint256 _borrowing,
        uint256 _collateral,
        uint256 _amountOutMin
    ) private returns (uint256 amountOut) {
        pool.loan(_borrowing);

        uint256 total = _collateral.add(_borrowing);
        amountOut = _swap(pool.token(), total, _amountOutMin);
    }

    function openPosition(
        uint256 _pid,
        uint256 _collateral,
        uint256 _borrowing,
        uint256 _amountOutMin,
        uint256 _deadline
    )
        public
        lock
        ensure(_deadline)
        correctBorrowing(_borrowing, _collateral)
        returns (uint256 pid, uint256 amountOut)
    {
        require(
            _pid == 0 || positions[_pid].owner == msg.sender,
            "LuaMargin: wrong pid"
        );

        _takeTokenFromSender(_collateral);
        amountOut = _loanThenSwap(_borrowing, _collateral, _amountOutMin);

        if (_pid == 0) {
            pid = positions.length;
            positionIdOf[_owner] = pid;
            positions.push(
                Position({
                    collateral: _collateral,
                    borrowing: _borrowing,
                    amount: _amount,
                    openedAtBlock: block.number,
                    owner: _owner
                })
            );
        } else {
            pid = _pid;
            Position storage p = positions[pid];
            p.collateral = p.collateral.add(_collateral);
            p.borrowing = p.borrowing.add(_borrowing);
            p.amount = p.amount.add(_amount);
        }
    }

    function addMoreFund(uint256 _pid, uint256 _amount)
        public
        lock
        existPosition(_pid)
        ownerPosition(_pid)
    {
        Position storage p = positions[_pid];
        require(_amount <= p.borrowing, "LuaSwap: wrong amount");

        uint256 fee = _amount.mul(BORROW_FEE).div(1000);
        uint256 _borrowing = _amount.sub(fee);

        p.collateral = p.collateral.add(_amount);
        p.borrowing = p.borrowing.sub(_borrowing);

        _takeTokenFromSender(_amount);
        _repay(_borrowing, _amount);
    }

    function closePosition(uint256 _pid, uint256 _amount)
        public
        lock
        existPosition(_pid)
        ownerPosition(_pid)
    {
        _closePosition(_pid, _amount);
    }

    function liquidate(uint256 _pid) public lock existPosition(_pid) {
        Position memory p = positions[_pid];
        uint256 value = _getAmountOut(address(token), p.amount);
        uint256 risk = p.borrowing.mul(100).div(value);
        bool liquidationPrice = risk > RISK_LIQIDATION;
        bool expiration = p.openedAtBlock + POSITION_DURATION < block.number;
        require(
            liquidationPrice || expiration,
            "LuaMargin: Cannot liquidate position"
        );

        _closePosition(_pid, positions[_pid].amount);
    }
}
