
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

const name = process.argv[2]
const port = process.argv[3]

const sbot = startSbot(`./ssb-dev/${name}`, port)

sbot.publish({
  type: 'about',
  about: sbot.id,
  name: name,
}, () => {})

process.send({
  name, port, id: sbot.id
})

process.on('message', ({gossip, contact}) => {
  console.log('gossip', gossip, 'contact', contact)
  sbot.gossip.enable('local', (err, _) => {
    sbot.gossip.add(gossip)
  })
  sbot.publish(contact, () => {})
})
