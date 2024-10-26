# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
{ log } = console
{ env } = process

{ mongoose, redis } = require './../lib/database'

Schema = mongoose.Schema
{ basePlugin, EXPOSE } = require './../lib/models'

_ = require 'lodash'

AWS = require 'aws-sdk'

modelOpts = {
  name: 'Domain'
  schema: {
    collection: 'domains'
    strict: false
  }
}

Domain = new Schema {

  # aws account managing this domain
  awsAccount: {
    type: String
    ref: 'AwsAccount'
    required: true
  }

  # ourwebsite.com 
  domain: {
    type: String
    required: true
    unique: true
    lowercase: true
    trim: true
  }

  # mirroredwebsite.com 
  mirrorHost: {
    type: String
    lowercase: true
    trim: true
  }

  # dkim properties
  dkimSelector: { type: String, default: null }
  dkimPrivateKey: { type: String, default: null }
  timeDkimLastUpdated: { type: Number, default: 0 }

  # health properties
  isHealthy: { type: Boolean, default: false }
  timeLastChecked: { type: Number, default: 0 }

}, modelOpts.schema

Domain.plugin(basePlugin)

Domain.pre 'save', (next) ->
  if !@isNew
    if @isModified('dkimSelector') || @isModified('dkimPrivateKey')
      @timeDkimLastUpdated = helpers.time()

  next()

Domain.methods.checkHealth = (opt = {}) ->
  return next new Error 'Unimplemented'

# @note: this will create a DKIM and SPF record for the domain
# POST /domains/:id/configureDkim
Domain.methods.configureDkim = (opt = {}) ->
  try
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
    await @populate('awsAccount')

    if !@awsAccount
      throw new Error("AWS Account not found")

    try
      result = await @awsAccount.upsertDnsRecord({ domain: @domain, record })
      return result
    catch error
      throw new Error("Error upserting DNS record: #{error.message}")

# POST /domains/:id/pointToWebsite
Domain.methods.pointToWebsite = ({ ipAddress }) ->
  try
    await @populate('awsAccount')

    if !@awsAccount
      throw new Error("AWS Account not found")

    # create root A record
    rootRecord = {
      name: @domain
      type: 'A'
      ttl: 300
      value: ipAddress
    }

    # create www A record
    wwwRecord = {
      name: "www.#{@domain}"
      type: 'A'
      ttl: 300
      value: ipAddress
    }

    try
      # upsert both records
      await @awsAccount.upsertDnsRecord({ domain: @domain, record: rootRecord })
      await @awsAccount.upsertDnsRecord({ domain: @domain, record: wwwRecord })

      return {
        success: true
        message: "Domain pointed to website successfully"
      }
    catch error
      throw new Error("Error pointing domain to website: #{error.message}")

# GET /domains/:id/queryDnsRecords
Domain.methods.queryDnsRecords = (opt = {}) ->
  try
    await @populate('awsAccount')

    if !@awsAccount
      throw new Error("AWS Account not found")

    # initialize route 53 client
    @awsAccount._configureAWS()
    route53 = new AWS.Route53()

    # get hosted zone id for the domain
    listHostedZonesResponse = await route53.listHostedZonesByName({ DNSName: @domain }).promise()
    hostedZoneId = _.get(listHostedZonesResponse, 'HostedZones[0].Id')
    
    if !hostedZoneId
      throw new Error "No hosted zone found for domain #{@domain}"

    # get all records for the domain
    existingRecords = await route53.listResourceRecordSets({ HostedZoneId: hostedZoneId }).promise()

    # format records
    records = existingRecords.ResourceRecordSets.map (record) ->
      {
        name: record.Name
        type: record.Type
        ttl: record.TTL
        value: record.ResourceRecords?[0]?.Value
      }

    return records
  catch error
    throw new Error "Failed to query DNS records: #{error.message}"

model = mongoose.model modelOpts.name, Domain
module.exports = EXPOSE(model)
