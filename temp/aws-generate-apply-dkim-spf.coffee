# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
AWS = require 'aws-sdk'
crypto = require 'crypto'

# Configure AWS
AWS.config.update
  region: 'your-region'
  accessKeyId: 'your-access-key-id'
  secretAccessKey: 'your-secret-access-key'

route53 = new AWS.Route53()

domain = 'yourdomain.com'
hostedZoneId = 'your-hosted-zone-id'

generateDKIMKey = ->
  { privateKey, publicKey } = crypto.generateKeyPairSync 'rsa',
    modulusLength: 2048
    publicKeyEncoding:
      type: 'spki'
      format: 'pem'
    privateKeyEncoding:
      type: 'pkcs8'
      format: 'pem'

  publicKey
    .replace(/-----BEGIN PUBLIC KEY-----\n/, '')
    .replace(/\n-----END PUBLIC KEY-----\n/, '')
    .replace(/\n/g, '')

createDKIMRecords = ->
  try
    dkimSelector = 'default'  # You can change this if needed
    dkimKey = generateDKIMKey()

    dkimRecord = "v=DKIM1; k=rsa; p=#{dkimKey}"

    params =
      HostedZoneId: hostedZoneId
      ChangeBatch:
        Changes: [
          {
            Action: 'CREATE'
            ResourceRecordSet:
              Name: "#{dkimSelector}._domainkey.#{domain}"
              Type: 'TXT'
              TTL: 600
              ResourceRecords: [{ Value: "\"#{dkimRecord}\"" }]
          }
        ]

    await route53.changeResourceRecordSets(params).promise()
    console.log "DKIM record created successfully"
    console.log "DKIM Selector: #{dkimSelector}"
    console.log "DKIM Record: #{dkimRecord}"
  catch err
    console.error "Error creating DKIM record:", err

createSPFRecord = ->
  try
    spfRecord = "v=spf1 include:_spf.#{domain} ~all"

    params =
      HostedZoneId: hostedZoneId
      ChangeBatch:
        Changes: [
          {
            Action: 'CREATE'
            ResourceRecordSet:
              Name: domain
              Type: 'TXT'
              TTL: 600
              ResourceRecords: [{ Value: "\"#{spfRecord}\"" }]
          }
        ]

    await route53.changeResourceRecordSets(params).promise()
    console.log "SPF record created successfully"
    console.log "SPF Record: #{spfRecord}"
  catch err
    console.error "Error creating SPF record:", err

main = ->
  try
    await createDKIMRecords()
    await createSPFRecord()
    console.log "All operations completed successfully"
  catch err
    console.error "An error occurred:", err

# Execute the main function
main()
