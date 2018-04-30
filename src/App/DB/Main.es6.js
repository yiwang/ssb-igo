
const Reduce = require("flumeview-reduce")

exports.mkFlumeReducer =
  version => reducer => mapper => initial =>
    Reduce(version, reducer, mapper, null, initial)

exports.flumeUse =
  sbot => indexName => view => () =>
    sbot._flumeUse(indexName, view)

exports.liveStream =
  view => () =>
    view.stream({live: true})
