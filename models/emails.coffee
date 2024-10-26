# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
# emails.coffee
{ log } = console
{ env } = process

{ mongoose, redis } = require './../lib/database'

Schema = mongoose.Schema
{ basePlugin, EXPOSE } = require './../lib/models'

helpers = require './../lib/helpers'

modelOpts = {
  name: 'Email'
  schema: {
    collection: 'emails'
    strict: false
  }
}

IGNORE_DOTS_PROVIDERS = [
  'gmail.com'
  'googlemail.com'
]

PLUS_PROVIDERS = [
  'gmail.com'
  'googlemail.com'
  'yahoo.com'
  'outlook.com'
  'hotmail.com'
  'live.com'
  'fastmail.com'
  'protonmail.com'
  'pm.me'
  'hey.com'
]

# these limits are used to determine when to mark an
# email as hardbounce or complaint
SETTINGS = {
  SOFT_BOUNCE_THRESHOLD: +(env.SOFT_BOUNCE_LIMIT ? 2)
  HARD_BOUNCE_THRESHOLD: +(env.HARD_BOUNCE_LIMIT ? 1)
  COMPLAINT_THRESHOLD: +(env.COMPLAINT_LIMIT ? 1)
}

Email = new Schema {

  email: {
    type: String
    required: true
    unique: true
    lowercase: true
    trim: true
    index: true
  }

  emailDomain: {
    type: String
    required: true
    lowercase: true
    trim: true
    index: true
  }

  md5: {
    type: String
    index: true
  }

  lists: [{
    type: String
    ref: 'List'
    index: true
  }]

  status: {
    type: String
    enum: [
      'active'
      'hardbounce'
      'softbounce'
      'complaint'
      'unsubscribe'
    ]
    default: 'active'
    index: true
  }

  data: {
    type: Schema.Types.Mixed
    default: {}
    select: false
  }

  bounces: {
    hard: { type: Number, default: 0 }
    soft: { type: Number, default: 0 }
  }

  sentCount: { type: Number, default: 0 }
  openCount: { type: Number, default: 0 }
  clickCount: { type: Number, default: 0 }
  conversionCount: { type: Number, default: 0 }

  timeLastSent: { type: Number, default: 0 }
  timeLastOpen: { type: Number, default: 0 }
  timeLastClick: { type: Number, default: 0 }
  timeLastConversion: { type: Number, default: 0 }

  revenue: { type: Number, default: 0 }

}, modelOpts.schema

Email.plugin(basePlugin)

Email.pre 'save', (next) ->
  if @isModified('email')
    try
      @email = @constructor._sanitize(@email)
      @emailDomain = @email.split('@')[1]
      @md5 = require('crypto').createHash('md5').update(@email).digest('hex')
    catch e
      return next(e)

  next()

Email.statics._sanitize = (email) ->
  try
    email = email.toLowerCase()
    [local, domain] = email.split('@')

    if not local? or not domain?
      throw new Error('Invalid email format')

    if domain in IGNORE_DOTS_PROVIDERS
      local = local.replace(/\./g, '')

    # handle plus addressing for supporting providers
    if domain in PLUS_PROVIDERS

      # handle different separator characters
      switch domain
        when 'fastmail.com'

          # fastmail uses # as separator
          local = local.split('#')[0]

        when 'outlook.com', 'hotmail.com', 'live.com'

          # outlook uses - as separator
          local = local.split('-')[0]

        else

          # most providers use + as separator
          local = local.split('+')[0]

    # reassemble
    sanitizedEmail = "#{local}@#{domain}"

    if not domain.includes('.')
      throw new Error('Invalid email domain')

    # final format validation
    emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

    if not emailRegex.test(sanitizedEmail)
      throw new Error('Invalid email format')

    return sanitizedEmail
  catch e
    throw e

# handle all actions on an email
# POST /emails/applyAction { email, action, revenue? }
Email.statics.applyAction = ({ email, action, revenue = 0 }) ->
  if action is 'unsubscribe'
    action = 'unsub'

  NEGATIVE_ACTIONS = [
    'unsub'
    'complaint'
    'hardbounce'
    'softbounce'
  ]

  POSITIVE_ACTIONS = [
    'sent'
    'open'
    'click'
    'conversion'
  ]

  if action not in [...NEGATIVE_ACTIONS, ...POSITIVE_ACTIONS]
    throw new Error('Invalid action type')

  try
    # sanitize/normalize the email first
    normalizedEmail = @_sanitize(email)

    # find or return error
    doc = await @findOne({ email: normalizedEmail })
    if not doc?
      throw new Error('Email not found')

    if doc.status != 'active'
      throw new Error('Email is not active')

    now = helpers.time()

    # handle negative actions
    if action in NEGATIVE_ACTIONS
      switch action
        when 'unsub'
          doc.status = 'unsubscribe'

        when 'complaint'
          doc.complaints += 1
          if doc.complaints >= SETTINGS.COMPLAINT_THRESHOLD
            doc.status = 'complaint'

        when 'hardbounce'
          doc.bounces.hard += 1
          if doc.bounces.hard >= SETTINGS.HARD_BOUNCE_THRESHOLD
            doc.status = 'hardbounce'

        when 'softbounce'
          doc.bounces.soft += 1
          if doc.bounces.soft >= SETTINGS.SOFT_BOUNCE_THRESHOLD
            doc.status = 'hardbounce'

    # handle positive actions
    else
      switch action
        when 'sent'
          doc.sentCount += 1
          doc.timeLastSent = now
        when 'open'
          doc.openCount += 1
          doc.timeLastOpen = now
        when 'click'
          doc.clickCount += 1
          doc.timeLastClick = now
        when 'conversion'
          doc.conversionCount += 1
          doc.timeLastConversion = now
          doc.revenue += +revenue || 0

    return await doc.save()
  catch e
    return e

model = mongoose.model modelOpts.name, Email
module.exports = EXPOSE(model)

