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

Domain = require './domains'

modelOpts = {
  name: 'AwsAccount'
  schema: {
    collection: 'awsaccounts'
    strict: false
  }
}

AwsAccount = new Schema {

  name: {
    type: String
    required: true
    trim: true
  }

  AWS_ACCOUNT_ID: {
    type: Number
    unique: true
    required: true
  }

  AWS_ACCESS_KEY_ID: {
    type: String
    required: true
    set: encrypt
    get: decrypt
  }

  AWS_SECRET_ACCESS_KEY: {
    type: String
    required: true
    set: encrypt
    get: decrypt
  }

  AWS_REGION: {
    type: String
    required: true
    enum: [
      'us-east-1'
      'us-east-2'
      'us-west-1'
      'us-west-2'
      'ca-central-1'
      'ca-west-1'
      'eu-north-1'
      'eu-west-3'
      'eu-west-2'
      'eu-west-1'
      'eu-central-1'
      'eu-south-1'
      'eu-south-2'
      'eu-central-2'
      'ap-south-1'
      'ap-northeast-1'
      'ap-northeast-2'
      'ap-northeast-3'
      'ap-southeast-1'
      'ap-southeast-2'
      'ap-southeast-3'
      'ap-east-1'
      'sa-east-1'
      'cn-north-1'
      'cn-northwest-1'
      'us-gov-east-1'
      'us-gov-west-1'
      'us-isob-east-1'
      'us-iso-east-1'
      'us-iso-west-1'
      'me-south-1'
      'af-south-1'
      'me-central-1'
      'ap-south-2'
      'ap-southeast-4'
      'il-central-1'
      'ap-southeast-5'
    ]
    default: 'us-east-1'
  }

  # health properties
  isHealthy: { type: Boolean, default: false }
  timeHealthChecked: { type: Number, default: 0 }

}, modelOpts.schema

AwsAccount.plugin(basePlugin)

AwsAccount.methods._configureAWS = -> 
  AWS.config.update {
    accessKeyId: @AWS_ACCESS_KEY_ID,
    secretAccessKey: @AWS_SECRET_ACCESS_KEY,
    region: @AWS_REGION
  }

AwsAccount.pre 'save', (next) ->
  @_configureAWS()

  if @isNew
    try
      sts = new AWS.STS()
      data = await sts.getCallerIdentity().promise()
      
      @AWS_ACCOUNT_ID = +data.Account

      @isHealthy = true
      @timeLastChecked = helpers.time() 

      try
        L "Syncing domains for new AWS account"
        await @syncDomains()
      catch error
        # we don't want to prevent the account from being created if syncing fails
        # so we'll just log the error and continue
        L.error("Error syncing domains for new AWS account:", error)

      # credentials are valid
      return next()

    catch error
      return next(new Error("Error validating AWS credentials: #{error.message}"))

  next()

# POST /awsaccounts/:_id/checkHealth
AwsAccount.methods.checkHealth = (opt = {}) ->
  @_configureAWS()

  try
    sts = new AWS.STS()

    data = await sts.getCallerIdentity().promise()

    now = helpers.time()

    if +data?.Account != @AWS_ACCOUNT_ID
      @isHealthy = false
      @timeHealthChecked = now 
      try await @save()

      throw new Error "AWS credentials are invalid"
  
    @isHealthy = true
    @timeHealthChecked = now

    try await @save()

    return true 

  catch error
    throw new Error("Error validating AWS credentials: #{error.message}")

# @note: this will eventually create an entry in the domains collection
# POST /awsaccounts/:_id/purchaseDomain
AwsAccount.methods.purchaseDomain = ({ domain }) ->
  @_configureAWS()

  try
    route53Domains = new AWS.Route53Domains()

    params = {
      DomainName: domain
      AutoRenew: false 
      DurationInYears: 1
    }

    result = await route53Domains.registerDomain(params).promise()

    # validate that the domain was actually registered
    try
      domainDetails = await route53Domains.getDomainDetail({ DomainName: domain }).promise()

      if domainDetails.DomainName isnt domain
        throw new Error("Domain registration failed: Domain not found after registration")

    catch error
      throw new Error("Failed to validate domain registration: #{error.message}")

    # Create a domain entry in the domains collection
    newDomain = new Domain({
      awsAccount: @_id
      domain: domain
    })

    try
      await newDomain.save()
    catch error
      throw new Error("Failed to save domain in database: #{error.message}")

    return newDomain

  catch error
    L.error "Failed to purchase domain: #{error.message}"
    throw new Error "Failed to purchase domain: #{error.message}"

# POST /awsaccounts/:_id/listDomains
AwsAccount.methods.listDomains = (opt = {}) ->
  @_configureAWS()

  try
    route53Domains = new AWS.Route53Domains()
    result = await route53Domains.listDomains({}).promise()

    domains = result.Domains.map (domain) ->
      {
        DomainName: domain.DomainName
        AutoRenew: domain.AutoRenew
        TransferLock: domain.TransferLock
        Expiry: domain.Expiry
      }

    return domains
  catch error
    L.error "Failed to list domains: #{error.message}"
    throw new Error "Failed to list domains: #{error.message}"

# @note: this will create an entry in the domains collection
# for each domain that is registered in this AWS account
# POST /awsaccounts/:_id/syncDomains
AwsAccount.methods.syncDomains = (opt = {}) ->
  @_configureAWS()

  try
    route53Domains = new AWS.Route53Domains()
    result = await route53Domains.listDomains({}).promise()

    for domain in result.Domains
      existingDomain = await Domain.findOne({ domain: domain.DomainName })
      
      if !existingDomain
        newDomain = new Domain({
          awsAccount: @_id
          domain: domain.DomainName
        })
        
        try
          await newDomain.save()
          L "Added new domain: #{domain.DomainName}"

          # configure DKIM and SPF for the new domain
          if opt.configureDkim
            L "Configuring DKIM and SPF for new domain: #{domain.DomainName}"
            await newDomain.configureDkim()

        catch error
          L.error "Failed to save domain #{domain.DomainName}: #{error.message}"
      else
        L "Domain already exists: #{domain.DomainName}"

    return { message: "Domains synced successfully" }
  catch error
    L.error "Failed to sync domains: #{error.message}"
    throw new Error "Failed to sync domains: #{error.message}"

# @note: this will create a DKIM and SPF record for the domain
# POST /awsaccounts/:_id/configureDkim
AwsAccount.methods.configureDkim = ({ domain, spfInclude = [] }) ->
  @_configureAWS()

  try
    # verify domain is in this AWS account
    route53Domains = new AWS.Route53Domains()

    try
      await route53Domains.getDomainDetail({ DomainName: domain }).promise()
    catch error
      if error.code is 'DomainNotFound'
        throw new Error "Domain #{domain} is not in this AWS account"
      throw error

    route53 = new AWS.Route53()

    # get hosted zone id for the domain
    listHostedZonesResponse = await route53.listHostedZonesByName({ DNSName: domain }).promise()
    hostedZoneId = _.get(listHostedZonesResponse, 'HostedZones[0].Id')
    
    if !hostedZoneId
      throw new Error "No hosted zone found for domain #{domain}"

    # delete existing dkim and spf records if any
    existingRecords = await route53.listResourceRecordSets({ HostedZoneId: hostedZoneId }).promise()

    changesToDelete = _.chain(existingRecords.ResourceRecordSets)
      .filter((record) -> 
        record.Type in ['TXT', 'CNAME'] and (_.includes(record.Name, '_domainkey') or record.Name is "#{domain}.")
      )
      .map((record) -> 
        {
          Action: 'DELETE'
          ResourceRecordSet: record
        }
      )
      .value()

    if changesToDelete
      try
        await route53.changeResourceRecordSets({
          HostedZoneId: hostedZoneId
          ChangeBatch: { Changes: changesToDelete }
        }).promise()
        # wait a bit for deletion to propagate
        await new Promise (resolve) -> setTimeout(resolve, 5000)
      catch error
        L.error "Failed to delete existing records: #{error.message}"
        # continue anyway since records may not exist

    # generate new dkim keys
    { publicKey, privateKey } = await new Promise (resolve, reject) ->
      require('crypto').generateKeyPair 'rsa',
        modulusLength: 2048
        publicKeyEncoding: { type: 'spki', format: 'pem' }
        privateKeyEncoding: { type: 'pkcs8', format: 'pem' }
        (err, publicKey, privateKey) ->
          if err then reject(err) else resolve({ publicKey, privateKey })

    # create dkim dns records
    dkimSelector = "dkim1"
    dkimRecord = _.chain(publicKey)
      .replace(/-----BEGIN PUBLIC KEY-----/, '')
      .replace(/-----END PUBLIC KEY-----/, '')
      .replace(/\s+/g, '')
      .value()
    
    # split the dkim record into chunks of 250 characters
    stringToRoute53Safe = (string) ->
      splitString = (string[i..(i + 249)] for i in [0...string.length] by 250)
      splitString.map((v) -> "\"#{v}\"").join(' ')
    
    dkimValue = "v=DKIM1; k=rsa; p=#{dkimRecord}"
    dkimSafeValue = stringToRoute53Safe(dkimValue)
    
    dkimChanges = [
      {
        Action: 'UPSERT'
        ResourceRecordSet:
          Name: "#{dkimSelector}._domainkey.#{domain}"
          Type: 'TXT'
          TTL: 300
          ResourceRecords: [{ Value: dkimSafeValue }]
      }
    ]
    # create spf record with core email providers
    defaultIncludes = [
      '_spf.google.com'                # google workspace
      'amazonses.com'                  # amazon ses
      'sendgrid.net'                   # sendgrid
      'spf.protection.outlook.com'     # microsoft 365
      'mailgun.org'                    # mailgun
    ]
    
    allIncludes = _.uniq([...defaultIncludes, ...spfInclude])
    
    # split spf includes into chunks to avoid route53 length limits
    spfChunks = []
    currentChunk = []
    currentLength = 0
    
    for include in allIncludes
      includeStr = "include:#{include}"

      # account for spaces and quotes in final string
      if currentLength + includeStr.length + 10 > 250
        spfChunks.push currentChunk
        currentChunk = []
        currentLength = 0
      
      currentChunk.push includeStr
      currentLength += includeStr.length + 1
    
    spfChunks.push currentChunk if currentChunk.length
    
    # create spf value with mechanism chunks
    spfValue = spfChunks.map((chunk) -> 
      "v=spf1 #{chunk.join(' ')} ~all"
    ).join('')

    spfChanges = [
      {
        Action: 'UPSERT'
        ResourceRecordSet:
          Name: domain
          Type: 'TXT'
          TTL: 300
          ResourceRecords: [{ Value: "\"#{spfValue}\"" }]
      }
    ]

    # apply dns changes
    await route53.changeResourceRecordSets({
      HostedZoneId: hostedZoneId
      ChangeBatch: { Changes: [...dkimChanges, ...spfChanges] }
    }).promise()

    return {
      success: true
      message: "DKIM and SPF records configured successfully"
      dkimSelector: dkimSelector
      dkimPrivateKey: privateKey
    }

  catch error
    L.error "Failed to configure DKIM: #{error.message}"
    throw new Error "Failed to configure DKIM: #{error.message}"

# @note: this will create a DNS record for a domain
# POST /awsaccounts/:_id/upsertDnsRecord
AwsAccount.methods.upsertDnsRecord = ({ domain, record }) ->
  @_configureAWS()

  try
    route53 = new AWS.Route53()

    # find the hosted zone id for the domain
    listHostedZonesResponse = await route53.listHostedZones().promise()
    hostedZone = listHostedZonesResponse.HostedZones.find (zone) -> zone.Name == "#{domain}."

    unless hostedZone
      throw new Error "Hosted zone not found for domain: #{domain}"

    hostedZoneId = hostedZone.Id

    # prepare the change batch
    change = {
      Action: 'UPSERT'
      ResourceRecordSet:
        Name: record.name
        Type: record.type
        TTL: record.ttl || 300
        ResourceRecords: [{ Value: record.value }]
    }

    # apply dns changes
    await route53.changeResourceRecordSets({
      HostedZoneId: hostedZoneId
      ChangeBatch: { Changes: [change] }
    }).promise()

    return {
      success: true
      message: "DNS record upserted successfully"
      record: record
    }

  catch error
    L.error "Failed to upsert DNS record: #{error.message}"
    throw new Error "Failed to upsert DNS record: #{error.message}"

##
model = mongoose.model modelOpts.name, AwsAccount
module.exports = EXPOSE(model)
