# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
{ log } = console
{ env } = process

{ mongoose, redis } = require './../lib/database'

Schema = mongoose.Schema
{ basePlugin, EXPOSE } = require './../lib/models'

helpers = require './../lib/helpers'
macros = require './../lib/macros'

modelOpts = {
  name: 'Campaign'
  schema: {
    collection: 'campaigns'
    strict: false
  }
}

Campaign = new Schema {

  # esp account managing this campaign
  espAccount: {
    type: String
    ref: 'EspAccount'
    required: true
  }

  # domain used for sending
  domain: {
    type: String
    ref: 'Domain'
    required: true
  }

  name: {
    type: String
    required: true
    trim: true
  }

  # email content
  subject: {
    type: String
    required: true
    trim: true
  }

  fromName: {
    type: String
    required: true
    trim: true
  }

  fromEmail: {
    type: String
    required: true
    trim: true
    lowercase: true
  }

  replyToEmail: {
    type: String
    trim: true
    lowercase: true
  }

  htmlBody: {
    type: String
    required: true
  }

  textBody: {
    type: String
  }

  # campaign status
  status: {
    type: String
    enum: [
      'draft'      # initial state
      'queued'     # queue built (ready to send)
      'sending'    # actively sending
      'stopped'    # manually stopped 
      'completed'  # finished sending
      'failed'     # error occurred
    ]
    default: 'draft'
  }

  # rate limiting (emails per day, 0 = unlimited)
  dailyRateLimit: {
    type: Number
    default: 0
    min: 0
  }

  # calculated hourly rate (internal use)
  hourlyRateLimit: {
    type: Number
    default: 0
  }

  # targeting object for mongo query
  query: {
    type: Object
    default: {}
  }

  estimatedCount: { type: Number, default: 0 }

  # timing
  timeStarted: { type: Number, default: 0 }
  timeCompleted: { type: Number, default: 0 }

  lastSendAttempt: { type: Number, default: 0 }
  
  # stats
  emailsSent: { type: Number, default: 0 }
  emailsDelivered: { type: Number, default: 0 }
  emailsBounced: { type: Number, default: 0 }
  emailsOpened: { type: Number, default: 0 }
  emailsClicked: { type: Number, default: 0 }
  emailsUnsubscribed: { type: Number, default: 0 }
  emailsComplained: { type: Number, default: 0 }

}, modelOpts.schema

Campaign.plugin(basePlugin)

Campaign.pre 'save', (next) ->
  if @isModified('dailyRateLimit')
    # if daily rate is 0 (unlimited), hourly rate is also 0
    if @dailyRateLimit is 0
      @hourlyRateLimit = 0
    else
      # divide daily rate by 24 and round up to ensure we don't exceed daily limit
      @hourlyRateLimit = Math.ceil(@dailyRateLimit / 24)
  next()

model = mongoose.model modelOpts.name, Campaign
module.exports = EXPOSE(model)
