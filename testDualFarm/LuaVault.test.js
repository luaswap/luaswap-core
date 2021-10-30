const { expectRevert, time } = require('@openzeppelin/test-helpers')
const LuaVault = artifacts.require('LuaVault')
const MockERC20 = artifacts.require('MockERC20')

contract('LuaVault', ([alice, dev, chef, luaAddr]) => {
    beforeEach(async () => {
        this.LuaToken = await MockERC20.new('LuaToken', 'LUA', '10000000000', { from: alice })
        this.vault = await LuaVault.new(this.LuaToken.address, { from: alice });
        await this.LuaToken.transfer(this.vault.address, '10000000000', { from: alice })
        await this.vault.setMaster(chef, { from: alice })
    })

    it('should have correct setting', async () => {
        assert.equal((await this.LuaToken.totalSupply()).valueOf(), '10000000000');
        assert.equal((await this.LuaToken.balanceOf(this.vault.address)).valueOf(), '10000000000');
        const owner = await this.vault.owner()
        const master = await this.vault.master()
        assert.equal(owner.valueOf(), alice)
        assert.equal(master.valueOf(), chef)
    })

    it('should allow owner or Master to send token', async () => {
        await this.vault.send(luaAddr, '1000', { from: alice })
        assert.equal((await this.LuaToken.balanceOf(luaAddr)).valueOf(), '1000');
        assert.equal((await this.LuaToken.balanceOf(this.vault.address)).valueOf(), 10000000000 - 1000)
    })
    it('should correct emergencyWithdraw', async () => {
        assert.equal((await this.LuaToken.balanceOf(this.vault.address)).valueOf(), 10000000000)
        await this.vault.emergencyWithdraw(this.LuaToken.address, dev, { from: alice})
        assert.equal((await this.LuaToken.balanceOf(this.vault.address)).valueOf(), 0)
        assert.equal((await this.LuaToken.balanceOf(dev)).valueOf(), 10000000000)

    })    
})
