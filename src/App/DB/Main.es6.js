
const pull = require('pull-stream')
const Reduce = require("flumeview-reduce")

exports.mkFlumeReducer =
  version => reducer => mapper => initial => {
    return Reduce(version, reducer, mapper, null, initial)
  }

exports.flumeUse =
  sbot => indexName => view => () =>
    sbot._flumeUse(indexName, view)

exports.liveStream =
  view => () => {
    return view.stream({live: true})
  }
