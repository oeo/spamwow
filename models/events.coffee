# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
{ log } = console
{ env } = process

{ mongoose, redis } = require './../lib/database'

Schema = mongoose.Schema
{ basePlugin, EXPOSE } = require './../lib/models'

modelOpts = {
  name: 'Event'
  schema: {
    collection: 'events'
    strict: false
  }
}

Event = new Schema {

  event: {
    type: String
    required: true
  }

  email: {
    type: String
    ref: 'Email'
  }

  domain: {
    type: String
    ref: 'Domain'
  }

  campaign: {
    type: String
    ref: 'Campaign'
  }

}, modelOpts.schema

Event.plugin(basePlugin)

# POST /events/ping
Event.statics.ping = ({ pong }) ->
  return { pong }

model = mongoose.model modelOpts.name, Event
module.exports = EXPOSE(model)

