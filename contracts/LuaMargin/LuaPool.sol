// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../uniswapv2/UniswapV2ERC20.sol";

contract LuaPool is UniswapV2ERC20, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public token;
    uint256 public reserve;
    uint256 public totalRequestWithdraw;
    uint256 public totalLoan;
    mapping(address => uint256) public requestWithdrawAmount;
    mapping(address => bool) public verifiedMiddleMan;

    uint private unlocked = 1;

    event RequestWithdraw(
        address indexed add,
        uint256 lpAmount,
        uint256 oldAmount,
        uint256 newAmount
    );

    event Deposit(address indexed add, uint amount);
    event Withdraw(address indexed add, uint lpAmount, uint amount);
    event Loan(address indexed add, uint256 amount);
    event Repay(address indexed add, uint256 loanAmount, uint256 fee);
    event FlashLoan(address indexed add, address target, uint256 amount);

    constructor(address _token) public {
        token = _token;
    }

    modifier onlyMiddleMan() {
        require(verifiedMiddleMan[msg.sender], "LuaPool: Not middle man");
        _;
    }

    modifier correctBalance(address staker, uint256 _lpAmount) {
        require(_lpAmount <= balanceOf[staker], "LuaPool: wrong lpamount");
        _;
    }

    modifier lock() {
        require(unlocked == 1, 'LuaPool: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function poolBalance() public view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function maxAmountForLoan() public view returns (uint256) {
        uint256 balance = poolBalance();
        uint256 _totalRequest = totalRequestWithdraw;

        return _totalRequest >= balance ? 0 : balance.sub(_totalRequest);
    }

    function canWithdrawImediatelyAmount(address _staker)
        public
        view
        returns (uint256)
    {
        uint256 _currentRequest = requestWithdrawAmount[_staker];
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

    function setMiddleMan(address _man, bool _active) public onlyOwner {
        verifiedMiddleMan[_man] = _active;
    }

    function requestWithdraw(uint256 _lpAmount)
        public
        lock
        correctBalance(msg.sender, _lpAmount)
    {
        uint256 withdrawAmount = convertLPToAmount(_lpAmount);

        require(
            withdrawAmount > canWithdrawImediatelyAmount(msg.sender),
            "LuaPool: You can withdraw now"
        );

        uint256 currentRequest = requestWithdrawAmount[msg.sender];

        totalRequestWithdraw = totalRequestWithdraw.sub(currentRequest).add(
            withdrawAmount
        );

        requestWithdrawAmount[msg.sender] = withdrawAmount;

        emit RequestWithdraw(
            msg.sender,
            _lpAmount,
            currentRequest,
            withdrawAmount
        );
    }

    function withdraw(uint256 _lpAmount)
        public
        lock
        correctBalance(msg.sender, _lpAmount)
    {
        uint256 withdrawAmount = convertLPToAmount(_lpAmount);
        uint256 currentRequest = requestWithdrawAmount[msg.sender];

        require(
            withdrawAmount <= canWithdrawImediatelyAmount(msg.sender),
            "LuaPool: not enough balance"
        );

        _burn(msg.sender, _lpAmount);
        IERC20(token).safeTransfer(msg.sender, withdrawAmount);

        reserve = reserve.sub(withdrawAmount);

        if (currentRequest > withdrawAmount) {
            requestWithdrawAmount[msg.sender] = currentRequest.sub(withdrawAmount);
            totalRequestWithdraw = totalRequestWithdraw.sub(withdrawAmount);
        } else {
            requestWithdrawAmount[msg.sender] = 0;
            totalRequestWithdraw = totalRequestWithdraw.sub(currentRequest);
        }

        emit Withdraw(msg.sender, _lpAmount, withdrawAmount);
    }

    function sendTokenAfterRequestWithdraw(address add) public lock {
        uint256 withdrawAmount = requestWithdrawAmount[add];
        uint256 lpAmount = withdrawAmount.mul(totalSupply) / reserve;
        require(withdrawAmount > 0, "LuaPool: No request withdraw");
        require(
            withdrawAmount <= canWithdrawImediatelyAmount(add),
            "LuaPool: not enough balance"
        );

        _burn(add, lpAmount);
        IERC20(token).safeTransfer(add, withdrawAmount);
        requestWithdrawAmount[add] = 0;
        totalRequestWithdraw = totalRequestWithdraw.sub(withdrawAmount);
        emit Withdraw(msg.sender, lpAmount, withdrawAmount);
    }

    function deposit(uint256 _amount) public lock {
        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);

        if (reserve == 0) {
            _mint(msg.sender, _amount);
        } else {
            _mint(msg.sender, _amount.mul(totalSupply) / reserve);
        }

        reserve = reserve.add(_amount);
        emit Deposit(msg.sender, _amount);
    }

    function loan(uint256 _amount) public lock onlyMiddleMan {
        IERC20(token).safeTransfer(msg.sender, _amount);
        totalLoan = totalLoan.add(_amount);
        emit Loan(msg.sender, _amount);
    }

    function repay(uint256 _loanAmount, uint256 _payBackAmount) public lock onlyMiddleMan {
        reserve = reserve.add(_payBackAmount).sub(_loanAmount);
        totalLoan = totalLoan.sub(_loanAmount);
        emit Repay(msg.sender, _loanAmount, _payBackAmount);
    }
}
