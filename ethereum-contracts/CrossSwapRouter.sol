pragma solidity =0.6.12;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import './uniswapv2/libraries/TransferHelper.sol';
import './uniswapv2/interfaces/IUniswapV2Factory.sol';
import './uniswapv2/interfaces/IUniswapV2Pair.sol';
import './uniswapv2/interfaces/IWETH.sol';
import './uniswapv2/UniswapV2Router02.sol';

import './uniswapv2/libraries/UniswapV2Library.sol';

contract CrossSwapRouter is 
    UniswapV2Router02(
        address(0x0388C1E0f210AbAe597B7DE712B9510C6C36C857), 
        address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ) 
{
    function _crossSwap(uint[] memory amounts, address[] memory path, address[] calldata pairs, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? pairs[i] : _to;
            IUniswapV2Pair(pairs[i]).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
    function crossSwapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address[] calldata pairs,
        uint[] calldata fee, 
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts) {
        amounts = getCrossAmountsOut(amountIn, path, pairs, fee);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, pairs[0], amounts[0]
        );
        _crossSwap(amounts, path, pairs, to);
    }
    function crossSwapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address[] calldata pairs,
        uint[] calldata fee, 
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts) {
        amounts = getCrossAmountsIn(amountOut, path, pairs, fee);
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, pairs[0], amounts[0]
        );
        _crossSwap(amounts, path, pairs, to);
    }

    function crossSwapExactETHForTokens(
        uint amountOutMin, 
        address[] calldata path, 
        address[] calldata pairs, 
        uint[] calldata fee, 
        address to, 
        uint deadline
    )
        external
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = getCrossAmountsOut(msg.value, path, pairs, fee);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(pairs[0], amounts[0]));
        _crossSwap(amounts, path, pairs, to);
    }

    function crossSwapExactTokensForETH(
        uint amountIn, 
        uint amountOutMin, 
        address[] calldata path, 
        address[] calldata pairs, 
        uint[] calldata fee, 
        address to, 
        uint deadline
    )
        external
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = getCrossAmountsOut(amountIn, path, pairs, fee);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, pairs[0], amounts[0]
        );
        _crossSwap(amounts, path, pairs, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    
    function crossSwapTokensForExactETH(
        uint amountOut, 
        uint amountInMax, 
        address[] calldata path, 
        address[] calldata pairs, 
        uint[] calldata fee, 
        address to, 
        uint deadline
    )
        external
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = getCrossAmountsIn(amountOut, path, pairs, fee);
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, pairs[0], amounts[0]
        );
        _crossSwap(amounts, path, pairs, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function crossSwapETHForExactTokens(
        uint amountOut, 
        address[] calldata path, 
        address[] calldata pairs, 
        uint[] calldata fee, 
        address to, 
        uint deadline
    )
        external
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = getCrossAmountsIn(amountOut, path, pairs, fee);
        require(amounts[0] <= msg.value, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(pairs[0], amounts[0]));
        _crossSwap(amounts, path, pairs, to);
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    function getReserve(address tokenA, address tokenB, address pair) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = UniswapV2Library.sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function getCrossAmountsOut(uint amountIn, address[] memory path, address[] calldata pairs, uint[] calldata swapFee)
        public
        view
        returns (uint[] memory amounts)
    {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserve(path[i], path[i + 1], pairs[i]);
            amounts[i + 1] = UniswapV2Library.getAmountOut(amounts[i], reserveIn, reserveOut, swapFee[i]);
        }
    }

    function getCrossAmountsIn(uint amountOut, address[] memory path, address[] calldata pairs, uint[] calldata swapFee)
        public
        view
        returns (uint[] memory amounts)
    {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) = getReserve(path[i - 1], path[i], pairs[i - 1]);
            amounts[i - 1] = UniswapV2Library.getAmountIn(amounts[i], reserveIn, reserveOut, swapFee[i - 1]);
        }
    }
}
