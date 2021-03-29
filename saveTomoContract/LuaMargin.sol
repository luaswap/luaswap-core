// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./uniswapv2/UniswapV2ERC20.sol";
import "./uniswapv2/interfaces/IUniswapV2Pair.sol";

contract LuaMargin is UniswapV2ERC20 {
    using SafeMath for uint;
    bytes4 private constant SELECTOR_TRANSFER = bytes4(keccak256(bytes('transfer(address,uint256)')));
    bytes4 private constant SELECTOR_TRANSFER_FROM = bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));

    struct Position {
        uint collateral;
        uint borrowing;
        uint amount;
        address token;
        uint openedAtBlock;
        address owner;
    }

    uint public constant MAX_LEVERAGE = 10;

    IERC20 public token;
    uint256 public reserve;
    uint256 public requestWithdrawTotal;
    mapping(address => uint256) public userReqestWithdraw;
    mapping(address=>bool) public supportTokens;
    mapping(address => mapping(address => uint)) public mapPositions;
    Position[] public positions;
    
    constructor(address _token) public {
        token = IERC20(_token);
        positions.push(Position({
            collateral: 0,
            borrowing: 0,
            amount: 0,
            token: address(0x0),
            openedAtBlock: 0,
            owner: address(0x0)
        }));
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "LuaMargin: only owner");
        _;
    }

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'LuaMargin: EXPIRED');
        _;
    }

    function _safeTransfer(address _token, address to, uint value) private {
        (bool success, bytes memory data) = _token.call(abi.encodeWithSelector(SELECTOR_TRANSFER, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'LuaMargin: TRANSFER_FAILED');
    }

    function _safeTransferFrom(address _token, address from, address to, uint value) private {
        (bool success, bytes memory data) = _token.call(abi.encodeWithSelector(SELECTOR_TRANSFER_FROM, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'LuaMargin: TRANSFER_FROM_FAILED');
    }

    function addToken(address _token) public {
      require(_token != address(token), "LuaMargin: invalid token");
      supportTokens[_token] = true;
    }

    function removeToken(address _token) public {
      supportTokens[_token] = false;
    }
    
    function deposit(uint _amount) public {
        _safeTransferFrom(address(token), msg.sender, address(this), _amount);
        
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
        
        _safeTransfer(address(token), msg.sender, withdrawAmount);
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

    function swap(uint _amountIn, uint _amountOutMin, IUniswapV2Pair pair) private returns (uint amountOut) {
        address token0 = pair.token0();
        address _token = address(token);

        (uint reserve0, uint reserve1,) = pair.getReserves();
        
        (uint reserveIn, uint reserveOut) = token0 == _token ? (reserve0, reserve1) : (reserve1, reserve0);
        uint amountInWithFee = _amountIn.mul(997);
        amountOut = amountInWithFee.mul(reserveOut) / reserveIn.mul(1000).add(amountInWithFee);

        require(amountOut > _amountOutMin, "LuaMargin: INSUFFICIENT_OUTPUT_AMOUNT");

        (uint amount0Out, uint amount1Out) = token0 == _token ? (uint(0), amountOut) : (amountOut, uint(0));
        _safeTransfer(_token, address(pair), _amountIn);
        pair.swap(amount0Out, amount1Out, address(this), new bytes(0));
    }
    
    function openPosition(address _tokenBuy, address _pair, uint _collateral, uint _borrowing, uint _amountOutMin, uint _deadline) public ensure(_deadline) returns (uint pid) {
        IUniswapV2Pair pair = IUniswapV2Pair(_pair);
        address token0 = pair.token0();
        address token1 = pair.token1();
        address _token = address(token);

        require(supportTokens[_tokenBuy], "LuaMargin: not support token");
        require(_token != _tokenBuy, "LuaMargin: wrong token buy");
        require(token0 == _token || token1 == _token, "LuaMargin: Invalid token");
        require(token0 == _tokenBuy || token1 == _tokenBuy, "LuaMargin: Invalid token buy");
        require(_borrowing.div(_collateral) <= MAX_LEVERAGE, "LuaMargin: INSUFFICIENT_BORROW_AMOUNT_1");
        require(_borrowing <= token.balanceOf(address(this)).div(3), "LuaMargin: INSUFFICIENT_BORROW_AMOUNT_2");

        _safeTransferFrom(address(token), msg.sender, address(this), _collateral);
        uint amountOut = swap(_collateral.add(_borrowing), _amountOutMin, pair);
        
        pid = mapPositions[_tokenBuy][msg.sender];
        if (pid == 0) {
            pid = positions.length;
            positions.push(Position({
                collateral: _collateral,
                borrowing: _borrowing,
                token: _tokenBuy,
                amount: amountOut,
                openedAtBlock: block.number,
                owner: msg.sender
            }));
        }
        else {
            Position storage p = positions[pid];
            p.collateral = p.collateral.add(_collateral);
            p.borrowing = p.borrowing.add(_borrowing);
            uint numerator = p.openedAtBlock.mul(p.amount) + block.number.mul(amountOut);
            uint totalAmount = p.borrowing.add(amountOut);
            p.openedAtBlock = numerator.div(totalAmount);
            p.amount = totalAmount;
        }
    }
    
    function closePosition(uint pid) public {
        
    }

    function addMoreFund(uint pid, uint _collateral) public {
        Position storage p = positions[pid];
        require(p.amount > 0, "LuaMargin: wrong pid");
        _safeTransferFrom(p.token, msg.sender, address(this), _collateral);
        p.collateral = p.collateral.add(_collateral);
        
    }

    function removeFund(uint pid) public {

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