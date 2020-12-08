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
    using SafeMath for uint;

    address public constant factoryLua = address(0x0388C1E0f210AbAe597B7DE712B9510C6C36C857);
    address public constant factoryUni = address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address public constant factorySushi = address(0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac);

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _crossSwap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? _crossPairFor(output, path[i + 2]) : _to;
            IUniswapV2Pair(_crossPairFor(input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
    function crossSwapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts) {
        amounts = getCrossAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, _crossPairFor(path[0], path[1]), amounts[0]
        );
        _crossSwap(amounts, path, to);
    }
    function crossSwapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts) {
        amounts = getCrossAmountsIn(amountOut, path);
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, _crossPairFor(path[0], path[1]), amounts[0]
        );
        _crossSwap(amounts, path, to);
    }

    function crossSwapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = getCrossAmountsOut(msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(_crossPairFor(path[0], path[1]), amounts[0]));
        _crossSwap(amounts, path, to);
    }

    function crossSwapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = getCrossAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, _crossPairFor(path[0], path[1]), amounts[0]
        );
        _crossSwap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    // function crossSwapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
    //     external
    //     ensure(deadline)
    //     returns (uint[] memory amounts)
    // {
    //     require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
    //     amounts = getCrossAmountsIn(amountOut, path);
    //     require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
    //     TransferHelper.safeTransferFrom(
    //         path[0], msg.sender, _crossPairFor(path[0], path[1]), amounts[0]
    //     );
    //     _crossSwap(amounts, path, address(this));
    //     IWETH(WETH).withdraw(amounts[amounts.length - 1]);
    //     TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    // }
    // function crossSwapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
    //     external
    //     payable
    //     ensure(deadline)
    //     returns (uint[] memory amounts)
    // {
    //     require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
    //     amounts = getCrossAmountsIn(amountOut, path);
    //     require(amounts[0] <= msg.value, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
    //     IWETH(WETH).deposit{value: amounts[0]}();
    //     assert(IWETH(WETH).transfer(_crossPairFor(path[0], path[1]), amounts[0]));
    //     _crossSwap(amounts, path, to);
    //     // refund dust eth, if any
    //     if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    // }

    function _crossPairForAndFee(address tokenA, address tokenB) internal view returns (address pair, uint fee) {
        address luaPair = IUniswapV2Factory(factoryLua).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            address uniPair = IUniswapV2Factory(factoryUni).getPair(tokenA, tokenB);
            address sushiPair = IUniswapV2Factory(factorySushi).getPair(tokenA, tokenB);
            if (uniPair != address(0) && sushiPair != address(0)) {
                if (IERC20(uniPair).totalSupply() > IERC20(sushiPair).totalSupply()) {
                    return (uniPair, 3);
                }
                else {
                    return (sushiPair, 3);
                }
            }
            else if (uniPair != address(0)) {
                return (uniPair, 3);
            }
            else if (sushiPair != address(0)) {
                return (sushiPair, 3);
            }
        }
        else {
            return (luaPair, 4);
        }
    }

    function _crossPairFor(address tokenA, address tokenB) internal view returns (address pair) {
        (pair, ) = _crossPairForAndFee(tokenA, tokenB);
    }

    function _crossPairInfo(address tokenA, address tokenB) internal view returns (address pair, uint swapFee, uint reserveA, uint reserveB) {
        (pair, swapFee) = _crossPairForAndFee(tokenA, tokenB);

        (address token0,) = UniswapV2Library.sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function getCrossAmountsOut(uint amountIn, address[] memory path)
        public
        view
        returns (uint[] memory amounts)
    {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (, uint fee, uint reserveIn, uint reserveOut) = _crossPairInfo(path[i], path[i + 1]);
            amounts[i + 1] = UniswapV2Library.getAmountOut(amounts[i], reserveIn, reserveOut, fee);
        }
    }

    function getCrossAmountsIn(uint amountOut, address[] memory path)
        public
        view
        returns (uint[] memory amounts)
    {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            (, uint fee, uint reserveIn, uint reserveOut) = _crossPairInfo(path[i - 1], path[i]);
            amounts[i - 1] = UniswapV2Library.getAmountIn(amounts[i], reserveIn, reserveOut, fee);
        }
    }
}
