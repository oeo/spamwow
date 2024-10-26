# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
{ log } = console
{ env } = process

{ mongoose, redis } = require './../lib/database'

Schema = mongoose.Schema
{ basePlugin, EXPOSE } = require './../lib/models'

_ = require 'lodash'

modelOpts = {
  name: 'Domain'
  schema: {
    collection: 'domains'
    strict: false
  }
}

# mirror domains
Domain = new Schema {

  # aws account managing this domain
  awsAccount: {
    type: String
    ref: 'AwsAccount'
    required: true
  }

  # our-domain-name.com
  domain: {
    type: String
    required: true
    unique: true
    lowercase: true
    trim: true
  }

  # real-domain-name.com
  mirrorHost: {
    type: String
    lowercase: true
    trim: true
  }

  dkimSelector: {
    type: String
    default: null 
  }

  dkimPrivateKey: { 
    type: String
    default: null 
  }

  isHealthy: {
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
  return next new Error 'Unimplemented'

# @note: this will create a DKIM and SPF record for the domain
# POST /domains/:id/configureDkim
Domain.methods.configureDkim = (opt = {}) ->
  try
    # Populate the awsAccount field
    await @populate('awsAccount')

    if !@awsAccount
      throw new Error("AWS Account not found")

    result = await @awsAccount.configureDkim({ domain: @domain })
    
    if result.success
      @dkimSelector = result.dkimSelector
      @dkimPrivateKey = result.dkimPrivateKey
      await @save()
      
      return {
        success: true,
        message: "DKIM and SPF configured successfully",
        dkimSelector: @dkimSelector
      }
    else
      throw new Error(result.message || "Failed to configure DKIM and SPF")
  catch error
    throw new Error("Error configuring DKIM and SPF: #{error.message}")

# POST /domains/:id/upsertDnsRecord
Domain.methods.upsertDnsRecord = ({ record }) ->
  try
    # Populate the awsAccount field
    await @populate('awsAccount')

    if !@awsAccount
      throw new Error("AWS Account not found")

    try
      result = await @awsAccount.upsertDnsRecord({ domain: @domain, record })
      return result
    catch error
      throw new Error("Error upserting DNS record: #{error.message}")

# GET /domains/:id/queryDnsRecords
Domain.methods.queryDnsRecords = (opt = {}) ->
  try
    dns = require 'dns'
    { promisify } = require 'util'

    resolveAny = promisify(dns.resolveAny)
    records = await resolveAny(@domain)

    formattedRecords = records.map (record) ->
      {
        type: record.type
        value: record.address or record.exchange or record.value
        ttl: record.ttl
      }

    return formattedRecords
  catch error
    throw new Error "Failed to query DNS records: #{error.message}"

model = mongoose.model modelOpts.name, Domain
module.exports = EXPOSE(model)
