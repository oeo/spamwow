# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
{ L, log } = require './../lib/logger'
{ exit, env } = process

{ mongoose, redis } = require './../lib/database'

Schema = mongoose.Schema
{ basePlugin, EXPOSE } = require './../lib/models'

{ encrypt, decrypt } = require './../lib/crypto'
helpers = require './../lib/helpers'

AWS = require 'aws-sdk'
_ = require 'lodash'

AwsAccount = require './awsAccounts'
Domain = require './domains'

modelOpts = {
  name: 'EspAccount'
  schema: {
    collection: 'espaccounts'
    strict: false
  }
}

EspAccount = new Schema {

  name: {
    type: String
    required: true
    trim: true
  }

  provider: {
    type: String
    required: true
    enum: [
      'amazon-ses'
      'sendgrid'
    ]
  }

  # amazon ses specific fields
  AWS_ACCESS_KEY_ID: {
    type: String
    set: encrypt
    get: decrypt
  }

  AWS_SECRET_ACCESS_KEY: {
    type: String
    set: encrypt
    get: decrypt
  }

  AWS_REGION: {
    type: String
    enum: [
      'us-east-1'
      'us-east-2'
      'us-west-1'
      'us-west-2'
      'eu-west-1'
      'eu-central-1'
      'ap-south-1'
      'ap-southeast-1'
      'ap-southeast-2'
      'ap-northeast-1'
    ]
    default: 'us-east-1'
  }

  # sendgrid specific fields
  SENDGRID_API_KEY: {
    type: String
    set: encrypt
    get: decrypt
  }

  # health properties
  isHealthy: { type: Boolean, default: false }
  timeHealthChecked: { type: Number, default: 0 }

  # sending limits
  dailySendingLimit: { type: Number }
  hourlySendingLimit: { type: Number }

  # stats
  sentLast24h: { type: Number, default: 0 }
  sentLastHour: { type: Number, default: 0 }
  bounceRate: { type: Number, default: 0 }
  complaintRate: { type: Number, default: 0 }

}, modelOpts.schema

EspAccount.plugin(basePlugin)

EspAccount.methods._configureProvider = ->
  switch @provider
    when 'amazon-ses'
      AWS.config.update {
        accessKeyId: @AWS_ACCESS_KEY_ID
        secretAccessKey: @AWS_SECRET_ACCESS_KEY
        region: @AWS_REGION
      }

EspAccount.pre 'save', (next) ->
  @_configureProvider()

  if @isNew
    try
      switch @provider
        when 'amazon-ses'
          ses = new AWS.SES()
          await ses.getSendQuota().promise()
        when 'sendgrid'
          # validate sendgrid key
          headers = Authorization: "Bearer #{@SENDGRID_API_KEY}"
          response = await fetch 'https://api.sendgrid.com/v3/user/credits'
            headers: headers
          if !response.ok
            throw new Error 'Invalid SendGrid API key'
        # add other provider validations here

      @isHealthy = true
      @timeLastChecked = helpers.time()
      return next()

    catch error
      return next(new Error("Error validating ESP credentials: #{error.message}"))

  next()

# POST /espaccounts/:_id/checkHealth
EspAccount.methods.checkHealth = (opt = {}) ->
  @_configureProvider()

  try
    now = helpers.time()

    switch @provider
      when 'amazon-ses'
        ses = new AWS.SES()
        await ses.getSendQuota().promise()
      when 'sendgrid'
        headers = Authorization: "Bearer #{@SENDGRID_API_KEY}"
        response = await fetch 'https://api.sendgrid.com/v3/user/credits'
          headers: headers
        if !response.ok
          throw new Error 'Invalid SendGrid API key'
      # add other provider health checks here

    @isHealthy = true
    @timeHealthChecked = now

    try await @save()

    return true

  catch error
    @isHealthy = false
    @timeHealthChecked = now
    try await @save()
    throw new Error("Error validating ESP credentials: #{error.message}")

# POST /espaccounts/:_id/getDomainSettings
EspAccount.methods.getDomainSettings = ({ domain }) ->
  @_configureProvider()

  try
    switch @provider
      when 'amazon-ses'
        ses = new AWS.SES()
        result = await ses.getIdentityDkimAttributes(
          Identities: [domain]
        ).promise()
        return result
      when 'sendgrid'
        headers = Authorization: "Bearer #{@SENDGRID_API_KEY}"
        response = await fetch "https://api.sendgrid.com/v3/whitelabel/domains"
          headers: headers
        if !response.ok
          throw new Error 'Failed to get SendGrid domain settings'
        return await response.json()
      # add other provider implementations here

    return { message: "Domain settings retrieved successfully" }

  catch error
    L.error "Failed to get domain settings: #{error.message}"
    throw new Error "Failed to get domain settings: #{error.message}"

##
model = mongoose.model modelOpts.name, EspAccount
module.exports = EXPOSE(model)
