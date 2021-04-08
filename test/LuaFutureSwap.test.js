
const { expectRevert, time, BN } = require('@openzeppelin/test-helpers')
const LuaPool = artifacts.require('LuaPool')
const LuaFutureSwap = artifacts.require('LuaFutureSwap')
const UniswapV2Factory = artifacts.require('UniswapV2Factory')
const UniswapV2Pair = artifacts.require('UniswapV2Pair')
const UniswapV2Router = artifacts.require('UniswapV2Router02')
const MockERC20 = artifacts.require('MockERC20')

var that = null

async function checkPool(pool, token) {
    assert.equal((await token.balanceOf(pool.address)).toNumber(), (await pool.reserve()).valueOf().toNumber() - (await pool.totalLoan()).valueOf().toNumber());
}

async function balance(user, userName) {
    console.log('---BALANCE---')
    console.log('USDT | LuaFutureSwap:', (await that.USDT.balanceOf(that.LuaFutureSwap.address)).toString())
    console.log('WETH | LuaFutureSwap:', (await that.WETH.balanceOf(that.LuaFutureSwap.address)).toString())

    console.log('USDT | LuaPool:', (await that.USDT.balanceOf(that.LuaPool.address)).toString())
    console.log('WETH | LuaPool:', (await that.WETH.balanceOf(that.LuaPool.address)).toString())

    if (user) {
        console.log(`USDT | ${userName}:`, (await that.USDT.balanceOf(user)).toString())
        console.log(`WETH | ${userName}:`, (await that.WETH.balanceOf(user)).toString())
    }
    console.log('')
}

async function amountOut(TOKEN0, TOKEN1, amount) {
    return (await that.UniswapV2Router.getAmountsOut(amount, [TOKEN0.address, TOKEN1.address]))[1].toNumber()
}

async function position(pid) {
    var p = await that.LuaFutureSwap.positions(pid)
    if (p.amount > 0) {
        var v = await amountOut(that.WETH, that.USDT, p.amount)
    }
    console.log('---POSITION---')
    console.log('collateral:', p.collateral.toString())
    console.log('borrowing:', p.borrowing.toString())
    console.log('amount:', p.amount.toString())
    console.log('openedAtBlock:', p.openedAtBlock.toString())
    console.log('owner:', p.owner.toString())
    if (v) {
        console.log('out: ', v, `(${Math.round(v / (p.collateral.toNumber() + p.borrowing.toNumber()) * 100)})`)
    }
    console.log('')
}

contract('LuaFutureSwap', ([owner, alice, bob, carol, minter]) => {
    beforeEach(async () => {
        
        this.USDT = await MockERC20.new('USDT', 'USDT', 1000000000, { from: owner })
        this.WETH = await MockERC20.new('WETH', 'WETH', 1000000000, { from: owner })

        this.UniswapFactory = await UniswapV2Factory.new(owner, { from: owner })
        this.UniswapV2Router = await UniswapV2Router.new(this.UniswapFactory.address, this.WETH.address, { from: owner })
        await this.UniswapFactory.createPair(this.USDT.address, this.WETH.address);
        this.WETHUSDT = await this.UniswapFactory.getPair(this.WETH.address, this.USDT.address);
        this.WETHUSDT = await UniswapV2Pair.at(this.WETHUSDT, { from: owner });
        this.USDT.transfer(this.WETHUSDT.address, 5000, { from: owner })
        this.WETH.transfer(this.WETHUSDT.address, 5000, { from: owner })
        this.WETHUSDT.mint(owner, { from: owner });

        this.LuaPool = await LuaPool.new(this.USDT.address, { from: owner })
        this.LuaFutureSwap = await LuaFutureSwap.new(this.WETH.address, this.LuaPool.address, this.WETHUSDT.address, 4)

        await this.LuaPool.setMiddleMan(this.LuaFutureSwap.address, true)

        await this.USDT.approve(this.LuaPool.address, 10000, { from: owner });
        await this.LuaPool.deposit(10000, { from: owner });

        await this.USDT.transfer(alice, 2000, { from: owner })
        await this.WETH.transfer(alice, 2000, { from: owner })

        await this.USDT.approve(this.LuaFutureSwap.address, 100000000000000, { from: alice });
        await this.WETH.approve(this.LuaFutureSwap.address, 100000000000000, { from: alice });

        await this.USDT.approve(this.UniswapV2Router.address, 100000000000000, { from: owner });
        await this.WETH.approve(this.UniswapV2Router.address, 100000000000000, { from: owner });

        that = this;
    })

    it('Open position', async () => {
        await this.LuaFutureSwap.openPosition(100, 400, 0, 99999999999, { from: alice });
        assert.equal(await this.LuaFutureSwap.positionIdsOf(alice, 0), 1)
        await this.LuaFutureSwap.openPosition(300, 500, 0, 99999999999, { from: alice });
        assert.equal(await this.LuaFutureSwap.positionIdsOf(alice, 1), 2)

        assert.equal(await this.USDT.balanceOf(alice), 1600)
        var p1 = await this.LuaFutureSwap.positions(1);
        assert.equal(p1.collateral, 100)
        assert.equal(p1.borrowing, 400)

        var p2 = await this.LuaFutureSwap.positions(2);
        assert.equal(p2.collateral, 300)
        assert.equal(p2.borrowing, 500)

        assert.equal(await this.LuaFutureSwap.numberOfPosition(alice), 2)
        assert.equal(await this.WETH.balanceOf(this.LuaFutureSwap.address), p1.amount.toNumber() + p2.amount.toNumber())
        assert.equal(await this.LuaFutureSwap.numberOfPosition(alice), 2)
    })

    it('expand position', async () => {
        await this.LuaFutureSwap.openPosition(100, 400, 0, 99999999999, { from: alice });
        await this.LuaFutureSwap.expandPosition(1, 300, 500, 0, 99999999999, { from: alice });

        assert.equal(await this.LuaFutureSwap.positionIdsOf(alice, 0), 1)
        assert.equal(await this.LuaFutureSwap.numberOfPosition(alice), 1)

        assert.equal(await this.USDT.balanceOf(alice), 1600)
        var p = await this.LuaFutureSwap.positions(1);
        assert.equal(p.collateral, 400)
        assert.equal(p.borrowing, 900)
    })

    it('Add more fund to position', async () => {
        await this.LuaFutureSwap.openPosition(100, 400, 0, 99999999999, { from: alice });
        await this.LuaFutureSwap.addMoreFund(1, 300, { from: alice });
        assert.equal(await this.USDT.balanceOf(alice), 1600)
        var p = await this.LuaFutureSwap.positions(1);
        assert.equal(p.collateral, 400)
        assert.equal(p.borrowing, 115)
    })

    it('Close position', async () => {
        await this.LuaFutureSwap.openPosition(100, 400, 0, 99999999999, { from: alice });
        var p = await this.LuaFutureSwap.positions(1);
        await this.LuaFutureSwap.closePosition(1, p.amount / 2, { from: alice });
        var p2 = await this.LuaFutureSwap.positions(1);
        assert.equal(p2.collateral, 50)
        assert.equal(p2.borrowing, 200)
        assert.equal(p2.amount, p.amount / 2)

        await this.LuaFutureSwap.closePosition(1, p.amount - p.amount / 2, { from: alice });
        p2 = await this.LuaFutureSwap.positions(1);
        assert.equal(p2.collateral, 0)
        assert.equal(p2.borrowing, 0)
        assert.equal(p2.amount, 0)
        assert.equal(await this.LuaFutureSwap.numberOfPosition(alice), 0)
        assert.equal(await this.USDT.balanceOf(this.LuaPool.address), 10020)
        assert.equal(await this.USDT.balanceOf(this.LuaFutureSwap.address), 0)
        assert.equal(await this.WETH.balanceOf(this.LuaFutureSwap.address), 0)
    })
})