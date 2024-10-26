# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
{ log, L } = require './../lib/logger'
{ exit, env } = process

require './../lib/env'

{ mongoose, redis, connected } = require './../lib/database'

helpers = require './../lib/helpers'

_ = require 'lodash'

{
  AwsAccount
} = require './../models'

run = ->
  await connected()
  start = new Date

  newCred = new AwsAccount({
    name: 'My AWS Credential'
    AWS_ACCESS_KEY_ID: 'AKIAIOSFODNN7EXAMPLE'
    AWS_SECRET_ACCESS_KEY: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
    AWS_REGION: 'us-west-2'
  })

  result = await newCred.save()

  L 'Created new AWS Account', result

  foundItem = await AwsAccount.findOne({ _id: result._id })

  L 'Found AWS Account (decrypted)', foundItem.AWS_ACCESS_KEY_ID, foundItem.AWS_SECRET_ACCESS_KEY
  L 'AWS_ACCESS_KEY_ID', foundItem.AWS_SECRET_ACCESS_KEY

  return { elapsed: new Date() - start }

module.exports = {
  run
}

if !module.parent
  await run()
  exit 0

