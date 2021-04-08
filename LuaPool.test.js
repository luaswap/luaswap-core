const { expectRevert, time, BN } = require('@openzeppelin/test-helpers')
const LuaPool = artifacts.require('LuaPool')
const MockERC20 = artifacts.require('MockERC20')

async function checkPool(pool, token) {
    assert.equal((await token.balanceOf(pool.address)).toNumber(), (await pool.reserve()).valueOf().toNumber() - (await pool.totalLoan()).valueOf().toNumber());
}

contract('LuaPool', ([alice, bob, carol, middleMan, minter]) => {
    beforeEach(async () => {
        this.USDT = await MockERC20.new('USDT', 'USDT', 1000000000, { from: alice })
        this.LuaPool = await LuaPool.new(this.USDT.address, { from: alice })
        await this.LuaPool.setMiddleMan(middleMan, true)
    })

    it('Correct setting', async () => {
        assert.equal(await this.LuaPool.token(), this.USDT.address);
        assert.equal(await this.LuaPool.reserve(), 0);
        assert.equal(await this.LuaPool.totalRequestWithdraw(), 0);
        assert.equal(await this.LuaPool.feeFlashLoan(), 1);
    })

    it('Correct deposit and withdraw', async () => {
        await this.USDT.transfer(bob, 1000, { from: alice });
        await this.USDT.approve(this.LuaPool.address, 1000, { from: bob });

        await expectRevert(this.LuaPool.deposit(50000, { from: bob }), "ERC20: transfer amount exceeds balance")
        await this.LuaPool.deposit(500, { from: bob });
        await checkPool(this.LuaPool, this.USDT)

        assert.equal((await this.LuaPool.totalSupply()).toNumber(), 500);
        assert.equal((await this.LuaPool.balanceOf(bob)).toNumber(), 500);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 500);

        await expectRevert(this.LuaPool.withdraw(1000, { from: bob }), 'LuaPool: wrong lpamount')
        await expectRevert(this.LuaPool.requestWithdraw(1000, { from: bob }), 'LuaPool: wrong lpamount')
        await expectRevert(this.LuaPool.requestWithdraw(500, { from: bob }), 'LuaPool: You can withdraw now')
        await expectRevert(this.LuaPool.requestWithdraw(100, { from: bob }), 'LuaPool: You can withdraw now')

        await expectRevert(this.LuaPool.loan(100, { from: carol }), 'LuaPool: Not middle man')
        await this.LuaPool.loan(100, { from: middleMan });
        await expectRevert(this.LuaPool.requestWithdraw(400, { from: bob }), 'LuaPool: You can withdraw now')
        await expectRevert(this.LuaPool.withdraw(500, { from: bob }), 'LuaPool: not enough balance')
        await checkPool(this.LuaPool, this.USDT)
        await this.LuaPool.withdraw(400, { from: bob });
        await checkPool(this.LuaPool, this.USDT)
        assert.equal((await this.LuaPool.totalSupply()).toNumber(), 100);
        assert.equal((await this.LuaPool.balanceOf(bob)).toNumber(), 100);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 900);

        await this.USDT.transfer(middleMan, 100, { from: alice });
        await this.USDT.transfer(this.LuaPool.address, 200, { from: middleMan });
        await this.LuaPool.repay(100, 200, { from: middleMan })
        await checkPool(this.LuaPool, this.USDT)
        await this.LuaPool.withdraw(100, { from: bob });
        assert.equal((await this.LuaPool.totalSupply()).toNumber(), 0);
        assert.equal((await this.LuaPool.balanceOf(bob)).toNumber(), 0);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 1100);
        await checkPool(this.LuaPool, this.USDT)
    })

    it('Correct deposit and withdraw with losing', async () => {
        await this.USDT.transfer(bob, 500, { from: alice });
        await this.USDT.approve(this.LuaPool.address, 1000, { from: bob });

        await this.LuaPool.deposit(500, { from: bob });
        await checkPool(this.LuaPool, this.USDT)

        await this.LuaPool.loan(100, { from: middleMan });
        await this.USDT.transfer(this.LuaPool.address, 50, { from: middleMan });
        await this.LuaPool.repay(100, 50, { from: middleMan })

        await checkPool(this.LuaPool, this.USDT)

        await this.LuaPool.withdraw(250, { from: bob });

        await checkPool(this.LuaPool, this.USDT)

        assert.equal((await this.LuaPool.totalSupply()).toNumber(), 250);
        assert.equal((await this.LuaPool.balanceOf(bob)).toNumber(), 250);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 225);

        await this.LuaPool.withdraw(250, { from: bob });

        await checkPool(this.LuaPool, this.USDT)


        assert.equal((await this.LuaPool.totalSupply()).toNumber(), 0);
        assert.equal((await this.LuaPool.balanceOf(bob)).toNumber(), 0);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 450);
    })

    it('Correct deposit and withdraw with 2 stakers', async () => {
        await this.USDT.transfer(bob, 1000, { from: alice });
        await this.USDT.transfer(carol, 1000, { from: alice });
        await this.USDT.transfer(middleMan, 1000, { from: alice });
        await this.USDT.approve(this.LuaPool.address, 1000, { from: bob });
        await this.USDT.approve(this.LuaPool.address, 1000, { from: carol });

        await this.LuaPool.deposit(500, { from: bob });
        await this.LuaPool.deposit(800, { from: carol });
        await this.LuaPool.deposit(500, { from: bob });

        assert.equal((await this.LuaPool.totalSupply()).toNumber(), 1800);
        assert.equal((await this.LuaPool.reserve()).toNumber(), 1800);
        assert.equal((await this.LuaPool.balanceOf(bob)).toNumber(), 1000);
        assert.equal((await this.LuaPool.balanceOf(carol)).toNumber(), 800);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 0);
        assert.equal((await this.USDT.balanceOf(carol)).toNumber(), 200);

        await expectRevert(this.LuaPool.withdraw(1000, { from: carol }), 'LuaPool: wrong lpamount')
        
        await this.LuaPool.withdraw(300, { from: carol })
        assert.equal((await this.LuaPool.reserve()).toNumber(), 1500);
        assert.equal((await this.USDT.balanceOf(carol)).toNumber(), 500);
        assert.equal((await this.LuaPool.balanceOf(carol)).toNumber(), 500);
        assert.equal((await this.USDT.balanceOf(this.LuaPool.address)).toNumber(), 1500);

        await this.LuaPool.loan(100, { from: middleMan })
        await this.USDT.transfer(this.LuaPool.address, 200, { from: middleMan });
        await this.LuaPool.repay(100, 200, { from: middleMan })
        assert.equal((await this.USDT.balanceOf(this.LuaPool.address)).toNumber(), 1600);
        assert.equal((await this.LuaPool.reserve()).toNumber(), 1600);
        await this.LuaPool.withdraw(250, { from: bob }); // total pool 1500 token
        
        assert.equal((await this.LuaPool.reserve()).toNumber(), 1334);
        assert.equal((await this.USDT.balanceOf(this.LuaPool.address)).toNumber(), 1334);
        assert.equal((await this.LuaPool.totalSupply()).toNumber(), 1250);
        assert.equal((await this.LuaPool.balanceOf(bob)).toNumber(), 750);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 266);

        await this.LuaPool.loan(200, {from: middleMan});
        assert.equal((await this.USDT.balanceOf(this.LuaPool.address)).toNumber(), 1134);
        assert.equal((await this.LuaPool.reserve()).toNumber(), 1334);
        await this.LuaPool.withdraw(250, { from: bob });

        assert.equal((await this.LuaPool.reserve()).toNumber(), 1068);
        assert.equal((await this.USDT.balanceOf(this.LuaPool.address)).toNumber(), 868);
        assert.equal((await this.LuaPool.totalSupply()).toNumber(), 1000);
        assert.equal((await this.LuaPool.balanceOf(bob)).toNumber(), 500);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 532);

        await this.LuaPool.withdraw(500, { from: carol });

        assert.equal((await this.LuaPool.reserve()).toNumber(), 534);
        assert.equal((await this.USDT.balanceOf(this.LuaPool.address)).toNumber(), 334);
        assert.equal((await this.LuaPool.totalSupply()).toNumber(), 500);
        assert.equal((await this.LuaPool.balanceOf(carol)).toNumber(), 0);
        assert.equal((await this.USDT.balanceOf(carol)).toNumber(), 1034);

        await this.LuaPool.loan(300, { from: middleMan });
        assert.equal((await this.LuaPool.reserve()).toNumber(), 534);
        assert.equal((await this.USDT.balanceOf(this.LuaPool.address)).toNumber(), 34);
        await expectRevert(this.LuaPool.withdraw(500, { from: bob }), 'LuaPool: not enough balance')
        await expectRevert(this.LuaPool.requestWithdraw(10, { from: bob }), 'LuaPool: You can withdraw now')
        
        await this.LuaPool.withdraw(10, { from: bob })
        assert.equal((await this.LuaPool.reserve()).toNumber(), 524);
        assert.equal((await this.USDT.balanceOf(this.LuaPool.address)).toNumber(), 24);
        assert.equal((await this.LuaPool.totalSupply()).toNumber(), 490);
        assert.equal((await this.LuaPool.balanceOf(bob)).toNumber(), 490);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 542);

        await this.LuaPool.requestWithdraw(490, { from: bob })
        await this.USDT.transfer(this.LuaPool.address, 310, { from: middleMan });
        await this.LuaPool.repay(300, 310, { from: middleMan });
        await expectRevert(this.LuaPool.withdraw(490, { from: bob }), 'LuaPool: not enough balance')
        await this.USDT.transfer(this.LuaPool.address, 250, { from: middleMan });
        await this.LuaPool.repay(200, 250, { from: middleMan });
        await this.LuaPool.withdraw(490, { from: bob })
        assert.equal((await this.USDT.balanceOf(this.LuaPool.address)).toNumber(), 0);
        assert.equal((await this.LuaPool.totalSupply()).toNumber(), 0);
        assert.equal((await this.LuaPool.balanceOf(bob)).toNumber(), 0);
        assert.equal((await this.USDT.balanceOf(bob)).toNumber(), 1126);
    })
})