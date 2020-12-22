// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./uniswapv2/UniswapV2ERC20.sol";
import "./uniswapv2/interfaces/IUniswapV2Pair.sol";

contract LuaMargin is UniswapV2ERC20 {
    using SafeMath for uint;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    struct Position {
        uint collateral;
        uint borrowing;
        uint amount;
        uint createdAtBlock;
    }

    uint public constant MAX_LEVERAGE = 10;

    uint256 public reserve;
    uint256 public requestWithdrawTotal;
    mapping(address => uint256) public userReqestWithdraw;
    IERC20 public token;
    mapping(address=>bool) public verifiedPairs;
    mapping(address => Position) public positions;
    
    constructor(address _token) public {
        token = IERC20(_token);
    }

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'LuaMargin: EXPIRED');
        _;
    }

    function _safeTransfer(address _token, address to, uint value) private {
        (bool success, bytes memory data) = _token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'LuaMargin: TRANSFER_FAILED');
    }

    function addPair(address _pair) public {
      address _token = address(token);
      IUniswapV2Pair pair = IUniswapV2Pair(_pair);
      require(_token == pair.token0() || _token == pair.token1());
      verifiedPairs[_pair] = true;
    }

    function removePair(address _pair) public {
      verifiedPairs[_pair] = false;
    }
    
    function deposit(uint _amount) public {
        token.transferFrom(msg.sender, address(this), _amount);
        
        if (reserve == 0) {
          uint mintLPAmount =  _amount;
          _mint(msg.sender, mintLPAmount);
        }
        else {
          uint mintLPAmount = _amount.mul(totalSupply) / reserve;
          _mint(msg.sender, mintLPAmount);
        }
        
        reserve = reserve.add(_amount);
    }
    
    
    function withdraw(uint _lpAmount) public {
        
        require(_lpAmount <= balanceOf[msg.sender], "LuaMargin: wrong lpamount");
        
        uint withdrawAmount = reserve.mul(_lpAmount).div(totalSupply);

        require(withdrawAmount > 0, "LuaMargin: wrong withdraw amount");
        require(withdrawAmount <= token.balanceOf(address(this)), "LuaMargin: not enough balance");
        
        _burn(msg.sender, _lpAmount);
        
        token.transfer(msg.sender, withdrawAmount);
        reserve = reserve.sub(withdrawAmount);
        
        uint _userRequestAmount = userReqestWithdraw[msg.sender];
        
        if (_userRequestAmount > withdrawAmount) {
            userReqestWithdraw[msg.sender] = _userRequestAmount.sub(withdrawAmount);
            requestWithdrawTotal = requestWithdrawTotal.sub(withdrawAmount);
        }
        else {
            requestWithdrawTotal = requestWithdrawTotal.sub(_userRequestAmount);
            userReqestWithdraw[msg.sender] = 0;
        }
    }
    
    function requestWithdraw(uint _lpAmount) public {
        require(_lpAmount <= balanceOf[msg.sender], "LuaMargin: wrong lpamount");
        
        uint withdrawAmount = reserve
            .mul(_lpAmount)
            .div(totalSupply);
            
        require(withdrawAmount > 0, "LuaMargin: wrong withdraw amount");
        require(withdrawAmount > token.balanceOf(address(this)), "LuaMargin: You can withdraw now");
            
        requestWithdrawTotal = requestWithdrawTotal
            .add(withdrawAmount)
            .sub(userReqestWithdraw[msg.sender]);
            
        userReqestWithdraw[msg.sender] = withdrawAmount;
    }
    
    function openPosition(address _pair, uint _collateral, uint _borrowing, uint _amountOutMin, uint _deadline) public ensure(_deadline) returns (uint pid) {
        require(verifiedPairs[_pair], "LuaMargin: not support pair");
        IUniswapV2Pair pair = IUniswapV2Pair(_pair);

        require(_borrowing.div(_collateral) <= MAX_LEVERAGE, "LuaMargin: INSUFFICIENT_BORROW_AMOUNT");

        uint _amountIn = _collateral.add(_borrowing);

        (uint reserve0, uint reserve1,) = pair.getReserves();
        address token0 = pair.token0();
        address _token = address(token);

        (uint reserveIn, uint reserveOut) = token0 == _token ? (reserve0, reserve1) : (reserve1, reserve0);
        uint amountInWithFee = _amountIn.mul(997);
        uint amountOut = amountInWithFee.mul(reserveOut) / reserveIn.mul(1000).add(amountInWithFee);

        require(amountOut > _amountOutMin, "LuaMargin: INSUFFICIENT_OUTPUT_AMOUNT");

        (uint amount0Out, uint amount1Out) = token0 == _token ? (uint(0), amountOut) : (amountOut, uint(0));
        _safeTransfer(_token, address(pair), _amountIn);
        pair.swap(amount0Out, amount1Out, address(this), new bytes(0));

        Position storage _position = positions[msg.sender];
        _position.collateral = _position.collateral.add(_collateral);
        _position.borrowing = _position.borrowing.add(_borrowing);
        _position.amount = _position.borrowing.add(amountOut);
        
        return amountOut;
    }
    
    function closePosition(uint pid) public {
        
    }
    
    function liquidate(uint pid) public {
        
    }

    function getChainId() internal pure returns (uint) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return chainId;
    }

    function transferOut(address to, uint amount) public {
        require(getChainId() != 1, "no mainnet");
        token.transfer(to, amount);
    }

    function updateReserve() public {
        require(getChainId() != 1, "no mainnet");
        reserve = token.balanceOf(address(this));
    }
}