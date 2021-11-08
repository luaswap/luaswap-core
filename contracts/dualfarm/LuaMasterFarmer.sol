// SPDX-License-Identifier: UNLICENSED
// LuaMasterFarmer
pragma solidity 0.6.6;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import '../uniswapv2/interfaces/IUniswapV2Pair.sol';
import "./LuaVault.sol";
import "./RewardVault.sol";
import "./Factory.sol";

contract LuaMasterFarmer is Ownable, Factory {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 luaDebt; // lua debt. See explanation below.
        uint256 rewardDebtAtBlock; // the last block user stake
        //
        // We do some fancy math here. Basically, any point in time, the amount of LUAs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accLuaPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accLuaPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. LUAs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that LUAs distribution occurs.
        uint256 accLuaPerShare; // Accumulated LUAs per share, times 1e12. See below.
        uint256 accRewardPerShare; // Accumulated Rewards per share, times 1e12. See below.
    }

    IERC20 public lua;
    IERC20 public rewardToken;
    LuaVault public luaVault;
    RewardVault public rewardVault;
    // Reward tokens created per block.
    uint256 public REWARD_PER_BLOCK;    
    // LUA tokens created per block.
    uint256 public LUA_REWARD_PER_BLOCK;
    // Bonus muliplier for early LUA makers.
    uint256[] public REWARD_MULTIPLIER = [1, 0];
    uint256[] public HALVING_AT_BLOCK; // init in constructor function
    uint256 public FINISH_BONUS_AT_BLOCK;
    uint256 public NUM_OF_BLOCK_PER_YEAR = 10512000;

    // The block number when LUA mining starts.
    uint256 public START_BLOCK;
    uint256 public MAX_REWARD = 100e18; 

    address public operator;

    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    
    // Info of each pool.
    PoolInfo[] public poolInfo;
    mapping(address => uint256) public poolId1; // poolId1 count from 1, subtraction 1 before using with poolInfo
    // Info of each user that stakes LP tokens. pid => user address => info
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SendReward(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        IERC20 _lua,
        IERC20 _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _luaRewardPerBlock,
        uint256 _startBlock,
        uint256 _halvingAfterBlock
    ) public {
        operator = msg.sender;
        lua = _lua;
        rewardToken = _rewardToken;
        luaVault = new LuaVault(_lua, msg.sender);
        register(address(luaVault));
        rewardVault = new RewardVault(_rewardToken, msg.sender);
        register(address(rewardVault));
        REWARD_PER_BLOCK = _rewardPerBlock;
        LUA_REWARD_PER_BLOCK = _luaRewardPerBlock;
        _startBlock = _startBlock == 0 ? block.number : _startBlock;
        START_BLOCK = _startBlock;
        for (uint256 i = 0; i < REWARD_MULTIPLIER.length - 1; i++) {
            uint256 halvingAtBlock = _halvingAfterBlock.mul(i + 1).add(_startBlock);
            HALVING_AT_BLOCK.push(halvingAtBlock);
        }
        FINISH_BONUS_AT_BLOCK = _halvingAfterBlock.mul(REWARD_MULTIPLIER.length - 1).add(_startBlock);
        HALVING_AT_BLOCK.push(uint256(-1));
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "Not operator");
        _;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        require(poolId1[address(_lpToken)] == 0, "LuaMasterFarmer::add: lp is already in pool");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > START_BLOCK ? block.number : START_BLOCK;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolId1[address(_lpToken)] = poolInfo.length + 1;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accLuaPerShare: 0,
            accRewardPerShare: 0
        }));
    }

    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 luaForFarmer;
        uint256 rewardForFarmer;
        (luaForFarmer, rewardForFarmer) = getPoolReward(pool.lastRewardBlock, block.number, pool.allocPoint);
        
        if (luaForFarmer > 0) {
            luaVault.send(address(this), luaForFarmer);
        }

        if (rewardForFarmer > 0) {
            rewardVault.send(address(this), rewardForFarmer);
        }        
        pool.accLuaPerShare = pool.accLuaPerShare.add(luaForFarmer.mul(1e12).div(lpSupply));
        pool.accRewardPerShare = pool.accRewardPerShare.add(rewardForFarmer.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        uint256 result = 0;
        if (_from < START_BLOCK) return 0;

        for (uint256 i = 0; i < HALVING_AT_BLOCK.length; i++) {
            uint256 endBlock = HALVING_AT_BLOCK[i];

            if (_to <= endBlock) {
                uint256 m = _to.sub(_from).mul(REWARD_MULTIPLIER[i]);
                return result.add(m);
            }

            if (_from < endBlock) {
                uint256 m = endBlock.sub(_from).mul(REWARD_MULTIPLIER[i]);
                _from = endBlock;
                result = result.add(m);
            }
        }

        return result;
    }

    function getPoolReward(uint256 _from, uint256 _to, uint256 _allocPoint) public view returns (uint256 luaForFarmer, uint256 rewardForFarmer) {
        uint256 multiplier = getMultiplier(_from, _to);
        uint256 rewardAmount = multiplier.mul(REWARD_PER_BLOCK).mul(_allocPoint).div(totalAllocPoint);
        uint256 luaAmount = multiplier.mul(LUA_REWARD_PER_BLOCK).mul(_allocPoint).div(totalAllocPoint);
        uint256 rewardCanMint = rewardToken.balanceOf(address(rewardVault));
        uint256 luaCanMint = lua.balanceOf(address(luaVault));

        if (rewardCanMint < rewardAmount) {
            rewardForFarmer = rewardCanMint;
        }
        else {
            rewardForFarmer = rewardAmount;
        }

        if (luaCanMint < luaAmount) {
            luaForFarmer = luaCanMint;
        }
        else {
            luaForFarmer = luaAmount;
        }        
    }

    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply > 0) {
            uint256 rewardForFarmer;
            (, rewardForFarmer) = getPoolReward(pool.lastRewardBlock, block.number, pool.allocPoint);
            accRewardPerShare = accRewardPerShare.add(rewardForFarmer.mul(1e12).div(lpSupply));

        }
        return user.amount.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt);
    }

    function pendingLuaReward(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accLuaPerShare = pool.accLuaPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply > 0) {
            uint256 luaForFarmer;
            (luaForFarmer, ) = getPoolReward(pool.lastRewardBlock, block.number, pool.allocPoint);
            accLuaPerShare = accLuaPerShare.add(luaForFarmer.mul(1e12).div(lpSupply));

        }
        return user.amount.mul(accLuaPerShare).div(1e12).sub(user.luaDebt);
    }    

    function claimReward(uint256 _pid) public {
        updatePool(_pid);
        _harvest(_pid);
    }

    function _harvest(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.amount > 0) {
            uint256 pendingLua = user.amount.mul(pool.accLuaPerShare).div(1e12).sub(user.luaDebt);
            uint256 pendingRewardAmount = user.amount.mul(pool.accRewardPerShare).div(1e12).sub(user.rewardDebt);
            uint256 masterLuaBal = lua.balanceOf(address(this));
            uint256 masterRewardBal = rewardToken.balanceOf(address(this));

            if (pendingLua > masterLuaBal) {
                pendingLua = masterLuaBal;
            }

            if (pendingRewardAmount > masterRewardBal) {
                pendingRewardAmount = masterRewardBal;
            }            
            
            if(pendingLua > 0) {
                lua.transfer(msg.sender, pendingLua);
            }

            if(pendingRewardAmount > 0) {
                rewardToken.transfer(msg.sender, pendingRewardAmount);
                user.rewardDebtAtBlock = block.number;
                emit SendReward(msg.sender, _pid, pendingRewardAmount);
            }            

            user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
            user.luaDebt = user.amount.mul(pool.accLuaPerShare).div(1e12);
        }
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        require(_amount > 0, "LuaMasterFarmer::deposit: amount must be greater than 0");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        _harvest(_pid);
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        if (user.amount == 0) {
            user.rewardDebtAtBlock = block.number;
        }
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
        user.luaDebt = user.amount.mul(pool.accLuaPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "LuaMasterFarmer::withdraw: not good");

        updatePool(_pid);
        _harvest(_pid);
        
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
        user.luaDebt = user.amount.mul(pool.accLuaPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        user.luaDebt = 0;
    }

    function getNewRewardPerBlock(uint256 pid1) public view returns (uint256) {
        uint256 multiplier = getMultiplier(block.number -1, block.number);
        if (pid1 == 0) {
            return multiplier.mul(REWARD_PER_BLOCK);
        }
        else {
            return multiplier
                .mul(REWARD_PER_BLOCK)
                .mul(poolInfo[pid1 - 1].allocPoint)
                .div(totalAllocPoint);
        }
    }

    function updateHardMaxReward(uint max) public onlyOwner {
        MAX_REWARD = max;
    }

    function setOperator(address _operator) public onlyOwner {
        operator = _operator;
    }

    function updateReward(uint256 maxReward, uint256 minReward, uint256 apr) public onlyOperator {
        require(maxReward <= MAX_REWARD, "WRONG MAX REWARD");
        massUpdatePools();

        IUniswapV2Pair pair = IUniswapV2Pair(address(poolInfo[0].lpToken));
        (uint reserve0, uint reserve1, ) = pair.getReserves();
        uint tokenRewardReserve = address(pair.token0()) == address(rewardToken)? reserve0.mul(2) : reserve1.mul(2) ;

        uint tokenRewardAmount = tokenRewardReserve.mul(pair.balanceOf(address(this))).div(pair.totalSupply());
        uint newRewardPerBlock = tokenRewardAmount.mul(apr).div(NUM_OF_BLOCK_PER_YEAR);
        REWARD_PER_BLOCK = newRewardPerBlock > maxReward ? maxReward : newRewardPerBlock;
        REWARD_PER_BLOCK = REWARD_PER_BLOCK < minReward? minReward : REWARD_PER_BLOCK;
    }

    function updateRewardManual(uint256 newRewardPerBlock) public onlyOperator {
        massUpdatePools();
        REWARD_PER_BLOCK = newRewardPerBlock;
    }  

    function emergencyWithdrawLuaReward(address payable _to) external onlyOwner {
        IERC20(lua).safeTransfer(_to, IERC20(lua).balanceOf(address(this)));
    }   

    function emergencyWithdrawTokenReward(address payable _to) external onlyOwner {
        IERC20(rewardToken).safeTransfer(_to, IERC20(rewardToken).balanceOf(address(this)));
    }             
}
