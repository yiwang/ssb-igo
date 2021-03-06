
const fs = require('fs')
const path = require('path')
const pull = require('pull-stream')
const ssbKeys = require('ssb-keys')
const {ssbIgoPlugin} = require('../output/App.DB.Main')

const sbotBuilder =
  require('scuttlebot')
  .use(require("scuttlebot/plugins/master"))
  .use(require("scuttlebot/plugins/gossip"))
  .use(require("scuttlebot/plugins/replicate"))
  .use(require("ssb-private"))
  .use(require("ssb-friends"))
  .use(ssbIgoPlugin)

function dumpManifest(sbot, filePath) {
  const manifest = JSON.stringify(sbot.getManifest())
  fs.writeFileSync(path.join(filePath, "manifest.json"), manifest)
}

function startSbot (path, port) {
  console.log(`starting sbot in ${path} at port ${port}`)
  const keyz = ssbKeys.loadOrCreateSync(path + "/secret")

  const config = require('ssb-config/inject')('ssb', {
    path: path,
    keys: keyz,
    host: "localhost",
    port: port,
    master: keyz.id,
    caps: {
      shs: process.env.SBOT_SHS || "GVZDyNf1TrZuGv3W5Dpef0vaITW1UqOUO3aWLNBp+7A=",
      sign: process.env.SBOT_SIGN || null,
    }
  });

  const sbot = sbotBuilder(config)
  dumpManifest(sbot, path)

  return sbot
}

const main = startSbot('./ssb-data', 8008)
const devs = ['alice', 'bob', 'charlie'].map((name, i) => {
  const port = 8081 + i
  const sbot = startSbot(`./ssb-dev/${name}`, port)
  sbot.port = port
  sbot.name = name
  return sbot
})

if (process.argv[2]) {
  let pubs = 0
  console.log("Setting up follow graph")
  devs.forEach(dev1 => {
    dev1.publish({
      type: 'about',
      about: dev1.id,
      name: dev1.name,
    }, () => {})
    devs.forEach(dev2 => {
      if (dev1.id !== dev2.id) {
        console.log(`${dev1.name} => ${dev2.name}`)
        dev1.gossip.enable('local', (err, blah) => {
          dev1.gossip.add({
            host: 'localhost',
            port: dev2.port,
            key: dev2.id,
          })
        })
        dev1.publish({
          type: 'contact',
          contact: dev2.id,
          following: true,
        }, () => {})//, (err, msg) => {if (++pubs == 6) feed0()})
      }
    })
  })
} else {

}
