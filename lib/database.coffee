# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
{ env, exit } = process
{ log, L } = require './logger'
{ emit } = require './emitter'

_ = require 'lodash'

mongoose = require 'mongoose'
IORedis = require 'ioredis'

Trk2 = require 'trk2'

connections = {
  redis: 0
  mongo: 0
}

# mongo
mongoose.connect env.MONGODB_URI
  .catch (error) -> L.error error
  .then ->
    connections.mongo = true
    L 'connected to mongo'
  .catch (error) -> L.error error

# redis
console.log env.REDIS_URI
redis = new IORedis env.REDIS_URI
  .on 'error', (error) -> L.error error
  .on 'connect', ->
    connections.redis = true
    L 'connected to redis'

trk2 = new Trk2 {
  redis,
  prefix: 'trk2'
  map: {
    bmp: [
      'ip'
      'email'
    ]
    add: [
      'event'
      'event~awsaccount'
      'event~campaign'
    ]
    addv: [
      
    ]
    top: [

    ]
  }
}

# ready promise
connected = ready = ->
  new Promise (resolve, reject) ->
    check = ->
      if _.sum(_.values(connections)) is _.size(connections)
        resolve()
        clearInterval _check

    _check = setInterval check, 1
    check()

module.exports = {
  mongoose
  redis
  connected
  ready
}

