# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
{ log } = console
{ env } = process

{ mongoose, redis } = require './../lib/database'
dns = require 'dns'
{ promisify } = require 'util'

Schema = mongoose.Schema
{ basePlugin, EXPOSE } = require './../lib/models'

helpers = require './../lib/helpers'

modelOpts = {
  name: 'EmailDns'
  schema: {
    collection: 'emaildns'
    strict: false
  }
}

PROVIDER_MAPPING = {
  'gmail.com': ['googlemail.com', 'google.com'],
  'outlook.com': ['hotmail.com', 'live.com', 'msn.com'],
  'yahoo.com': ['ymail.com', 'rocketmail.com']
}

COMMON_PROVIDERS = Object.keys(PROVIDER_MAPPING).concat(
  Object.values(PROVIDER_MAPPING).flat()
)

EMAIL_BITMAP_KEY = 'email:checked'

detectProvider = (domain) ->
  for provider, aliases of PROVIDER_MAPPING
    if domain is provider or domain in aliases
      return provider
  null

isCustomProviderDomain = (domain, mxRecords) ->
  if mxRecords.length > 0
    mxDomain = mxRecords[0].exchange.toLowerCase()
    for provider, aliases of PROVIDER_MAPPING
      if mxDomain.includes(provider) or aliases.some((alias) -> mxDomain.includes(alias))
        return provider
  null

resolveMx = promisify(dns.resolveMx)

getMXRecords = (domain) ->
  try
    records = await resolveMx(domain)
    records.sort((a, b) -> a.priority - b.priority)
  catch error
    console.error("Error resolving MX for #{domain}:", error)
    []

# Model definition
EmailDns = new Schema {
  domain: {
    type: String
    required: true
    unique: true
    lowercase: true
    trim: true
    index: true
  }

  provider: {
    type: String
    lowercase: true
    trim: true
    index: true
  }

  isValid: {
    type: Boolean
    default: false
  }

  isCustomDomain: {
    type: Boolean
    default: false
  }

  mxRecords: [{
    exchange: String
    priority: Number
  }]

  frequency: {
    type: Number
    default: 0
  }

  firstSeen: {
    type: Number
    default: 0
  }

  lastChecked: {
    type: Number
    default: 0
  }

}, modelOpts.schema

EmailDns.plugin(basePlugin)

# Static methods
EMAIL_BITMAP_KEY = 'email:checked'

EmailDns.statics.verifyDomain = ({ email }) ->
  [, domain] = email.split('@')

  # Check if email has been checked before
  emailChecked = await redis.getbit(EMAIL_BITMAP_KEY, helpers.hash(email))

  if emailChecked
    # email already checked, just return the existing record
    return await @findOne({ domain })

  # set the bit for this email
  await redis.setbit(EMAIL_BITMAP_KEY, helpers.hash(email), 1)

  # check if domain already exists
  emailDns = await @findOne({ domain })

  if emailDns
    emailDns.frequency += 1
    return await emailDns.save()

  # new domain, perform dns check
  mxRecords = await getMXRecords(domain)
  provider = detectProvider(domain) or isCustomProviderDomain(domain, mxRecords)

  newEmailDns = new @({
    domain
    provider: provider or domain
    isValid: mxRecords.length > 0
    isCustomDomain: !!provider and provider isnt domain
    mxRecords
    frequency: 1
    firstSeen: (now = helpers.time())
    lastChecked: now
  })

  await newEmailDns.save()
  newEmailDns

EmailDns.statics.getTop = ({ limit = 50 } = {}) ->
  @find({ isValid: true })
    .sort({ frequency: -1 })
    .limit(limit)
    .lean()

EmailDns.statics.getDomainStats = ({ domain }) ->
  @findOne({ domain })

EmailDns.statics.batchVerify = ({ emails }) ->
  results = []
  for email in emails
    result = await @verifyDomain({ email })
    results.push(result)
  results

model = mongoose.model modelOpts.name, EmailDns
module.exports = EXPOSE(model)

