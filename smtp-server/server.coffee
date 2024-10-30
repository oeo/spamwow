# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
SMTPServer = require 'smtp-server'
simpleParser = require 'mailparser'
mongoose = require 'mongoose'
dns = require 'dns'

# Database connection
MONGO_URI = process.env.MONGO_URI ? 'mongodb://localhost/emaildb'
mongoose.connect MONGO_URI, useNewUrlParser: true, useUnifiedTopology: true

# Email schema
EmailSchema = new mongoose.Schema
  messageId: String
  from: String
  to: String
  subject: String
  text: String
  html: String
  date: Date
  attachments: Array
  bounceType: String
  bounceSubType: String
  diagnosticCode: String
  reportingMTA: String
  originalRecipient: String
  isBounce: Boolean
  isComplaint: Boolean
  isAutoReply: Boolean

Email = mongoose.model 'Email', EmailSchema

# Function to parse bounce messages
parseBounce = (parsedMail) ->
  bounce =
    isBounce: false
    bounceType: null
    bounceSubType: null
    diagnosticCode: null
    reportingMTA: null
    originalRecipient: null

  # Check for standard DSN (Delivery Status Notification)
  if parsedMail.attachments?.length > 0
    dsnAttachment = parsedMail.attachments.find (att) -> att.contentType == 'message/delivery-status'
    if dsnAttachment
      dsnContent = dsnAttachment.content.toString()
      bounce.isBounce = true
      bounce.bounceType = if dsnContent.includes('Action: failed') then 'hard' else 'soft'
      bounce.diagnosticCode = dsnContent.match(/Diagnostic-Code: (.+)/)?[1]
      bounce.reportingMTA = dsnContent.match(/Reporting-MTA: (.+)/)?[1]
      bounce.originalRecipient = dsnContent.match(/Original-Recipient: (.+)/)?[1]

  # Check for bounce indicators in the subject
  if parsedMail.subject?.toLowerCase().includes('undelivered') or
     parsedMail.subject?.toLowerCase().includes('failed delivery')
    bounce.isBounce = true
    bounce.bounceType = 'soft' # Assume soft bounce unless we can determine it's hard

  # Check for auto-reply indicators
  if parsedMail.subject?.toLowerCase().includes('auto') or
     parsedMail.subject?.toLowerCase().includes('automatic reply')
    bounce.isAutoReply = true

  bounce

# Function to check if the sender is authenticated
isAuthenticatedSender = (email) ->
  new Promise (resolve, reject) ->
    domain = email.split('@')[1]
    dns.resolveTxt domain, (err, records) ->
      if err
        reject err
      else
        spfRecord = records.find (record) -> record[0].startsWith('v=spf1')
        resolve !!spfRecord

# SMTP server options
options =
  secure: false
  authOptional: true
  onData: (stream, session, callback) ->
    mailParser = new simpleParser()
    mailParser.on 'end', (parsedMail) ->
      bounceInfo = parseBounce(parsedMail)

      isAuthenticated = await isAuthenticatedSender(parsedMail.from.value[0].address)

      email = new Email
        messageId: parsedMail.messageId
        from: parsedMail.from.text
        to: parsedMail.to.text
        subject: parsedMail.subject
        text: parsedMail.text
        html: parsedMail.html
        date: parsedMail.date
        attachments: parsedMail.attachments
        isBounce: bounceInfo.isBounce
        isComplaint: parsedMail.subject?.toLowerCase().includes('complaint')
        isAutoReply: bounceInfo.isAutoReply
        bounceType: bounceInfo.bounceType
        bounceSubType: bounceInfo.bounceSubType
        diagnosticCode: bounceInfo.diagnosticCode
        reportingMTA: bounceInfo.reportingMTA
        originalRecipient: bounceInfo.originalRecipient

      email.save (err) ->
        if err
          console.error 'Error saving email:', err
        else
          console.log 'Email saved successfully'
          if bounceInfo.isBounce
            console.log 'Bounce detected:', bounceInfo
          if !isAuthenticated
            console.log 'Warning: Unauthenticated sender:', parsedMail.from.text
        callback()

    stream.pipe mailParser

# Create and start the SMTP server
server = new SMTPServer options
server.listen (PORT = process.env.PORT ? 25), ->
  console.log 'SMTP Server running on port ' + PORT

