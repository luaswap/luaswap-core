// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.6;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./uniswapv2/UniswapV2ERC20.sol";
import "./uniswapv2/interfaces/IUniswapV2Pair.sol";

interface ILuaPoolCallee {
    function luaPoolCall(
        uint256 amount,
        uint256 sendBackAmount,
        address sender,
        bytes calldata data
    ) external;
}

contract LuaPool is UniswapV2ERC20 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public reserve;
    uint256 public totalRequestWithdraw;
    mapping(address => uint256) public userReqestWithdraw;

    uint256 public feeFlashLoan = 1; // 1/1000 = 0.1%

    event RequestWithdraw(
        address indexed add,
        uint256 lpAmount,
        uint256 oldAmount,
        uint256 newAmount
    );

    event Loan(address indexed add, uint256 amount);
    event FlashLoan(address indexed add, address target, uint256 amount);

    constructor(address _token) public {
        token = IERC20(_token);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "LuaPool: only owner");
        _;
    }

    modifier correctBalance(address staker, uint256 _lpAmount) {
        require(_lpAmount <= balanceOf(staker), "LuaPool: wrong lpamount");
        _;
    }

    function poolBalance() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function deposit(uint256 _amount) public {
        token.safeTransferFrom(msg.sender, address(this), _amount);

        if (reserve == 0) {
            _mint(msg.sender, _amount);
        } else {
            _mint(msg.sender, _amount.mul(totalSupply) / reserve);
        }

        reserve = reserve.add(_amount);
    }

    function canWithdrawImediatelyAmount(address _staker)
        public
        view
        returns (uint256)
    {
        uint256 _currentRequest = userReqestWithdraw[_staker];
        uint256 _poolBalance = poolBalance();
        uint256 _totalRequest = totalRequestWithdraw.sub(_currentRequest);

        return
            _poolBalance > _totalRequest ? _poolBalance.sub(_totalRequest) : 0;
    }

    function convertLPToAmount(uint256 _lpAmount)
        public
        view
        returns (uint256)
    {
        return reserve.mul(_lpAmount).div(totalSupply);
    }

    function withdraw(uint256 _lpAmount)
        public
        correctBlance(msg.sender, _lpAmount)
    {
        uint256 withdrawAmount = convertLPToAmount(_lpAmount);

        require(
            withdrawAmount <= canWithdrawImediatelyAmount(msg.sender),
            "LuaPool: not enough balance"
        );

        _burn(msg.sender, _lpAmount);
        _safeTransfer(address(token), msg.sender, withdrawAmount);

        reserve = reserve.sub(withdrawAmount);

        uint256 currentRequest = userReqestWithdraw[msg.sender];

        if (currentRequest > withdrawAmount) {
            userReqestWithdraw[msg.sender] = currentRequest.sub(withdrawAmount);
            totalRequestWithdraw = totalRequestWithdraw.sub(withdrawAmount);
        } else {
            userReqestWithdraw[msg.sender] = 0;
            totalRequestWithdraw = totalRequestWithdraw.sub(currentRequest);
        }
    }

    function requestWithdraw(uint256 _lpAmount)
        public
        correctBalance(msg.sender, _lpAmount)
    {
        uint256 withdrawAmount = convertLPToAmount(_lpAmount);
        uint256 currentRequest = userReqestWithdraw[msg.sender];

        totalRequestWithdraw = totalRequestWithdraw.sub(currentRequest).add(
            withdrawAmount
        );

        userReqestWithdraw[msg.sender] = withdrawAmount;

        emit RequestWithdraw(
            msg.sender,
            _lpAmount,
            currentRequest,
            withdrawAmount
        );
    }

    function loan(uint256 _amount) public {
      token.safeTransfer(msg.sender, _amount);
      emit Loan(msg.sender, _amount);
    }

    function flashLoan(
        address _target,
        uint256 _amount,
        bytes calldata _data
    ) public {
        uint256 beforeBalance = poolBalance();
        uint256 needSendBackAmount = _amount.mul(1000 + feeFlashLoan).div(1000);
        token.safeTransfer(_target, _amount);
        if (_data.length > 0) {
            ILuaPoolCallee(_target).luaPoolCall(
                _amount,
                needSendBackAmount,
                msg.sender,
                _data
            );
        }
        uint256 afterBalance = poolBalance();
        uint256 backAmount = afterBalance.sub(beforeBalance);
        require(
            backAmount >= needSendBackAmount,
            "LuaPool: Oops, you have not pay enough flash loan fee"
        );
        reserve = reserve.add(backAmount).sub(_amount);
        emit FlashLoan(msg.sender, _target, _amount);
    }
}
