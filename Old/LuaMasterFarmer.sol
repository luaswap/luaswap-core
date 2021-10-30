// SPDX-License-Identifier: UNLICENSED
// LuaMasterFarmer
pragma solidity >=0.6.0 <0.8.0;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./LuaVault.sol";


contract LuaMasterFarmer is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
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
    LuaVault public luaVault;
    // Dev address.
    address public devaddr;
    // LUA tokens created per block.
    uint256 public REWARD_PER_BLOCK;
    // Bonus muliplier for early LUA makers.
    uint256[] public REWARD_MULTIPLIER = [1, 0];
    uint256[] public HALVING_AT_BLOCK; // init in constructor function
    uint256 public FINISH_BONUS_AT_BLOCK;

    // The block number when LUA mining starts.
    uint256 public START_BLOCK;

    uint256 public constant PERCENT_FOR_DEV = 10; // 10% reward for dev

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
    event SendLuaReward(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        IERC20 _lua,
        LuaVault _luaVault,
        address _devaddr,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _halvingAfterBlock
    ) public {
        lua = _lua;
        luaVault = _luaVault;
        devaddr = _devaddr;
        REWARD_PER_BLOCK = _rewardPerBlock;
        _startBlock = _startBlock == 0 ? block.number : _startBlock;
        START_BLOCK = _startBlock;
        for (uint256 i = 0; i < REWARD_MULTIPLIER.length - 1; i++) {
            uint256 halvingAtBlock = _halvingAfterBlock.mul(i + 1).add(_startBlock);
            HALVING_AT_BLOCK.push(halvingAtBlock);
        }
        FINISH_BONUS_AT_BLOCK = _halvingAfterBlock.mul(REWARD_MULTIPLIER.length - 1).add(_startBlock);
        HALVING_AT_BLOCK.push(uint256(-1));
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
        uint256 luaForDev;
        uint256 luaForFarmer;
        (luaForDev, luaForFarmer) = getPoolReward(pool.lastRewardBlock, block.number, pool.allocPoint);
        
        if (luaForFarmer == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        if (luaForDev > 0) {
            luaVault.send(devaddr, luaForDev);
        }
        if (luaForFarmer > 0) {
            luaVault.send(address(this), luaForFarmer);
        }
        pool.accLuaPerShare = pool.accLuaPerShare.add(luaForFarmer.mul(1e12).div(lpSupply));
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

    function getPoolReward(uint256 _from, uint256 _to, uint256 _allocPoint) public view returns (uint256 forDev, uint256 forFarmer) {
        uint256 multiplier = getMultiplier(_from, _to);
        uint256 amount = multiplier.mul(REWARD_PER_BLOCK).mul(_allocPoint).div(totalAllocPoint);
        uint256 luaCanMint = lua.balanceOf(address(luaVault));

        if (luaCanMint < amount) {
            forDev = 0;
            forFarmer = luaCanMint;
        }
        else {
            forDev = devaddr == address(0) ? 0 : amount.mul(PERCENT_FOR_DEV).div(100);
            forFarmer = amount;
        }
    }

    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accLuaPerShare = pool.accLuaPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply > 0) {
            uint256 luaForFarmer;
            (, luaForFarmer) = getPoolReward(pool.lastRewardBlock, block.number, pool.allocPoint);
            accLuaPerShare = accLuaPerShare.add(luaForFarmer.mul(1e12).div(lpSupply));

        }
        return user.amount.mul(accLuaPerShare).div(1e12).sub(user.rewardDebt);
    }

    function claimReward(uint256 _pid) public {
        updatePool(_pid);
        _harvest(_pid);
    }

    function _harvest(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accLuaPerShare).div(1e12).sub(user.rewardDebt);
            uint256 masterBal = lua.balanceOf(address(this));

            if (pending > masterBal) {
                pending = masterBal;
            }
            
            if(pending > 0) {
                lua.transfer(msg.sender, pending);

                user.rewardDebtAtBlock = block.number;

                emit SendLuaReward(msg.sender, _pid, pending);
            }

            user.rewardDebt = user.amount.mul(pool.accLuaPerShare).div(1e12);
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
        user.rewardDebt = user.amount.mul(pool.accLuaPerShare).div(1e12);
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
        user.rewardDebt = user.amount.mul(pool.accLuaPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
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
}
