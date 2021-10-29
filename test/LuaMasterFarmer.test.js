const { expectRevert, time } = require('@openzeppelin/test-helpers')
const LuaVault = artifacts.require('LuaVault')
const MockERC20 = artifacts.require('MockERC20')
const LuaToken = artifacts.require('LuaToken')
const LuaMasterFarmer = artifacts.require('LuaMasterFarmer')

contract('LuaMasterFarmer', ([alice, bob, carol, dev, minter]) => {
    beforeEach(async () => {
        this.LuaToken = await LuaToken.new(100, 900, { from: alice })
        this.vault = await LuaVault.new(this.LuaToken.address, { from: alice })
    })

    it('should set correct state variables', async () => {
        this.chef = await LuaMasterFarmer.new(this.LuaToken.address, this.vault.address,'0x0000000000000000000000000000000000000000', 100, 100, 500, { from: alice })
        await this.vault.setMaster(this.chef.address, { from: alice })
        await this.LuaToken.mint(alice, '10000000000', { from: alice })
        await this.LuaToken.transfer(this.vault.address, '10000000000', { from: alice })

        assert.equal((await this.LuaToken.balanceOf(this.vault.address)).valueOf(), '10000000000');
        const master = await this.vault.master()
        assert.equal(master.valueOf(), this.chef.address)
        await this.LuaToken.transferOwnership(this.chef.address, { from: alice })
        const lua = await this.chef.lua()
        const devaddr = await this.chef.devaddr()
        const owner = await this.LuaToken.owner()
        assert.equal(lua.valueOf(), this.LuaToken.address)
        assert.equal(owner.valueOf(), this.chef.address)

        assert.equal((await this.chef.REWARD_PER_BLOCK()).valueOf(), 100)
        assert.equal((await this.chef.START_BLOCK()).valueOf(), 100)
        assert.equal((await this.chef.REWARD_MULTIPLIER(0)).valueOf(), 1)
        assert.equal((await this.chef.HALVING_AT_BLOCK(0)).valueOf(), 600)
        assert.equal((await this.chef.FINISH_BONUS_AT_BLOCK()).valueOf(), 600)
    })


    it ('should correct multiplier', async () => {
        // start at block 10 and halving after 10 blocks
        this.chef = await LuaMasterFarmer.new(this.LuaToken.address, this.vault.address,dev, '10', '10', '500', { from: alice })
        await this.vault.setMaster(this.chef.address, { from: alice })
        await this.LuaToken.mint(alice, '10000000000', { from: alice })
        await this.LuaToken.transfer(this.vault.address, '10000000000', { from: alice })
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
            this.lp2 = await MockERC20.new('LPToken2', 'LP2', '10000000000', { from: minter })
            await this.lp2.transfer(alice, '1000', { from: minter })
            await this.lp2.transfer(bob, '1000', { from: minter })
            await this.lp2.transfer(carol, '1000', { from: minter })
            this.lp3 = await MockERC20.new('LPToken3', 'LP3', '10000000000', { from: minter })
            await this.lp3.transfer(alice, '1000', { from: minter })
            await this.lp3.transfer(bob, '1000', { from: minter })
            await this.lp3.transfer(carol, '1000', { from: minter })            
        })

        it('should correct add new pool and set pool', async () => {
            // 10 lua per block, start at block 10 and halving after 10 block
            //this.chef = await LuaMasterFarmer.new(this.lua.address, dev, '10', '30', '10', { from: alice })
            this.chef = await LuaMasterFarmer.new(this.LuaToken.address, this.vault.address,dev, '10', '100', '10', { from: alice })
            await this.vault.setMaster(this.chef.address, { from: alice })
            
            await this.chef.add('100', this.lp.address, true, { from: alice})
            assert.equal((await this.chef.poolInfo(0)).lpToken.valueOf(), this.lp.address)
            assert.equal((await this.chef.poolInfo(0)).allocPoint.valueOf(), '100')
            assert.equal((await this.chef.poolInfo(0)).lastRewardBlock.valueOf(), '100')
            assert.equal((await this.chef.poolInfo(0)).accLuaPerShare.valueOf(), '0')
            assert.equal((await this.chef.poolId1(this.lp.address)).valueOf(), '1')
            await expectRevert(
                this.chef.add('100', this.lp.address, true, { from: alice}),
                "LuaMasterFarmer::add: lp is already in pool"
            )
            await expectRevert(
                this.chef.add('100', this.lp2.address, true, { from: bob}),
                "Ownable: caller is not the owner"
            )

            await this.chef.add('100', this.lp2.address, true, { from: alice})
            assert.equal((await this.chef.poolInfo(1)).lpToken.valueOf(), this.lp2.address)
            assert.equal((await this.chef.poolInfo(1)).allocPoint.valueOf(), '100')
            assert.equal((await this.chef.poolInfo(1)).lastRewardBlock.valueOf().toString(), '100')
            assert.equal((await this.chef.poolInfo(1)).accLuaPerShare.valueOf(), '0')
            assert.equal((await this.chef.poolId1(this.lp2.address)).valueOf(), '2')

            await this.chef.add('100', this.lp3.address, true, { from: alice})
            assert.equal((await this.chef.poolInfo(2)).lpToken.valueOf(), this.lp3.address)
            assert.equal((await this.chef.poolInfo(2)).allocPoint.valueOf(), '100')
            assert.equal((await this.chef.poolInfo(2)).lastRewardBlock.valueOf().toString(), '100')
            assert.equal((await this.chef.poolInfo(2)).accLuaPerShare.valueOf(), '0')
            assert.equal((await this.chef.poolId1(this.lp3.address)).valueOf(), '3')            

            assert.equal((await this.chef.totalAllocPoint()).valueOf(), '300')

        })

        it('should allow emergency withdraw', async () => {
            // 100 per block farming rate starting at block 100 and halving after each 900 blocks
            //this.chef = await LuaMasterFarmer.new(this.lua.address, dev, '100', '100', '900', { from: alice })
            this.chef = await LuaMasterFarmer.new(this.LuaToken.address, this.vault.address,dev, '100', '100', '900', { from: alice })
            await this.vault.setMaster(this.chef.address, { from: alice })
            await this.LuaToken.mint(alice, '10000000000', { from: alice })
            await this.LuaToken.transfer(this.vault.address, '10000000000', { from: alice })

            await this.chef.add('100', this.lp.address, true)
            await this.lp.approve(this.chef.address, '1000', { from: bob })
            await this.chef.deposit(0, '100', { from: bob })
            assert.equal((await this.lp.balanceOf(bob)).valueOf(), '900')
            await this.chef.emergencyWithdraw(0, { from: bob })
            assert.equal((await this.lp.balanceOf(bob)).valueOf(), '1000')
        })

        it('should correct deposit', async () => {
            this.chef = await LuaMasterFarmer.new(this.LuaToken.address, this.vault.address,dev, '100', '10000', '900', { from: alice })
            await this.vault.setMaster(this.chef.address, { from: alice })
            await this.LuaToken.mint(alice, '10000000000', { from: alice })
            await this.LuaToken.transfer(this.vault.address, '10000000000', { from: alice })

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
            assert.equal((await this.chef.poolInfo(0)).accLuaPerShare.valueOf(), "0")

            await this.lp.approve(this.chef.address, '1000', { from: carol })
            await this.chef.deposit(0, 50, { from: carol })
            assert.equal((await this.lp.balanceOf(carol)).valueOf(), '950')
            assert.equal((await this.lp.balanceOf(this.chef.address)).valueOf(), '150')
            
            assert.equal((await this.chef.poolInfo(0)).accLuaPerShare.valueOf(), "0")

            assert.equal((await this.chef.pendingReward(0, bob)).valueOf(), '0')
            assert.equal((await this.chef.pendingReward(0, carol)).valueOf(), '0')
        })

        it('should correct pending lua & balance & lock', async () => {
            // 100 per block farming rate starting at block 400 with bonus until block 1000
            //this.chef = await LuaMasterFarmer.new(this.lua.address, dev, '10', '100', '10', { from: alice })
            this.chef = await LuaMasterFarmer.new(this.LuaToken.address, this.vault.address,dev, '10', '200', '150', { from: alice })
            await this.vault.setMaster(this.chef.address, { from: alice })
            await this.LuaToken.mint(alice, '10000000000', { from: alice })
            await this.LuaToken.transfer(this.vault.address, '10000000000', { from: alice })            
            await this.LuaToken.transferOwnership(this.chef.address, { from: alice }) 

            await this.chef.add('10', this.lp.address, true) 
            await this.chef.add('10', this.lp2.address, true) 
            await this.chef.add('10', this.lp3.address, true) 
            await this.lp.approve(this.chef.address, '1000', { from: alice }) 
            await this.lp2.approve(this.chef.address, '1000', { from: bob }) 
            await this.lp3.approve(this.chef.address, '1000', { from: carol }) 
            await this.chef.deposit(0, '10', { from: alice }) 
            await this.chef.deposit(1, '10', { from: bob }) 
            await this.chef.deposit(2, '10', { from: carol }) 

            assert.equal((await this.chef.pendingReward(0, alice)).valueOf(), '0')
            assert.equal((await this.LuaToken.balanceOf(this.vault.address)).valueOf(), "10000000000")

            await time.advanceBlockTo('200')
            assert.equal((await this.chef.pendingReward(0, alice)).valueOf(), '0')
            assert.equal((await this.chef.pendingReward(1, bob)).valueOf(), '0')
            assert.equal((await this.chef.pendingReward(2, carol)).valueOf(), '0')

            await this.chef.massUpdatePools() // block 201

            assert.equal((await this.chef.pendingReward(0, alice)).valueOf(), '3')            
            assert.equal((await this.chef.pendingReward(1, bob)).valueOf(), '3')
            assert.equal((await this.chef.pendingReward(2, carol)).valueOf(), '3')

            await time.advanceBlockTo('210')
            assert.equal((await this.chef.pendingReward(0, alice)).valueOf(), '33')            
            assert.equal((await this.chef.pendingReward(1, bob)).valueOf(), '33')
            assert.equal((await this.chef.pendingReward(2, carol)).valueOf(), '33')

            await this.chef.deposit(0, '10', { from: alice }) 

            assert.equal((await this.chef.pendingReward(0, alice)).valueOf(), "0") // when deposit, it will automatic harvest
            assert.equal((await this.LuaToken.balanceOf(alice)).valueOf(), "36")

            await time.advanceBlockTo('212')
            assert.equal((await this.chef.pendingReward(0, alice)).valueOf(), "3")

            await time.advanceBlockTo('252')
            assert.equal((await this.chef.pendingReward(0, alice)).valueOf(), "136")

            await time.advanceBlockTo('350')

            assert.equal((await this.chef.pendingReward(0, alice)).valueOf(), "463")
            assert.equal((await this.chef.pendingReward(1, bob)).valueOf(), "499") 
            assert.equal((await this.chef.pendingReward(2, carol)).valueOf(), "499")

            await time.advanceBlockTo('360')

            assert.equal((await this.chef.pendingReward(0, alice)).valueOf(), "463")
            assert.equal((await this.chef.pendingReward(1, bob)).valueOf(), "499") 
            assert.equal((await this.chef.pendingReward(2, carol)).valueOf(), "499")            
        })
        

        it('should give out LUAs only after farming time', async () => {
            this.chef = await LuaMasterFarmer.new(this.LuaToken.address, this.vault.address,dev, '30', '400', '150', { from: alice })
            await this.vault.setMaster(this.chef.address, { from: alice })
            await this.LuaToken.mint(alice, '10000000000', { from: alice })
            await this.LuaToken.transfer(this.vault.address, '10000000000', { from: alice })

            await time.advanceBlockTo('390')
            await this.LuaToken.transferOwnership(this.chef.address, { from: alice }) // 391

            await this.chef.add('100', this.lp.address, true) // 392

            await this.lp.approve(this.chef.address, '1000', { from: bob }) // 393
            await this.chef.deposit(0, '100', { from: bob }) // 394

            await time.advanceBlockTo('395')
            await this.chef.claimReward(0, { from: bob }) // block 396
            assert.equal((await this.LuaToken.balanceOf(bob)).valueOf(), '0')

            await time.advanceBlockTo('399')
            await this.chef.claimReward(0, { from: bob }) // block 400
            assert.equal((await this.LuaToken.balanceOf(bob)).valueOf(), '0')

            await this.chef.claimReward(0, { from: bob }) // block 401
            assert.equal((await this.LuaToken.totalBalanceOf(bob)).valueOf(), '30')

            await time.advanceBlockTo('408')
            assert.equal((await this.chef.pendingReward(0, bob)).valueOf(), "210")
            await this.chef.claimReward(0, { from: bob }) // block 409
            assert.equal((await this.LuaToken.balanceOf(bob)).valueOf(), '270')
            // assert.equal((await this.LuaToken.lockOf(bob)).valueOf(), '8640')
            assert.equal((await this.chef.pendingReward(0, bob)).valueOf(), "0")
        })

        it('should not distribute LUAs if no one deposit', async () => {
            // 100 per block farming rate starting at block 200 with bonus until block 1000
            //this.chef = await LuaMasterFarmer.new(this.lua.address, dev, '100', '500', '10', { from: alice })
            this.chef = await LuaMasterFarmer.new(this.LuaToken.address, this.vault.address,dev, '100', '500', '100', { from: alice })
            await this.vault.setMaster(this.chef.address, { from: alice })
            await this.LuaToken.mint(alice, '10000000000', { from: alice })
            await this.LuaToken.transfer(this.vault.address, '10000000000', { from: alice })

            await this.LuaToken.transferOwnership(this.chef.address, { from: alice })
            await this.chef.add('100', this.lp.address, true)
            await this.lp.approve(this.chef.address, '1000', { from: bob })
            await time.advanceBlockTo('510')
            //assert.equal((await this.LuaToken.totalSupply()).valueOf(), '0')
            await time.advanceBlockTo('520')
            //assert.equal((await this.LuaToken.totalSupply()).valueOf(), '0')
            await time.advanceBlockTo('530')
            await this.chef.updatePool(0) // block 531
            //assert.equal((await this.LuaToken.totalSupply()).valueOf(), '0')
            assert.equal((await this.LuaToken.balanceOf(bob)).valueOf(), '0')

            await this.chef.deposit(0, '10', { from: bob }) // block 532
            assert.equal((await this.lp.balanceOf(this.chef.address)).valueOf(), '10')
            // assert.equal((await this.LuaToken.totalSupply()).valueOf(), '0')
            assert.equal((await this.LuaToken.balanceOf(bob)).valueOf(), '0')

            assert.equal((await this.lp.balanceOf(bob)).valueOf(), '990')

            await this.chef.withdraw(0, 10, { from: bob })
            assert.equal((await this.LuaToken.balanceOf(bob)).valueOf(), '100')
            assert.equal((await this.lp.balanceOf(bob)).valueOf(), '1000')

        })

    })
})