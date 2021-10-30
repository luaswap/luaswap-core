const { expectRevert, time } = require('@openzeppelin/test-helpers')
const LuaVault = artifacts.require('./contracts/dualFarm/LuaVault')
const RewardVault = artifacts.require('./contracts/dualFarm/RewardVault')
const MockERC20 = artifacts.require('MockERC20')
const LuaToken = artifacts.require('./contracts/dualFarm/LuaToken')
const LuaMasterFarmer = artifacts.require('./contracts/dualFarm/LuaMasterFarmer')

const UniswapV2Factory = artifacts.require('UniswapV2Factory');
const UniswapV2Pair = artifacts.require('UniswapV2Pair');

contract('LuaMasterFarmer', ([alice, bob, carol, dev, minter]) => {
    beforeEach(async () => {
        this.RewardToken = await LuaToken.new(100, 900, { from: alice })
        this.rewardVault = await RewardVault.new(this.RewardToken.address, { from: alice })

        this.LuaToken = await LuaToken.new(100, 900, { from: alice })
        this.luaVault = await LuaVault.new(this.LuaToken.address, { from: alice })

        this.factory = await UniswapV2Factory.new(alice, { from: alice });
        this.token0 = await MockERC20.new('TOKEN0', 'TOKEN0', '10000000000000000000000000', { from: alice });
        this.token1 = await MockERC20.new('TOKEN1', 'TOKEN1', '10000000000000000000000000', { from: alice });
        await this.token0.mint(alice, '2000000000000000000000000', { from: alice })
        await this.token1.mint(alice, '1000000000000000000000000', { from: alice })
        await this.token0.mint(bob, '3000000000000000000000000', { from: alice })
        await this.token1.mint(bob, '1500000000000000000000000', { from: alice })
        this.pair = await UniswapV2Pair.at((await this.factory.createPair(this.token0.address, this.token1.address)).logs[0].args.pair);        
    })

    it('should set correct state variables', async () => {
        this.chef = await LuaMasterFarmer.new(this.LuaToken.address, 
                                              this.RewardToken.address,
                                              this.luaVault.address,
                                              this.rewardVault.address,
                                              '0x0000000000000000000000000000000000000000', 
                                              100, 
                                              10, 
                                              100, 
                                              500, { from: alice })
        await this.luaVault.setMaster(this.chef.address, { from: alice })
        await this.LuaToken.mint(alice, '10000000000', { from: alice })
        await this.LuaToken.transfer(this.luaVault.address, '10000000000', { from: alice })

        await this.rewardVault.setMaster(this.chef.address, { from: alice })
        await this.RewardToken.mint(alice, '10000000000', { from: alice })
        await this.RewardToken.transfer(this.rewardVault.address, '10000000000', { from: alice })        

        assert.equal((await this.LuaToken.balanceOf(this.luaVault.address)).valueOf(), '10000000000');
        assert.equal((await this.RewardToken.balanceOf(this.rewardVault.address)).valueOf(), '10000000000');     

        assert.equal((await this.chef.LUA_REWARD_PER_BLOCK()).valueOf(), 10)
        assert.equal((await this.chef.REWARD_PER_BLOCK()).valueOf(), 100)
        assert.equal((await this.chef.START_BLOCK()).valueOf(), 100)
        assert.equal((await this.chef.REWARD_MULTIPLIER(0)).valueOf(), 1)
        assert.equal((await this.chef.HALVING_AT_BLOCK(0)).valueOf(), 600)
        assert.equal((await this.chef.FINISH_BONUS_AT_BLOCK()).valueOf(), 600)
    })


    it ('should correct multiplier', async () => {
        // start at block 10 and halving after 10 blocks
        this.chef = await LuaMasterFarmer.new(this.LuaToken.address, 
                                              this.RewardToken.address,
                                              this.luaVault.address,
                                              this.rewardVault.address,
                                              dev, 
                                              '100', 
                                              '10', 
                                              '10', 
                                              '500', { from: alice })

        await this.luaVault.setMaster(this.chef.address, { from: alice })
        await this.LuaToken.mint(alice, '10000000000', { from: alice })
        await this.LuaToken.transfer(this.luaVault.address, '10000000000', { from: alice })

        await this.rewardVault.setMaster(this.chef.address, { from: alice })
        await this.RewardToken.mint(alice, '10000000000', { from: alice })
        await this.RewardToken.transfer(this.rewardVault.address, '10000000000', { from: alice })        
        // 600, 9999999
        // 10, 1
        // ---------|--------------|-------------------------
        //   |---|
        //      |-------|
        //          |----|
        //              |-------|
        //                     |-----------|
        //                             |--------|
        assert.equal((await this.chef.getMultiplier(0, 1)).valueOf(), "0")
        assert.equal((await this.chef.getMultiplier(0, 9)).valueOf(), "0")
        assert.equal((await this.chef.getMultiplier(0, 10)).valueOf(), "0")
        assert.equal((await this.chef.getMultiplier(10, 11)).valueOf(), "1")
        assert.equal((await this.chef.getMultiplier(10, 20)).valueOf(), "10")
        assert.equal((await this.chef.getMultiplier(10, 500)).valueOf(), "490")
        assert.equal((await this.chef.getMultiplier(510, 550)).valueOf(), "0")
    })

    context('With ERC/LP token added to the field', () => {
        beforeEach(async () => {
            this.lp = await MockERC20.new('LPToken', 'LP', '10000000000', { from: minter })
            await this.lp.transfer(alice, '1000', { from: minter })
            await this.lp.transfer(bob, '1000', { from: minter })
            await this.lp.transfer(carol, '1000', { from: minter })          
        })

        it('should correct add new pool and set pool', async () => {
            this.chef = await LuaMasterFarmer.new(
                                                    this.LuaToken.address, 
                                                    this.RewardToken.address,
                                                    this.luaVault.address,
                                                    this.rewardVault.address,
                                                    dev, 
                                                    '100', 
                                                    '10', 
                                                    '100', 
                                                    '10', { from: alice })

            await this.luaVault.setMaster(this.chef.address, { from: alice })
            await this.rewardVault.setMaster(this.chef.address, { from: alice })
            
            await this.chef.add('100', this.lp.address, true, { from: alice})
            assert.equal((await this.chef.poolInfo(0)).lpToken.valueOf(), this.lp.address)
            assert.equal((await this.chef.poolInfo(0)).allocPoint.valueOf(), '100')
            assert.equal((await this.chef.poolInfo(0)).lastRewardBlock.valueOf(), '100')
            assert.equal((await this.chef.poolInfo(0)).accLuaPerShare.valueOf(), '0')
            assert.equal((await this.chef.poolId1(this.lp.address)).valueOf(), '1')

            await expectRevert(
                this.chef.add('100', this.lp.address, true, { from: bob}),
                "Ownable: caller is not the owner"
            )

            await expectRevert(
                this.chef.add('100', this.lp.address, true, { from: alice}),
                "LuaMasterFarmer::add: lp is already in pool"
            )
          
            assert.equal((await this.chef.totalAllocPoint()).valueOf(), '100')

        })

        it('should allow emergency withdraw', async () => {

            this.chef = await LuaMasterFarmer.new(
                                                    this.LuaToken.address, 
                                                    this.RewardToken.address,
                                                    this.luaVault.address,
                                                    this.rewardVault.address,
                                                    dev, 
                                                    '100', 
                                                    '10', 
                                                    '100', 
                                                    '900', { from: alice })

            await this.luaVault.setMaster(this.chef.address, { from: alice })
            await this.LuaToken.mint(alice, '10000000000', { from: alice })
            await this.LuaToken.transfer(this.luaVault.address, '10000000000', { from: alice })

            await this.rewardVault.setMaster(this.chef.address, { from: alice })
            await this.RewardToken.mint(alice, '10000000000', { from: alice })
            await this.RewardToken.transfer(this.rewardVault.address, '10000000000', { from: alice })            

            await this.chef.add('100', this.lp.address, true)
            await this.lp.approve(this.chef.address, '1000', { from: bob })
            await this.chef.deposit(0, '100', { from: bob })
            assert.equal((await this.lp.balanceOf(bob)).valueOf(), '900')
            await this.chef.emergencyWithdraw(0, { from: bob })
            assert.equal((await this.lp.balanceOf(bob)).valueOf(), '1000')
        })

        it('should correct deposit', async () => {
            this.chef = await LuaMasterFarmer.new(
                                                    this.LuaToken.address, 
                                                    this.RewardToken.address,
                                                    this.luaVault.address,
                                                    this.rewardVault.address,
                                                    dev, 
                                                    '100', 
                                                    '10', 
                                                    '10000', 
                                                    '900', { from: alice })

            await this.luaVault.setMaster(this.chef.address, { from: alice })
            await this.LuaToken.mint(alice, '10000000000', { from: alice })
            await this.LuaToken.transfer(this.luaVault.address, '10000000000', { from: alice })

            await this.rewardVault.setMaster(this.chef.address, { from: alice })
            await this.RewardToken.mint(alice, '10000000000', { from: alice })
            await this.RewardToken.transfer(this.rewardVault.address, '10000000000', { from: alice })            

            await this.chef.add('100', this.lp.address, true)
            await this.lp.approve(this.chef.address, '1000', { from: bob })
            await expectRevert(
                this.chef.deposit(0, 0, { from: bob }),
                'LuaMasterFarmer::deposit: amount must be greater than 0'
            )

            await this.chef.deposit(0, 100, { from: bob })
            assert.equal((await this.lp.balanceOf(bob)).valueOf(), '900')
            assert.equal((await this.lp.balanceOf(this.chef.address)).valueOf(), '100')

            assert.equal((await this.chef.pendingReward(0, bob)).valueOf(), "0")
            assert.equal((await this.chef.userInfo(0, bob)).rewardDebt.valueOf(), "0")
            assert.equal((await this.chef.poolInfo(0)).accRewardPerShare.valueOf(), "0")
            assert.equal((await this.chef.userInfo(0, bob)).luaDebt.valueOf(), "0")
            assert.equal((await this.chef.poolInfo(0)).accLuaPerShare.valueOf(), "0")            

            assert.equal((await this.chef.pendingReward(0, bob)).valueOf(), "0")
            assert.equal((await this.chef.userInfo(0, bob)).luaDebt.valueOf(), "0")
            assert.equal((await this.chef.poolInfo(0)).accLuaPerShare.valueOf(), "0")            

            await this.lp.approve(this.chef.address, '1000', { from: carol })
            await this.chef.deposit(0, 50, { from: carol })
            assert.equal((await this.lp.balanceOf(carol)).valueOf(), '950')
            assert.equal((await this.lp.balanceOf(this.chef.address)).valueOf(), '150')
            
            assert.equal((await this.chef.poolInfo(0)).accLuaPerShare.valueOf(), "0")
            assert.equal((await this.chef.poolInfo(0)).accRewardPerShare.valueOf(), "0")

            assert.equal((await this.chef.pendingReward(0, bob)).valueOf(), '0')
            assert.equal((await this.chef.pendingReward(0, carol)).valueOf(), '0')
        })

        it('should correct pending lua & balance & lock', async () => {
            this.chef = await LuaMasterFarmer.new(
                                                    this.LuaToken.address, 
                                                    this.RewardToken.address,
                                                    this.luaVault.address,
                                                    this.rewardVault.address,
                                                    dev, 
                                                    '100', 
                                                    '10', 
                                                    '200', 
                                                    '150', { from: alice })

            await this.luaVault.setMaster(this.chef.address, { from: alice })
            await this.LuaToken.mint(alice, '10000000000', { from: alice })
            await this.LuaToken.transfer(this.luaVault.address, '10000000000', { from: alice })            
            await this.LuaToken.transferOwnership(this.chef.address, { from: alice }) 

            await this.rewardVault.setMaster(this.chef.address, { from: alice })
            await this.RewardToken.mint(alice, '10000000000', { from: alice })
            await this.RewardToken.transfer(this.rewardVault.address, '10000000000', { from: alice })            
            await this.RewardToken.transferOwnership(this.chef.address, { from: alice })             

            await this.chef.add('10', this.lp.address, true) 

            await this.lp.approve(this.chef.address, '1000', { from: alice }) 
 
            await this.chef.deposit(0, '10', { from: alice }) 

            assert.equal((await this.chef.pendingReward(0, alice)).valueOf(), '0')
            assert.equal((await this.LuaToken.balanceOf(this.luaVault.address)).valueOf(), "10000000000")
            assert.equal((await this.RewardToken.balanceOf(this.rewardVault.address)).valueOf(), "10000000000")

            await time.advanceBlockTo('200')
            assert.equal((await this.chef.pendingReward(0, alice)).valueOf(), '0')

            await this.chef.massUpdatePools() // block 201

            assert.equal((await this.chef.pendingReward(0, alice)).valueOf(), '100')            

            await time.advanceBlockTo('210')
            assert.equal((await this.chef.pendingReward(0, alice)).valueOf(), '1000')            

            await this.chef.deposit(0, '10', { from: alice }) 

            assert.equal((await this.chef.pendingReward(0, alice)).valueOf(), "0") // when deposit, it will automatic harvest
            assert.equal((await this.LuaToken.balanceOf(alice)).valueOf(), "110")
            assert.equal((await this.RewardToken.balanceOf(alice)).valueOf(), "1100")


            await time.advanceBlockTo('212')
            assert.equal((await this.chef.pendingReward(0, alice)).valueOf(), "100")

            await time.advanceBlockTo('252')
            assert.equal((await this.chef.pendingReward(0, alice)).valueOf(), "4100")

            await time.advanceBlockTo('350')

            assert.equal((await this.chef.pendingReward(0, alice)).valueOf(), "13900")

            await time.advanceBlockTo('360')

            assert.equal((await this.chef.pendingReward(0, alice)).valueOf(), "13900")          
        })
        

        it('should give out LUAs only after farming time', async () => {
            this.chef = await LuaMasterFarmer.new(
                                                    this.LuaToken.address, 
                                                    this.RewardToken.address,
                                                    this.luaVault.address,
                                                    this.rewardVault.address,
                                                    dev, 
                                                    '30', 
                                                    '10', 
                                                    '400', 
                                                    '150', { from: alice })

            await this.luaVault.setMaster(this.chef.address, { from: alice })
            await this.LuaToken.mint(alice, '10000000000', { from: alice })
            await this.LuaToken.transfer(this.luaVault.address, '10000000000', { from: alice })

            await this.rewardVault.setMaster(this.chef.address, { from: alice })
            await this.RewardToken.mint(alice, '10000000000', { from: alice })
            await this.RewardToken.transfer(this.rewardVault.address, '10000000000', { from: alice })            

            await time.advanceBlockTo('390')
            await this.LuaToken.transferOwnership(this.chef.address, { from: alice }) // 391
            await this.RewardToken.transferOwnership(this.chef.address, { from: alice }) // 391

            await this.chef.add('100', this.lp.address, true) // 392

            await this.lp.approve(this.chef.address, '1000', { from: bob }) // 393
            await this.chef.deposit(0, '100', { from: bob }) // 394

            await time.advanceBlockTo('395')
            await this.chef.claimReward(0, { from: bob }) // block 396
            assert.equal((await this.RewardToken.balanceOf(bob)).valueOf(), '0')
            assert.equal((await this.LuaToken.balanceOf(bob)).valueOf(), '0')

            await time.advanceBlockTo('399')
            await this.chef.claimReward(0, { from: bob }) // block 400
            assert.equal((await this.RewardToken.balanceOf(bob)).valueOf(), '0')
            assert.equal((await this.LuaToken.balanceOf(bob)).valueOf(), '0')

            await this.chef.claimReward(0, { from: bob }) // block 401
            assert.equal((await this.RewardToken.totalBalanceOf(bob)).valueOf(), '30')
            assert.equal((await this.LuaToken.totalBalanceOf(bob)).valueOf(), '10')

            await time.advanceBlockTo('408')
            assert.equal((await this.chef.pendingReward(0, bob)).valueOf(), "210")
            await this.chef.claimReward(0, { from: bob }) // block 409
            assert.equal((await this.RewardToken.balanceOf(bob)).valueOf(), '270')
            assert.equal((await this.LuaToken.balanceOf(bob)).valueOf(), '90')


            assert.equal((await this.chef.pendingReward(0, bob)).valueOf(), "0")
        })

        it('should not distribute LUAs if no one deposit', async () => {
            await this.token0.transfer(this.pair.address, '2000000000000000000000000', { from: alice })
            await this.token1.transfer(this.pair.address, '1000000000000000000000000', { from: alice })
            await this.pair.mint(alice, { from: alice })

            await this.token0.transfer(this.pair.address, '3000000000000000000000000', { from: bob })
            await this.token1.transfer(this.pair.address, '1500000000000000000000000', { from: bob })
            await this.pair.mint(bob, { from: bob })   
            
            const reserves = await this.pair.getReserves()

            assert.equal(reserves[1].valueOf(), '5000000000000000000000000')
            assert.equal(reserves[0].valueOf(), '2500000000000000000000000')            
               
            assert.equal((await this.pair.totalSupply()).valueOf(), '3535533905932737622004220')
            assert.equal((await this.pair.balanceOf(alice)).valueOf(), '1414213562373095048800688')
            assert.equal((await this.pair.balanceOf(bob)).valueOf(), '2121320343559642573202532')

            this.chef = await LuaMasterFarmer.new(
                                                this.LuaToken.address, 
                                                this.RewardToken.address,
                                                this.luaVault.address,
                                                this.rewardVault.address,
                                                dev, 
                                                '30000000000000000000', 
                                                '10000000000000000000', 
                                                '500', 
                                                '100', { from: alice })

            await this.luaVault.setMaster(this.chef.address, { from: alice })
            await this.LuaToken.mint(alice, '1000000000000000000000', { from: alice })
            await this.LuaToken.transfer(this.luaVault.address, '1000000000000000000000', { from: alice })

            await this.rewardVault.setMaster(this.chef.address, { from: alice })
            await this.RewardToken.mint(alice, '1000000000000000000000', { from: alice })
            await this.RewardToken.transfer(this.rewardVault.address, '1000000000000000000000', { from: alice })   

            await this.LuaToken.transferOwnership(this.chef.address, { from: alice })
            await this.RewardToken.transferOwnership(this.chef.address, { from: alice })

            await this.chef.updateRewardManual('20000000000000000000', { from: alice })

            await this.chef.add('100000000000000000000', this.pair.address, true)
            await this.pair.approve(this.chef.address, '10000000000000000000000000000', { from: bob })
            await time.advanceBlockTo('510')
            //assert.equal((await this.LuaToken.totalSupply()).valueOf(), '0')
            await time.advanceBlockTo('520')
            //assert.equal((await this.LuaToken.totalSupply()).valueOf(), '0')
            await time.advanceBlockTo('530')
            await this.chef.updatePool(0) // block 531
            //assert.equal((await this.LuaToken.totalSupply()).valueOf(), '0')
            assert.equal((await this.RewardToken.balanceOf(bob)).valueOf(), '0')
            assert.equal((await this.LuaToken.balanceOf(bob)).valueOf(), '0')

            await this.chef.deposit(0, '10000000000000000000', { from: bob }) // block 532
            assert.equal((await this.pair.balanceOf(this.chef.address)).valueOf(), '10000000000000000000')
            // assert.equal((await this.LuaToken.totalSupply()).valueOf(), '0')
            assert.equal((await this.RewardToken.balanceOf(bob)).valueOf(), '0')
            assert.equal((await this.LuaToken.balanceOf(bob)).valueOf(), '0')

            await this.chef.withdraw(0, '10000000000000000000', { from: bob })
            assert.equal((await this.RewardToken.balanceOf(bob)).valueOf(), '20000000000000000000')
            assert.equal((await this.LuaToken.balanceOf(bob)).valueOf(), '10000000000000000000')

            await this.chef.deposit(0, '10000000000000000000', { from: bob }) // block 532
            await this.chef.updateRewardManual('10000000000000000000', { from: alice })
            await this.chef.withdraw(0, 10, { from: bob })
            assert.equal((await this.RewardToken.balanceOf(bob)).valueOf(), '50000000000000000000')

            await this.chef.updateReward('5000000000000000000', '2000000000000000000', 100, { from: alice })
            assert.equal((await this.chef.REWARD_PER_BLOCK()).valueOf(), '2000000000000000000')

            await this.chef.deposit(0, '2121000000000000000000000', { from: bob }) // block 532
            await this.chef.updateReward('73486177250000000', '18486177250000000', 120, { from: alice })
            assert.equal((await this.chef.REWARD_PER_BLOCK()).valueOf(), '73486177250000000')

        })

    })
})