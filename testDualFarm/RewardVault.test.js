const { expectRevert, time } = require('@openzeppelin/test-helpers')
const RewardVault = artifacts.require('RewardVault')
const MockERC20 = artifacts.require('MockERC20')

contract('RewardVault', ([alice, dev, chef, luaAddr]) => {
    beforeEach(async () => {
        this.RewardToken = await MockERC20.new('RewardToken', 'TOKEN', '10000000000', { from: alice })
        this.vault = await RewardVault.new(this.RewardToken.address, { from: alice });
        await this.RewardToken.transfer(this.vault.address, '10000000000', { from: alice })
        await this.vault.setMaster(chef, { from: alice })
    })

    it('should have correct setting', async () => {
        assert.equal((await this.RewardToken.totalSupply()).valueOf(), '10000000000');
        assert.equal((await this.RewardToken.balanceOf(this.vault.address)).valueOf(), '10000000000');
        const owner = await this.vault.owner()
        const master = await this.vault.master()
        assert.equal(owner.valueOf(), alice)
        assert.equal(master.valueOf(), chef)
    })

    it('should allow owner or Master to send token', async () => {
        await this.vault.send(luaAddr, '1000', { from: alice })
        assert.equal((await this.RewardToken.balanceOf(luaAddr)).valueOf(), '1000');
        assert.equal((await this.RewardToken.balanceOf(this.vault.address)).valueOf(), 10000000000 - 1000)
    })
    it('should correct emergencyWithdraw', async () => {
        assert.equal((await this.RewardToken.balanceOf(this.vault.address)).valueOf(), 10000000000)
        await this.vault.emergencyWithdraw(this.RewardToken.address, dev, { from: alice})
        assert.equal((await this.RewardToken.balanceOf(this.vault.address)).valueOf(), 0)
        assert.equal((await this.RewardToken.balanceOf(dev)).valueOf(), 10000000000)

    })       
})
