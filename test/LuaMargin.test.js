
const { expectRevert, time, BN } = require('@openzeppelin/test-helpers')
const { assertion } = require('@openzeppelin/test-helpers/src/expectRevert')
const LuaMargin = artifacts.require('LuaMargin')
const MockERC20 = artifacts.require('MockERC20')

contract('LuaMargin', ([alice, bob, carol, dev, minter]) => {
    beforeEach(async () => {
        this.USDT = await MockERC20.new('USDT', 'USDT', 1000000000, { from: alice })
        this.LuaMargin = await LuaMargin.new(this.USDT.address, { from: alice })
    })

    it('Correct deposit and withdraw', async () => {
        this.USDT.transfer(bob, 1000, { from: alice });
        this.USDT.approve(this.LuaMargin.address, 1000, { from: bob });

        this.LuaMargin.deposit(500, { from: bob });

        assert.equal((await this.LuaMargin.totalSupply()).toNumber(), 500);
        assert.equal((await this.LuaMargin.balanceOf(bob)).toNumber(), 500);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 500);

        await expectRevert(this.LuaMargin.withdraw(1000, { from: bob }), 'LuaMargin: wrong lpamount')
        await expectRevert(this.LuaMargin.requestWithdraw(1000, { from: bob }), 'LuaMargin: wrong lpamount')
        await expectRevert(this.LuaMargin.requestWithdraw(500, { from: bob }), 'LuaMargin: You can withdraw now')
        await expectRevert(this.LuaMargin.requestWithdraw(100, { from: bob }), 'LuaMargin: You can withdraw now')

        await this.LuaMargin.transferOut(alice, 100);
        await expectRevert(this.LuaMargin.requestWithdraw(400, { from: bob }), 'LuaMargin: You can withdraw now')
        this.LuaMargin.requestWithdraw(500, { from: bob })

        await expectRevert(this.LuaMargin.withdraw(500, { from: bob }), 'LuaMargin: not enough balance')

        await this.LuaMargin.withdraw(400, { from: bob });

        assert.equal((await this.LuaMargin.totalSupply()).toNumber(), 100);
        assert.equal((await this.LuaMargin.balanceOf(bob)).toNumber(), 100);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 900);

        await this.USDT.transfer(this.LuaMargin.address, 100, { from: alice });

        await this.LuaMargin.withdraw(100, { from: bob });
        assert.equal((await this.LuaMargin.totalSupply()).toNumber(), 0);
        assert.equal((await this.LuaMargin.balanceOf(bob)).toNumber(), 0);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 1000);
    })

    it('Correct deposit and withdraw with losing', async () => {
        this.USDT.transfer(bob, 1000, { from: alice });
        this.USDT.approve(this.LuaMargin.address, 1000, { from: bob });

        this.LuaMargin.deposit(500, { from: bob });

        assert.equal((await this.LuaMargin.totalSupply()).toNumber(), 500);
        assert.equal((await this.LuaMargin.balanceOf(bob)).toNumber(), 500);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 500);

        await expectRevert(this.LuaMargin.withdraw(1000, { from: bob }), 'LuaMargin: wrong lpamount')
        
        await this.LuaMargin.transferOut(alice, 100);
        await this.LuaMargin.updateReserve();
        await this.LuaMargin.withdraw(250, { from: bob });

        assert.equal((await this.LuaMargin.totalSupply()).toNumber(), 250);
        assert.equal((await this.LuaMargin.balanceOf(bob)).toNumber(), 250);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 700);

        await this.LuaMargin.withdraw(250, { from: bob });

        assert.equal((await this.LuaMargin.totalSupply()).toNumber(), 0);
        assert.equal((await this.LuaMargin.balanceOf(bob)).toNumber(), 0);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 900);
    })

    it('Correct deposit and withdraw with profit', async () => {
        this.USDT.transfer(bob, 1000, { from: alice });
        this.USDT.approve(this.LuaMargin.address, 1000, { from: bob });

        this.LuaMargin.deposit(500, { from: bob });

        assert.equal((await this.LuaMargin.totalSupply()).toNumber(), 500);
        assert.equal((await this.LuaMargin.balanceOf(bob)).toNumber(), 500);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 500);

        await expectRevert(this.LuaMargin.withdraw(1000, { from: bob }), 'LuaMargin: wrong lpamount')
        
        await this.USDT.transfer(this.LuaMargin.address, 100, { from: alice });
        await this.LuaMargin.updateReserve();
        await this.LuaMargin.withdraw(250, { from: bob });

        assert.equal((await this.LuaMargin.totalSupply()).toNumber(), 250);
        assert.equal((await this.LuaMargin.balanceOf(bob)).toNumber(), 250);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 800);

        await this.LuaMargin.withdraw(250, { from: bob });

        assert.equal((await this.LuaMargin.totalSupply()).toNumber(), 0);
        assert.equal((await this.LuaMargin.balanceOf(bob)).toNumber(), 0);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 1100);
    })

    it('Correct deposit and withdraw with 2 stakers', async () => {
        this.USDT.transfer(bob, 1000, { from: alice });
        this.USDT.transfer(carol, 1000, { from: alice });
        this.USDT.approve(this.LuaMargin.address, 1000, { from: bob });
        this.USDT.approve(this.LuaMargin.address, 1000, { from: carol });

        this.LuaMargin.deposit(500, { from: bob });
        this.LuaMargin.deposit(800, { from: carol });
        this.LuaMargin.deposit(500, { from: bob });

        assert.equal((await this.LuaMargin.totalSupply()).toNumber(), 1800);
        assert.equal((await this.LuaMargin.balanceOf(bob)).toNumber(), 1000);
        assert.equal((await this.LuaMargin.balanceOf(carol)).toNumber(), 800);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 0);
        assert.equal((await this.USDT.balanceOf(carol)).toNumber(), 200);

        await expectRevert(this.LuaMargin.withdraw(1000, { from: carol }), 'LuaMargin: wrong lpamount')
        
        this.LuaMargin.withdraw(300, { from: carol })
        assert.equal((await this.USDT.balanceOf(carol)).toNumber(), 500);
        assert.equal((await this.LuaMargin.balanceOf(carol)).toNumber(), 500);
        assert.equal((await this.USDT.balanceOf(this.LuaMargin.address)).toNumber(), 1500);

        await this.USDT.transfer(this.LuaMargin.address, 100, { from: alice });
        assert.equal((await this.USDT.balanceOf(this.LuaMargin.address)).toNumber(), 1600);
        await this.LuaMargin.updateReserve();
        await this.LuaMargin.withdraw(250, { from: bob });
        
        assert.equal((await this.USDT.balanceOf(this.LuaMargin.address)).toNumber(), 1334);
        assert.equal((await this.LuaMargin.totalSupply()).toNumber(), 1250);
        assert.equal((await this.LuaMargin.balanceOf(bob)).toNumber(), 750);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 266);

        await this.LuaMargin.transferOut(alice, 200);
        assert.equal((await this.USDT.balanceOf(this.LuaMargin.address)).toNumber(), 1134);
        await this.LuaMargin.updateReserve();
        await this.LuaMargin.withdraw(250, { from: bob });

        assert.equal((await this.USDT.balanceOf(this.LuaMargin.address)).toNumber(), 908);
        assert.equal((await this.LuaMargin.totalSupply()).toNumber(), 1000);
        assert.equal((await this.LuaMargin.balanceOf(bob)).toNumber(), 500);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 492);

        await this.LuaMargin.withdraw(500, { from: carol });

        assert.equal((await this.USDT.balanceOf(this.LuaMargin.address)).toNumber(), 454);
        assert.equal((await this.LuaMargin.totalSupply()).toNumber(), 500);
        assert.equal((await this.LuaMargin.balanceOf(carol)).toNumber(), 0);
        assert.equal((await this.USDT.balanceOf(carol)).toNumber(), 954);

        await this.LuaMargin.transferOut(alice, 300);
        await expectRevert(this.LuaMargin.withdraw(500, { from: bob }), 'LuaMargin: not enough balance')
        await expectRevert(this.LuaMargin.requestWithdraw(10, { from: bob }), 'LuaMargin: You can withdraw now')
        
        await this.LuaMargin.withdraw(10, { from: bob })
        assert.equal((await this.USDT.balanceOf(this.LuaMargin.address)).toNumber(), 145);
        assert.equal((await this.LuaMargin.totalSupply()).toNumber(), 490);
        assert.equal((await this.LuaMargin.balanceOf(bob)).toNumber(), 490);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 501);

        this.LuaMargin.requestWithdraw(490, { from: bob })
        await this.USDT.transfer(this.LuaMargin.address, 300, { from: alice });
        await this.LuaMargin.withdraw(490, { from: bob })
        assert.equal((await this.USDT.balanceOf(this.LuaMargin.address)).toNumber(), 0);
        assert.equal((await this.LuaMargin.totalSupply()).toNumber(), 0);
        assert.equal((await this.LuaMargin.balanceOf(bob)).toNumber(), 0);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 946);
    })
})