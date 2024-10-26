# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
{ log } = console
{ env } = process

{ mongoose, redis } = require './../lib/database'

Schema = mongoose.Schema
{ basePlugin, EXPOSE } = require './../lib/models'

modelOpts = {
  name: 'Domain'
  schema: {
    collection: 'domains'
    strict: false
  }
}

Domain = new Schema {

  active: { type: Boolean, default: true }

  # our-domain-name.com
  domain: {
    type: String
    required: true
    unique: true
    lowercase: true
    trim: true
  }

  # real-domain-name.com
  originHost: {
    type: String
    required: true
    lowercase: true
    trim: true
  }

  # localhost:someport
  mitmHost: {
    type: String
    required: true
  }

  healthy: {
    type: Boolean
    default: false
  }

  timeLastChecked: {
    type: Number
    default: 0
  }

}, modelOpts.schema

Domain.plugin(basePlugin)

Domain.pre 'save', (next) ->
  next()

Domain.methods.checkHealth = (opt = {}) ->

  # @todo: ping domain
  # @todo: ping mitmHost
  # @todo: ping originHost

  return next new Error 'Unimplemented'

model = mongoose.model modelOpts.name, Domain
module.exports = EXPOSE(model)

