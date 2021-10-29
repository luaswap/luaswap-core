var fs = require('fs')
var path = require('path')
const BigNumber = require('bignumber.js')
var abi = require('./balphamasterabi.js')
const Web3 = require('web3')
const web3 = new Web3('http://135.125.8.163:8585')
BigNumber.config({ DECIMAL_PLACES: 10, ROUNDING_MODE: 4, EXPONENTIAL_AT: [-50, 50] })
let contract = new web3.eth.Contract(abi, '0x5289d1a9C889b758269C3913136791b2D52d996A')
var lines = fs.readFileSync(path.join(__dirname, './tx.csv'), 'utf8').trim().split('\n')

var addresses = []


function getReward(i, cb) {
  var add = addresses[i]
  if (!add) {
    cb && cb();
    return;
  };
  var promise = []
  console.log(i, add)
  for (let id = 0; id < 8; id++) {
    promise.push(new Promise((resolve, reject) => {
      contract.methods.pendingReward(id, add).call({
        from: add,
      }, 35466888, (err, data) => {
        if (err) return reject(err)
        resolve([id, data])
      })
    }))
  }
  Promise.all(promise)
  .then(e => {
    addresses[i] = {
      address: add,
      reward: e.map(v => v[1]).join(','),
      total: e.reduce((s, v) => s.plus(new BigNumber(v[1])), new BigNumber(0)).toString()
    }
    fs.appendFileSync(path.join(__dirname, './reward.csv'), `${add},${e.reduce((s, v) => s.plus(new BigNumber(v[1])), new BigNumber(0)).toString()},${e.map(v => v[1]).join(',')}\n`)
    getReward(++i, cb)
  })
  .catch(ex => {
    cb && cb(ex)
  })
}

lines.forEach(e => {
  var add = e.split(',')[3].toLowerCase().replace(/"/gi, '')
  if (addresses.indexOf(add) < 0) {
    addresses.push(add)
  }
})
console.log(addresses.length);

addresses = addresses.sort()
fs.writeFileSync(path.join(__dirname, './addresses.txt'), addresses.join('\n'))

getReward(addresses.indexOf('') + 1, (ex) => {
  if (ex) console.log('Error', ex)
  else {
    fs.writeFileSync(path.join(__dirname, './rewards-json.json'), JSON.stringify(addresses, null, 4))
  }
})